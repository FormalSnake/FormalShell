//! The V4L2 capture interface by hand: no crate covers it without bindgen
//! at build time (`v4l2-sys-mit` runs it, so it would need libclang and the
//! kernel headers in every build), and the mirror needs a dozen ioctls.
//! Struct layouts are the kernel's uapi `videodev2.h` on a 64-bit target.

use std::ffi::CString;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};

const fn ioc(dir: u64, nr: u64, size: usize) -> u64 {
    (dir << 30) | ((size as u64) << 16) | ((b'V' as u64) << 8) | nr
}
const R: u64 = 2;
const W: u64 = 1;

const QUERYCAP: u64 = ioc(R, 0, std::mem::size_of::<Capability>());
const ENUM_FMT: u64 = ioc(R | W, 2, std::mem::size_of::<FmtDesc>());
const G_FMT: u64 = ioc(R | W, 4, std::mem::size_of::<Format>());
const S_FMT: u64 = ioc(R | W, 5, std::mem::size_of::<Format>());
const REQBUFS: u64 = ioc(R | W, 8, std::mem::size_of::<RequestBuffers>());
const QUERYBUF: u64 = ioc(R | W, 9, std::mem::size_of::<Buffer>());
const QBUF: u64 = ioc(R | W, 15, std::mem::size_of::<Buffer>());
const DQBUF: u64 = ioc(R | W, 17, std::mem::size_of::<Buffer>());
const STREAMON: u64 = ioc(W, 18, std::mem::size_of::<i32>());
const STREAMOFF: u64 = ioc(W, 19, std::mem::size_of::<i32>());

const BUF_TYPE_VIDEO_CAPTURE: u32 = 1;
const MEMORY_MMAP: u32 = 1;
const CAP_VIDEO_CAPTURE: u32 = 0x0000_0001;
const CAP_STREAMING: u32 = 0x0400_0000;
const CAP_DEVICE_CAPS: u32 = 0x8000_0000;

pub const fn fourcc(s: &[u8; 4]) -> u32 {
    (s[0] as u32) | ((s[1] as u32) << 8) | ((s[2] as u32) << 16) | ((s[3] as u32) << 24)
}
pub const YUYV: u32 = fourcc(b"YUYV");
pub const MJPG: u32 = fourcc(b"MJPG");
pub const GREY: u32 = fourcc(b"GREY");
pub const Y16: u32 = fourcc(b"Y16 ");

#[repr(C)]
struct Capability {
    driver: [u8; 16],
    card: [u8; 32],
    bus_info: [u8; 32],
    version: u32,
    capabilities: u32,
    device_caps: u32,
    reserved: [u32; 3],
}

#[repr(C)]
struct FmtDesc {
    index: u32,
    kind: u32,
    flags: u32,
    description: [u8; 32],
    pixelformat: u32,
    mbus_code: u32,
    reserved: [u32; 3],
}

#[repr(C)]
#[derive(Clone, Copy)]
struct PixFormat {
    width: u32,
    height: u32,
    pixelformat: u32,
    field: u32,
    bytesperline: u32,
    sizeimage: u32,
    colorspace: u32,
    private: u32,
    flags: u32,
    ycbcr_enc: u32,
    quantization: u32,
    xfer_func: u32,
}

/// `struct v4l2_format`: the union is 200 bytes and pointer aligned.
#[repr(C)]
struct Format {
    kind: u32,
    pad: u32,
    pix: PixFormat,
    rest: [u8; 200 - std::mem::size_of::<PixFormat>()],
}

#[repr(C)]
struct RequestBuffers {
    count: u32,
    kind: u32,
    memory: u32,
    capabilities: u32,
    flags: u8,
    reserved: [u8; 3],
}

#[repr(C)]
struct Buffer {
    index: u32,
    kind: u32,
    bytesused: u32,
    flags: u32,
    field: u32,
    pad: u32,
    timestamp: [i64; 2],
    timecode: [u8; 16],
    sequence: u32,
    memory: u32,
    offset: u64,
    length: u32,
    reserved2: u32,
    request_fd: u32,
    pad2: u32,
}

