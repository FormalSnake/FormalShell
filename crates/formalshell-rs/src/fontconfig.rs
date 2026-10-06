//! The rendering settings fontconfig resolves for `sans-serif`, read the way
//! cairo reads them: substitute the pattern, match it, and take antialias,
//! hinting and hintstyle off the match, so a user's fonts.conf edits apply.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HintStyle {
    None,
    Slight,
    Medium,
    Full,
}

#[derive(Clone, Copy, Debug)]
pub struct Rendering {
    pub antialias: bool,
    pub hinting: bool,
    pub hint_style: HintStyle,
}

/// fontconfig's own defaults when a key is absent from the match.
const FALLBACK: Rendering = Rendering { antialias: true, hinting: true, hint_style: HintStyle::Full };

#[cfg(target_os = "linux")]
pub fn rendering() -> Rendering {
    use fontconfig_sys::constants::{FC_ANTIALIAS, FC_HINT_STYLE, FC_HINTING};
    use fontconfig_sys::*;
    use std::ffi::c_int;

    unsafe {
        if FcInit() == 0 {
            return FALLBACK;
        }
        let pattern = FcNameParse(c"sans-serif".as_ptr().cast());
        if pattern.is_null() {
            return FALLBACK;
        }
        FcConfigSubstitute(std::ptr::null_mut(), pattern, FcMatchPattern);
        FcDefaultSubstitute(pattern);
        let mut result = FcResultMatch;
        let matched = FcFontMatch(std::ptr::null_mut(), pattern, &mut result);
        FcPatternDestroy(pattern);
        if matched.is_null() {
            return FALLBACK;
        }
        let get_bool = |key: &std::ffi::CStr, fallback: bool| {
            let mut v: FcBool = 0;
            if FcPatternGetBool(matched, key.as_ptr(), 0, &mut v) == FcResultMatch { v != 0 } else { fallback }
        };
        let mut style: c_int = 3;
        if FcPatternGetInteger(matched, FC_HINT_STYLE.as_ptr(), 0, &mut style) != FcResultMatch {
            style = 3;
        }
        let out = Rendering {
            antialias: get_bool(FC_ANTIALIAS, FALLBACK.antialias),
            hinting: get_bool(FC_HINTING, FALLBACK.hinting),
            hint_style: match style {
                0 => HintStyle::None,
                1 => HintStyle::Slight,
                2 => HintStyle::Medium,
                _ => HintStyle::Full,
            },
        };
        FcPatternDestroy(matched);
        out
    }
}

#[cfg(not(target_os = "linux"))]
pub fn rendering() -> Rendering {
    FALLBACK
}
