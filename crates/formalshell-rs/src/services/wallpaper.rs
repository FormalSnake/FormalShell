//! The desktop's picture (Background.qml): the wallpaper decoded and
//! cover-cropped to the output on the pool, handed to the UI thread as
//! ready pixels. The crossfade and the dither pass land with the wallpaper
//! picker.

use std::sync::{Arc, OnceLock};

use image::imageops::{self, FilterType};

use crate::runtime::Ctx;
use crate::store;

/// One output's picture, rows of wl_shm ARGB8888 (BGRA in memory).
pub struct Picture {
    pub path: String,
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

static REQUESTS: OnceLock<async_channel::Sender<(String, u32, u32)>> = OnceLock::new();

/// The wallpaper at `path` for an output `width` by `height`.
pub fn show(path: &str, width: u32, height: u32) {
    if let Some(tx) = REQUESTS.get() {
        let _ = tx.try_send((path.to_owned(), width, height));
    }
}

/// Background.qml's `PreserveAspectCrop`: scaled to cover, centred.
fn render(path: &str, width: u32, height: u32) -> Option<Picture> {
    let img = image::open(path).ok()?.to_rgba8();
    let (iw, ih) = (img.width() as f64, img.height() as f64);
    let scale = (width as f64 / iw).max(height as f64 / ih);
    let (cw, ch) = ((width as f64 / scale).round().max(1.0) as u32, (height as f64 / scale).round().max(1.0) as u32);
    let (cx, cy) = ((img.width().saturating_sub(cw)) / 2, (img.height().saturating_sub(ch)) / 2);
    let crop = imageops::crop_imm(&img, cx, cy, cw.min(img.width()), ch.min(img.height())).to_image();
    let out = imageops::resize(&crop, width, height, FilterType::Triangle);
    let mut bgra = Vec::with_capacity((width * height * 4) as usize);
    for px in out.pixels() {
        let [r, g, b, _] = px.0;
        bgra.extend_from_slice(&[b, g, r, 255]);
    }
    Some(Picture { path: path.to_owned(), width, height, bgra })
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
        let (path, w, h) = request;
        let picture = if path.is_empty() {
            None
        } else {
            ctx.pool().run(move || render(&path, w, h)).await.flatten().map(Arc::new)
        };
        ctx.publish(store::Diff::Wallpaper(Diff(picture)));
    }
}