const _: () = assert!(std::mem::size_of::<Capability>() == 104);
const _: () = assert!(std::mem::size_of::<FmtDesc>() == 64);
const _: () = assert!(std::mem::size_of::<Format>() == 208);
const _: () = assert!(std::mem::size_of::<RequestBuffers>() == 20);
const _: () = assert!(std::mem::size_of::<Buffer>() == 88);

fn zeroed<T>() -> T {
    // SAFETY: every struct here is plain integers, valid all zero.
    unsafe { std::mem::zeroed() }
}

fn ioctl<T>(fd: &OwnedFd, request: u64, arg: &mut T) -> std::io::Result<()> {
    loop {
        // SAFETY: `arg` is the struct the request's size field names.
        let r = unsafe { libc::ioctl(fd.as_raw_fd(), request as _, arg as *mut T) };
        if r >= 0 {
            return Ok(());
        }
        let err = std::io::Error::last_os_error();
        if err.kind() != std::io::ErrorKind::Interrupted {
            return Err(err);
        }
    }
}

fn open(path: &str) -> std::io::Result<OwnedFd> {
    let c = CString::new(path).map_err(|_| std::io::Error::from(std::io::ErrorKind::InvalidInput))?;
    // SAFETY: a NUL-terminated path; the fd is owned from here on.
    let fd = unsafe { libc::open(c.as_ptr(), libc::O_RDWR | libc::O_NONBLOCK | libc::O_CLOEXEC) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error());
    }
    // SAFETY: just opened, nothing else holds it.
    Ok(unsafe { OwnedFd::from_raw_fd(fd) })
}

fn cstr(bytes: &[u8]) -> String {
    let end = bytes.iter().position(|b| *b == 0).unwrap_or(bytes.len());
    String::from_utf8_lossy(&bytes[..end]).into_owned()
}

/// A capture node: its path, card name and pixel formats.
pub struct Node {
    pub path: String,
    pub card: String,
    pub formats: Vec<u32>,
}

/// Every `/dev/video*` that captures, each opened and closed again.
pub fn list() -> Vec<Node> {
    let Ok(dir) = std::fs::read_dir("/dev") else { return Vec::new() };
    let mut out = Vec::new();
    for entry in dir.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if !name.starts_with("video") {
            continue;
        }
        let path = format!("/dev/{name}");
        let Ok(fd) = open(&path) else { continue };
        let mut cap: Capability = zeroed();
        if ioctl(&fd, QUERYCAP, &mut cap).is_err() {
            continue;
        }
        let caps = if cap.capabilities & CAP_DEVICE_CAPS != 0 { cap.device_caps } else { cap.capabilities };
        if caps & CAP_VIDEO_CAPTURE == 0 || caps & CAP_STREAMING == 0 {
            continue;
        }
        let mut formats = Vec::new();
        for index in 0..32 {
            let mut d: FmtDesc = zeroed();
            d.index = index;
            d.kind = BUF_TYPE_VIDEO_CAPTURE;
            if ioctl(&fd, ENUM_FMT, &mut d).is_err() {
                break;
            }
            formats.push(d.pixelformat);
        }
        out.push(Node { path, card: cstr(&cap.card), formats });
    }
    out
}

/// One frame as the driver delivered it.
pub struct Frame<'a> {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub format: u32,
    pub data: &'a [u8],
}

/// An open, streaming capture node; dropping it stops the stream and
/// releases the buffers and the descriptor.
pub struct Stream {
    fd: OwnedFd,
    maps: Vec<(*mut libc::c_void, usize)>,
    pix: PixFormat,
}

// SAFETY: the mappings belong to this stream alone and move with it.
unsafe impl Send for Stream {}

