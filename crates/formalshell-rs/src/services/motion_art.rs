//! Apple Music's animated cover (AppleMusicArtService.qml, AnimatedAlbumArt.qml):
//! behind `media.appleMusicArt`, the track's album is looked up over the
//! undocumented chain fs-media's `applemusic` parses (iTunes artist search,
//! that artist's albums, a scraped web-player token, amp-api's editorial
//! video, the HLS playlists, one progressive mp4) and the mp4 kept under
//! `$XDG_CACHE_HOME/formalshell/applemusic-art`. While the media panel shows
//! the cover, an ffmpeg child decodes that mp4 to raw frames at the QML grab
//! timer's ~8 fps, cropped to the slot; each frame is rounded on the pool
//! and published to the store. A paused track stops the child where it is
//! and keeps its last frame; the panel closing kills it.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use async_io::Timer;
use fs_media::applemusic as am;
use futures_lite::AsyncReadExt;

use super::media;
use crate::runtime::Ctx;
use crate::scene::Bitmap;
use crate::store;

/// AnimatedAlbumArt.qml's 120 ms grab timer.
const FPS: &str = "25/3";
/// The lookup waits out a track skipped straight past (`_debounce`).
const DEBOUNCE: Duration = Duration::from_millis(1500);
/// Cached artwork older than this is pruned (`_prune`).
const MAX_AGE_DAYS: f64 = 30.0;
const CURL: [&str; 10] = ["-sS", "--fail", "-L", "--max-redirs", "5", "--connect-timeout", "5", "--max-time", "20", "--compressed"];

/// What the panel's cover slot asks for while it is on screen.
#[derive(Clone, Debug, PartialEq)]
pub struct Want {
    pub artist: String,
    pub album: String,
    pub size: u32,
    pub radius: f64,
    pub playing: bool,
}

impl Want {
    pub fn key(&self) -> String {
        am::cache_key(&self.artist, &self.album)
    }
}

static WANT: OnceLock<async_channel::Sender<Option<Want>>> = OnceLock::new();
static LAST: Mutex<Option<Option<Want>>> = Mutex::new(None);

/// The panel's slot, or none once it is gone. Repeats are dropped here, so
/// the panel may say it on every draw.
pub fn want(w: Option<Want>) {
    let Ok(mut last) = LAST.lock() else { return };
    if last.as_ref() == Some(&w) {
        return;
    }
    *last = Some(w.clone());
    if let Some(tx) = WANT.get() {
        let _ = tx.try_send(w);
    }
}

fn cache_dir() -> String {
    let base = std::env::var("XDG_CACHE_HOME").ok().filter(|d| !d.is_empty()).unwrap_or_else(|| format!("{}/.cache", std::env::var("HOME").unwrap_or_default()));
    format!("{base}/formalshell/applemusic-art")
}

/// The decode running for one slot: the child's pid, the flag that holds
/// it after the frame in flight (a pause) and the one that ends its reader.
struct Decode {
    key: String,
    size: u32,
    pid: Arc<AtomicI32>,
    hold: Arc<AtomicBool>,
    stop: Arc<AtomicBool>,
}

fn signal(pid: &AtomicI32, sig: i32) {
    let pid = pid.load(Ordering::Relaxed);
    if pid > 0 {
        // SAFETY: kill(2) on our own child's pid, which the reader keeps
        // unreaped until it has cleared it here.
        unsafe { libc::kill(pid, sig) };
    }
}

impl Decode {
    fn set_playing(&self, playing: bool) {
        if self.hold.swap(!playing, Ordering::Relaxed) && playing {
            signal(&self.pid, libc::SIGCONT);
        }
    }

    fn end(self) {
        self.stop.store(true, Ordering::Relaxed);
        signal(&self.pid, libc::SIGKILL);
    }
}

