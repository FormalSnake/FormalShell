//! The desktop's picture (Background.qml): the wallpaper decoded and
//! cover-cropped to the output on the pool, handed to the UI thread as
//! ready pixels, through the retro dither pass (DitherImage.qml) when
//! `wallpaper.dither` asks for it. The backdrop crossfades between two of
//! these.

use std::sync::{Arc, OnceLock};

use image::imageops::{self, FilterType};

use crate::runtime::Ctx;
use crate::store;

/// One output's picture, rows of wl_shm ARGB8888 (BGRA in memory).
pub struct Picture {
    pub path: String,
    /// The palette size the pass quantized to, none for the plain image.
    pub dither: Option<usize>,
    pub width: u32,
    pub height: u32,
    pub bgra: Vec<u8>,
}

#[derive(Default)]
pub struct State {
    pub picture: Option<Arc<Picture>>,
}

pub struct Diff(pub Option<Arc<Picture>>);

impl State {
    pub fn apply(&mut self, Diff(picture): Diff) -> bool {
        let same = match (&self.picture, &picture) {
            (Some(a), Some(b)) => Arc::ptr_eq(a, b),
            (None, None) => true,
            _ => false,
        };
        self.picture = picture;
        !same
    }
}

type Request = (String, u32, u32, Option<usize>);

static REQUESTS: OnceLock<async_channel::Sender<Request>> = OnceLock::new();

/// The wallpaper at `path` for an output `width` by `height`, dithered to
/// `dither` colours when set.
pub fn show(path: &str, width: u32, height: u32, dither: Option<usize>) {
    if let Some(tx) = REQUESTS.get() {
        let _ = tx.try_send((path.to_owned(), width, height, dither));
    }
}

/// DitherImage.qml's retro mode: the output sampled on a `chunk` grid at
/// each cell's centre, a palette of the image's own colours, and every cell
/// painted as one hard-edged square of its quantized entry.
fn dither(img: &mut image::RgbaImage, colors: usize) {
    let (w, h) = (img.width() as usize, img.height() as usize);
    let chunk = ((w.max(h) as f64 / 480.0).round() as usize).max(2);
    let (gw, gh) = (w.div_ceil(chunk), h.div_ceil(chunk));
    let mut cells = Vec::with_capacity(gw * gh * 3);
    for gy in 0..gh {
        let cy = (gy * chunk + chunk / 2).min(h - 1) as u32;
        for gx in 0..gw {
            let cx = (gx * chunk + chunk / 2).min(w - 1) as u32;
            let p = img.get_pixel(cx, cy).0;
            cells.extend_from_slice(&p[..3]);
        }
    }
    let pal = fs_chrome::dither::palette(&cells, gw * gh, colors);
    let idx = fs_chrome::dither::quantize(&cells, gw * gh, gw, &pal);
    if pal.is_empty() {
        return;
    }
    for (y, row) in img.rows_mut().enumerate() {
        let gy = y / chunk;
        for (x, px) in row.enumerate() {
            let e = idx[gy * gw + x / chunk] as usize * 3;
            px.0 = [pal[e], pal[e + 1], pal[e + 2], 255];
        }
    }
}

/// Background.qml's `PreserveAspectCrop`: scaled to cover, centred.
fn render(path: &str, width: u32, height: u32, colors: Option<usize>) -> Option<Picture> {
    let img = image::open(path).ok()?.to_rgba8();
    let (iw, ih) = (img.width() as f64, img.height() as f64);
    let scale = (width as f64 / iw).max(height as f64 / ih);
    let (cw, ch) = ((width as f64 / scale).round().max(1.0) as u32, (height as f64 / scale).round().max(1.0) as u32);
    let (cx, cy) = ((img.width().saturating_sub(cw)) / 2, (img.height().saturating_sub(ch)) / 2);
    let crop = imageops::crop_imm(&img, cx, cy, cw.min(img.width()), ch.min(img.height())).to_image();
    let mut out = imageops::resize(&crop, width, height, FilterType::Triangle);
    if let Some(n) = colors {
        dither(&mut out, n);
    }
    let mut bgra = Vec::with_capacity((width * height * 4) as usize);
    for px in out.pixels() {
        let [r, g, b, _] = px.0;
        bgra.extend_from_slice(&[b, g, r, 255]);
    }
    Some(Picture { path: path.to_owned(), dither: colors, width, height, bgra })
}

pub async fn run(ctx: Ctx) {
    let (tx, rx) = async_channel::unbounded();
    let _ = REQUESTS.set(tx);
    let mut last = None;
    while let Ok(mut request) = rx.recv().await {
        while let Ok(newer) = rx.try_recv() {
            request = newer;
        }
        if last.as_ref() == Some(&request) || request.1 == 0 || request.2 == 0 {
            continue;
        }
        last = Some(request.clone());
        let (path, w, h, colors) = request;
        let picture = if path.is_empty() {
            None
        } else {
            ctx.pool().run(move || render(&path, w, h, colors)).await.flatten().map(Arc::new)
        };
        ctx.publish(store::Diff::Wallpaper(Diff(picture)));
    }
}