impl Stream {
    pub fn open(path: &str, prefer: &[u32]) -> std::io::Result<Self> {
        let fd = open(path)?;
        let mut fmt: Format = zeroed();
        fmt.kind = BUF_TYPE_VIDEO_CAPTURE;
        ioctl(&fd, G_FMT, &mut fmt)?;
        if !prefer.contains(&fmt.pix.pixelformat) {
            for p in prefer {
                let mut want: Format = zeroed();
                want.kind = BUF_TYPE_VIDEO_CAPTURE;
                want.pix = fmt.pix;
                want.pix.pixelformat = *p;
                if ioctl(&fd, S_FMT, &mut want).is_ok() && want.pix.pixelformat == *p {
                    fmt = want;
                    break;
                }
            }
        }
        let mut req: RequestBuffers = zeroed();
        req.count = 4;
        req.kind = BUF_TYPE_VIDEO_CAPTURE;
        req.memory = MEMORY_MMAP;
        ioctl(&fd, REQBUFS, &mut req)?;
        let mut stream = Stream { fd, maps: Vec::new(), pix: fmt.pix };
        for index in 0..req.count {
            let mut b: Buffer = zeroed();
            b.index = index;
            b.kind = BUF_TYPE_VIDEO_CAPTURE;
            b.memory = MEMORY_MMAP;
            ioctl(&stream.fd, QUERYBUF, &mut b)?;
            // SAFETY: the driver's own offset and length for this buffer.
            let ptr = unsafe {
                libc::mmap(std::ptr::null_mut(), b.length as usize, libc::PROT_READ, libc::MAP_SHARED, stream.fd.as_raw_fd(), b.offset as libc::off_t)
            };
            if ptr == libc::MAP_FAILED {
                return Err(std::io::Error::last_os_error());
            }
            stream.maps.push((ptr, b.length as usize));
            ioctl(&stream.fd, QBUF, &mut b)?;
        }
        let mut kind = BUF_TYPE_VIDEO_CAPTURE as i32;
        ioctl(&stream.fd, STREAMON, &mut kind)?;
        Ok(stream)
    }

    pub fn format(&self) -> u32 {
        self.pix.pixelformat
    }

    /// Waits up to `timeout_ms` for a frame and hands it to `f`; false on a
    /// timeout.
    pub fn next(&mut self, timeout_ms: i32, f: &mut dyn FnMut(Frame)) -> std::io::Result<bool> {
        let mut pfd = libc::pollfd { fd: self.fd.as_raw_fd(), events: libc::POLLIN, revents: 0 };
        // SAFETY: one pollfd for our own descriptor.
        let r = unsafe { libc::poll(&mut pfd, 1, timeout_ms) };
        if r <= 0 {
            return Ok(false);
        }
        let mut b: Buffer = zeroed();
        b.kind = BUF_TYPE_VIDEO_CAPTURE;
        b.memory = MEMORY_MMAP;
        match ioctl(&self.fd, DQBUF, &mut b) {
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => return Ok(false),
            r => r?,
        }
        if let Some((ptr, len)) = self.maps.get(b.index as usize) {
            let used = (b.bytesused as usize).min(*len);
            // SAFETY: a mapping we own, dequeued so the driver is not writing it.
            let data = unsafe { std::slice::from_raw_parts(*ptr as *const u8, used) };
            f(Frame { width: self.pix.width, height: self.pix.height, stride: self.pix.bytesperline, format: self.pix.pixelformat, data });
        }
        ioctl(&self.fd, QBUF, &mut b)?;
        Ok(true)
    }
}

impl Drop for Stream {
    fn drop(&mut self) {
        let mut kind = BUF_TYPE_VIDEO_CAPTURE as i32;
        let _ = ioctl(&self.fd, STREAMOFF, &mut kind);
        for (ptr, len) in self.maps.drain(..) {
            // SAFETY: mapped in `open` and unmapped once.
            unsafe { libc::munmap(ptr, len) };
        }
    }
}