pub async fn run(ctx: Ctx) {
    let (tx, rx) = async_channel::unbounded();
    let _ = WANT.set(tx);
    let dir = cache_dir();
    prune(&dir).await;
    // A key's mp4, or none for an album Apple has no motion art for.
    let mut found: HashMap<String, Option<String>> = HashMap::new();
    let mut token = String::new();
    let mut decode: Option<Decode> = None;
    while let Ok(mut w) = rx.recv().await {
        while let Ok(next) = rx.try_recv() {
            w = next;
        }
        let Some(w) = w else {
            if let Some(d) = decode.take() {
                d.end();
            }
            ctx.publish(store::Diff::Media(media::Diff::Motion(None)));
            continue;
        };
        let key = w.key();
        if let Some(d) = decode.as_ref().filter(|d| d.key == key && d.size == w.size) {
            d.set_playing(w.playing);
            continue;
        }
        if let Some(d) = decode.take() {
            d.end();
        }
        ctx.publish(store::Diff::Media(media::Diff::Motion(None)));
        let path = match found.get(&key) {
            Some(p) => p.clone(),
            None => {
                let path = format!("{dir}/{key}.mp4");
                let on_disk = std::fs::metadata(&path).is_ok_and(|m| m.len() > 0);
                if on_disk {
                    Some(path)
                } else {
                    Timer::after(DEBOUNCE).await;
                    if !rx.is_empty() {
                        // Something newer is waiting; it decides.
                        continue;
                    }
                    match lookup(&w, &dir, &key, &mut token).await {
                        Ok(p) => p,
                        Err(why) => {
                            eprintln!("AppleMusicArtService: {why}");
                            continue;
                        }
                    }
                }
            }
        };
        found.insert(key.clone(), path.clone());
        let Some(path) = path.filter(|_| rx.is_empty()) else { continue };
        // A paused track still shows its first frame, then holds it.
        let d = Decode {
            key: key.clone(),
            size: w.size,
            pid: Arc::new(AtomicI32::new(0)),
            hold: Arc::new(AtomicBool::new(!w.playing)),
            stop: Arc::new(AtomicBool::new(false)),
        };
        ctx.spawn(frames(ctx.clone(), key, path, (w.size, w.radius), d.pid.clone(), d.hold.clone(), d.stop.clone()));
        decode = Some(d);
    }
}

/// The ffmpeg argv for one slot: decoded on the CPU, looped, paced to
/// real time, cropped to a `size` square, raw RGBA on stdout.
fn ffmpeg_args(path: &str, size: u32) -> Vec<String> {
    let filter = format!("fps={FPS},scale={size}:{size}:force_original_aspect_ratio=increase,crop={size}:{size}");
    ["-nostdin", "-hide_banner", "-loglevel", "error", "-re", "-stream_loop", "-1", "-i", path, "-an", "-vf", &filter, "-f", "rawvideo", "-pix_fmt", "rgba", "-"]
        .iter()
        .map(|s| (*s).to_owned())
        .collect()
}

async fn frames(ctx: Ctx, key: String, path: String, (size, radius): (u32, f64), pid: Arc<AtomicI32>, hold: Arc<AtomicBool>, stop: Arc<AtomicBool>) {
    let child = async_process::Command::new("ffmpeg")
        .args(ffmpeg_args(&path, size))
        .stdin(async_process::Stdio::null())
        .stdout(async_process::Stdio::piped())
        .stderr(async_process::Stdio::null())
        .kill_on_drop(true)
        .spawn();
    let mut child = match child {
        Ok(c) => c,
        Err(e) => {
            eprintln!("AppleMusicArtService: ffmpeg did not start: {e}");
            return;
        }
    };
    pid.store(child.id() as i32, Ordering::Relaxed);
    if stop.load(Ordering::Relaxed) {
        return;
    }
    let Some(mut out) = child.stdout.take() else { return };
    let mut buf = vec![0u8; (size * size * 4) as usize];
    let key_size = size;
    while out.read_exact(&mut buf).await.is_ok() {
        if stop.load(Ordering::Relaxed) {
            break;
        }
        let raw = buf.clone();
        let bitmap = ctx.pool().run(move || frame(raw, key_size, radius)).await.flatten();
        if stop.load(Ordering::Relaxed) {
            break;
        }
        if let Some(b) = bitmap {
            ctx.publish(store::Diff::Media(media::Diff::Motion(Some((key.clone(), b)))));
        }
        if hold.load(Ordering::Relaxed) {
            signal(&pid, libc::SIGSTOP);
        }
    }
    pid.store(0, Ordering::Relaxed);
    let _ = child.kill();
    let _ = child.status().await;
}

/// One raw frame as the cover draws it: corners cut to the slot's radius.
fn frame(raw: Vec<u8>, size: u32, radius: f64) -> Option<Bitmap> {
    let mut img = image::RgbaImage::from_raw(size, size, raw)?;
    super::cover::round_corners(&mut img, radius);
    let side = u16::try_from(size).ok()?;
    Some(Bitmap::from_rgba(side, side, img.into_raw()))
}

async fn curl(args: &[&str]) -> (i32, String) {
    let out = async_process::Command::new("curl")
        .args(CURL)
        .args(args)
        .stdin(async_process::Stdio::null())
        .stderr(async_process::Stdio::null())
        .kill_on_drop(true)
        .output()
        .await;
    match out {
        Ok(o) => (o.status.code().unwrap_or(-1), String::from_utf8_lossy(&o.stdout).into_owned()),
        Err(_) => (-1, String::new()),
    }
}

