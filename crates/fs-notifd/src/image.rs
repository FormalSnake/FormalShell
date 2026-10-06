use zbus::zvariant::{OwnedValue, Value};

/// Pixels as 8-bit RGBA, rows tightly packed (`rgba.len() == width * height * 4`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImageData {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Image {
    Data(ImageData),
    /// An absolute path (a `file://` prefix is stripped) or an icon name.
    Path(String),
}

/// Decodes the spec's `(iiibiiay)` image struct: width, height, rowstride,
/// has_alpha, bits per sample, channels, data.
///
/// Rowstride is honoured, unlike Quickshell, which only warns when it differs
/// from `width * channels`: GdkPixbuf-based senders pad rows. Anything that is
/// not 8-bit RGB or RGBA, or whose buffer is too short, decodes to `None`.
pub(crate) fn decode(value: &OwnedValue) -> Option<ImageData> {
    let value: &Value = value;
    let Value::Structure(s) = value else { return None };
    let f = s.fields();
    if f.len() != 7 {
        return None;
    }
    let int = |i: usize| f[i].downcast_ref::<i32>().ok();
    let (w, h, stride) = (int(0)?, int(1)?, int(2)?);
    let has_alpha = f[3].downcast_ref::<bool>().ok()?;
    let (bits, channels) = (int(4)?, int(5)?);
    let Value::Array(arr) = &f[6] else { return None };
    let data: Vec<u8> = arr.iter().map(|v| v.downcast_ref::<u8>().ok()).collect::<Option<_>>()?;

    if bits != 8 || channels != if has_alpha { 4 } else { 3 } || w <= 0 || h <= 0 || stride < 0 {
        return None;
    }
    let (w, h, stride, ch) = (w as usize, h as usize, stride as usize, channels as usize);
    if stride < w * ch || data.len() < stride * (h - 1) + w * ch {
        return None;
    }

    let mut rgba = Vec::with_capacity(w * h * 4);
    for row in 0..h {
        let line = &data[row * stride..row * stride + w * ch];
        if has_alpha {
            rgba.extend_from_slice(line);
        } else {
            for x in 0..w {
                rgba.extend_from_slice(&line[x * 3..x * 3 + 3]);
                rgba.push(255);
            }
        }
    }
    Some(ImageData { width: w as u32, height: h as u32, rgba })
}