/// The chain for one album: its mp4 on disk, `Ok(None)` for an album with
/// no motion art (cached as such), `Err` for a failure worth retrying.
async fn lookup(w: &Want, dir: &str, key: &str, token: &mut String) -> Result<Option<String>, &'static str> {
    let Some(url) = am::artist_search_url(&w.artist) else { return Ok(None) };
    let (code, out) = curl(&[&url]).await;
    let Some(artist) = am::parse_artist_search_result(code, &out, &w.artist).map_err(|_| "itunes artist search failed")? else { return Ok(None) };
    let (code, out) = curl(&[&am::artist_albums_url(artist)]).await;
    let Some(collection) = am::parse_artist_albums_result(code, &out, &w.album).map_err(|_| "itunes album lookup failed")? else { return Ok(None) };
    if token.is_empty() {
        let (code, html) = curl(&[&am::album_page_url(collection)]).await;
        if code != 0 {
            return Err("web-player page fetch failed");
        }
        let asset = am::extract_asset_path(&html).ok_or("no asset bundle referenced by album page")?;
        let (code, bundle) = curl(&[&format!("https://music.apple.com{asset}")]).await;
        if code != 0 {
            return Err("asset bundle fetch failed");
        }
        *token = am::extract_token(&bundle).ok_or("no web-player token found in asset bundle")?;
    }
    let auth = format!("Authorization: Bearer {token}");
    let (code, out) = curl(&["-H", &auth, "-H", "Origin: https://music.apple.com", &am::amp_api_url(collection)]).await;
    let video = match am::parse_editorial_video(code, &out) {
        Ok(v) => v,
        Err(e) => {
            if e == am::ParseError::HttpError {
                token.clear();
            }
            return Err("editorial video lookup failed");
        }
    };
    if video.is_empty() {
        return Ok(None);
    }
    let (code, master) = curl(&[&video]).await;
    if code != 0 {
        return Err("master playlist fetch failed");
    }
    let Some(variant) = am::pick_variant(&master) else { return Ok(None) };
    let variant = am::resolve_url(&variant, &video);
    let (code, rendition) = curl(&[&variant]).await;
    if code != 0 {
        return Err("rendition playlist fetch failed");
    }
    let Some(mp4) = am::extract_mp4_url(&rendition, &variant) else { return Ok(None) };
    std::fs::create_dir_all(dir).map_err(|_| "could not create cache dir")?;
    let path = format!("{dir}/{key}.mp4");
    let part = format!("{path}.{}.part", std::process::id());
    let ok = async_process::Command::new("curl")
        .args(["-sSf", "-L", "--max-redirs", "5", "--connect-timeout", "5", "--max-time", "60", "-o", &part, "--", &mp4])
        .stdin(async_process::Stdio::null())
        .stderr(async_process::Stdio::null())
        .kill_on_drop(true)
        .status()
        .await
        .is_ok_and(|s| s.success());
    if !ok {
        let _ = std::fs::remove_file(&part);
        return Err("artwork download failed");
    }
    std::fs::rename(&part, &path).map_err(|_| "could not install downloaded artwork")?;
    Ok(Some(path))
}

/// Drops cached artwork older than a month.
async fn prune(dir: &str) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    let now = crate::services::notifications::now_ms() as f64;
    for e in entries.flatten() {
        let Ok(meta) = e.metadata() else { continue };
        let Some(mtime) = meta.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()) else { continue };
        if meta.is_file() && am::is_stale(mtime.as_secs_f64() * 1000.0, now, MAX_AGE_DAYS) {
            let _ = std::fs::remove_file(e.path());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_decode_is_looped_paced_and_cropped_to_the_slot() {
        let args = ffmpeg_args("/c/a.mp4", 96).join(" ");
        assert!(args.contains("-re -stream_loop -1 -i /c/a.mp4"), "{args}");
        assert!(args.contains("fps=25/3,scale=96:96:force_original_aspect_ratio=increase,crop=96:96"), "{args}");
        assert!(args.ends_with("-f rawvideo -pix_fmt rgba -"), "{args}");
    }

    #[test]
    fn a_raw_frame_becomes_a_rounded_square() {
        let b = frame(vec![255; 16 * 16 * 4], 16, 4.0).unwrap();
        let px = b.pixmap.data_as_u8_slice();
        assert_eq!(px[3], 0, "the corner is cut");
        assert_eq!(px[((8 * 16) + 8) * 4 + 3], 255);
        assert!(frame(vec![0; 10], 16, 0.0).is_none(), "a short read is no frame");
    }
}
