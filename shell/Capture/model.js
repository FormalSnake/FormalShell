.pragma library

// Pure logic behind the two capture-side IPC targets: `capture` (pull
// something off the screen into the clipboard) and `record` (video). Kept
// out of QML so qmltestrunner reaches it head-on, the shell/Bar/layout.js
// and shell/Notifications/model.js convention. No Quickshell access, no
// Date.now(), no I/O: every function takes its inputs and returns a value.
//
// The argv builders return plain arrays that go straight onto
// Process.command with no shell in between, so a recording directory
// carrying a space or a quote can never splice a command.

// Transient PipeWire/Pulse sink the desktop+mic mode mixes both sources
// into. Fixed name, created and torn down inside one recording's lifetime;
// never written to state.json.
var MIX_SINK = "formalshell-mix";

// "YYYYMMDD-HHMMSS", every field zero-padded.
function timestamp(date) {
    var p = function (n) { return (n < 10 ? "0" : "") + n; };
    return "" + date.getFullYear() + p(date.getMonth() + 1) + p(date.getDate())
        + "-" + p(date.getHours()) + p(date.getMinutes()) + p(date.getSeconds());
}

function outputPath(dir, prefix, ext, date) {
    var base = ("" + dir).replace(/\/+$/, "");
    return base + "/" + prefix + "-" + timestamp(date) + "." + ext;
}

// The GIF lands next to its source rather than in recording.directory: the
// daily case is an mp4 someone sent you sitting in ~/Downloads, and moving
// the result somewhere else is friction rather than less of it. A leading
// dot after the last slash is a dotfile, not an extension, so it survives.
function gifOutputPath(source) {
    if (!source)
        return "";
    var slash = source.lastIndexOf("/");
    var dot = source.lastIndexOf(".");
    var stem = dot > slash + 1 ? source.slice(0, dot) : source;
    return stem + ".gif";
}

var GEOMETRY_RE = /^(-?\d+),(-?\d+)\s+(\d+)x(\d+)$/;

// slurp's own default output format ("%x,%y %wx%h"), the same string grim
// and wf-recorder both take for -g. Negative origins are legal on a
// multi-output layout; a zero-width or zero-height box is never a geometry.
function parseGeometry(text) {
    var m = GEOMETRY_RE.exec(("" + text).trim());
    if (!m)
        return "";
    if (Number(m[3]) <= 0 || Number(m[4]) <= 0)
        return "";
    return m[1] + "," + m[2] + " " + m[3] + "x" + m[4];
}

// `od -An -tu1` over the three trailing bytes of a 1x1 `grim -t ppm`.
// grim's P6 writer emits "P6\n<W> <H>\n255\n" followed by W*H*3 native RGB
// bytes and no trailing newline (grim write_ppm.c), so the last three bytes
// are the last pixel, in R,G,B order and already alpha-free. On a
// fractionally scaled output a 1x1 logical region renders as more than one
// device pixel, and the last one is still inside the region the user
// picked, so the trailing-bytes read stays correct there too.
function hexFromPpmBytes(text) {
    var raw = ("" + text).trim();
    if (raw === "")
        return "";
    var parts = raw.split(/\s+/);
    if (parts.length !== 3)
        return "";
    var out = "#";
    for (var i = 0; i < 3; i++) {
        if (!/^\d+$/.test(parts[i]))
            return "";
        var v = Number(parts[i]);
        if (v > 255)
            return "";
        out += (v < 16 ? "0" : "") + v.toString(16).toUpperCase();
    }
    return out;
}

// The audio-setup script's two-line answer: the pactl module ids it loaded
// (blank when it loaded none) on the first line, the device wf-recorder
// should record on the second. Anything else is a failed setup, reported as
// an empty device so the caller never starts a recording that silently
// captures nothing.
function parseAudioSetup(text) {
    var lines = ("" + text).split("\n");
    var ids = [];
    var raw = (lines[0] || "").trim();
    if (raw !== "") {
        var parts = raw.split(/\s+/);
        for (var i = 0; i < parts.length; i++) {
            if (!/^\d+$/.test(parts[i]))
                return { modules: [], device: "" };
            ids.push(Number(parts[i]));
        }
    }
    var device = (lines[1] || "").trim();
    if (device === "")
        return { modules: ids, device: "" };
    return { modules: ids, device: device };
}

// wf-recorder v0.6 argv, read off manpage/wf-recorder.1 and src/main.cpp's
// getopt table rather than recalled.
//
// `-y` is mandatory on every single invocation, not a convenience: without
// it main.cpp's user_specified_overwrite() does a blocking
// std::getline(std::cin) the moment the target file already exists, and
// quickshell hands a child a stdin pipe that never reaches EOF, the same
// trap ScreenshotIpc.qml documents for slurp.
//
// `--audio` is declared optional_argument, so the device has to ride the
// same argv element. A separate element would be left as a stray positional
// and the device silently dropped, recording the default source instead.
// `--audio-backend` is required_argument and long-form only, so it takes
// the ordinary two-element form.
function recorderArgv(opts) {
    var argv = ["wf-recorder", "-y", "-f", opts.path];
    if (opts.framerate > 0)
        argv.push("-r", String(opts.framerate));
    if (opts.output)
        argv.push("-o", opts.output);
    if (opts.geometry)
        argv.push("-g", opts.geometry);
    if (opts.codec)
        argv.push("-c", opts.codec);
    var scaleFilter = scaleCapFilter(opts.maxHeight);
    if (scaleFilter)
        argv.push("-F", scaleFilter);
    if (opts.noDmabuf === true)
        argv.push("--no-dmabuf");
    if (opts.audioDevice) {
        argv.push("--audio=" + opts.audioDevice);
        if (opts.audioBackend)
            argv.push("--audio-backend", opts.audioBackend);
    }
    return argv;
}

// wf-recorder's -F/--filter (M27 Task 4) passes straight into ffmpeg's own
// filtergraph parser (avfilter_graph_parse_ptr, upstream frame-writer.cpp
// init_video_filters), so an ordinary scale expression works with no shell
// in between to escape it. -2 asks ffmpeg to compute the width from the
// chosen height, rounded to an even number (most encoders require one);
// min(ih,H) leaves the height untouched under the cap and clamps it to H
// otherwise, so nothing here has to know the captured height in advance --
// screen scope has none until wf-recorder opens the real output. Single-
// quoted per ffmpeg's own filtergraph escaping, since the comma inside
// min(...) would otherwise read as the end of the -F value.
function scaleCapFilter(maxHeight) {
    var h = Number(maxHeight);
    if (!(h > 0))
        return "";
    return "scale=-2:'min(ih," + Math.floor(h) + ")'";
}

// The record IPC's own maxHeight override: "" defers to recording.maxHeight
// (the same "pass \"\" for a default" contract every other optional record
// argument already holds, USAGE.md), and 0 is itself the legal "uncapped,
// regardless of what config says" answer. Anything else must be a plain
// non-negative integer; NaN signals "not a number", which the caller turns
// into an IPC error string rather than silently falling back to the config
// default and hiding a typo.
function resolveMaxHeight(arg, configDefault) {
    var raw = (arg === undefined || arg === null) ? "" : ("" + arg).trim();
    if (raw === "")
        return configDefault;
    if (!/^\d+$/.test(raw))
        return NaN;
    return Number(raw);
}

// Two-pass palettegen/paletteuse. `-f image2 -update 1` is what makes pass
// one write a single-frame palette PNG instead of a numbered sequence.
// dither=bayer is not a taste call: DESIGN.md §2 item 8 names ordered Bayer
// dither as the shell's one sanctioned texture, and §2 item 12's chunky
// ruling is why bayer_scale sits at 3 rather than 0.
function gifArgv(inPath, palettePath, outPath, opts) {
    var chain = "fps=" + opts.fps + ",scale=" + opts.width + ":-1:flags=lanczos";
    return {
        pass1: ["ffmpeg", "-y", "-loglevel", "error", "-i", inPath,
            "-vf", chain + ",palettegen=stats_mode=diff",
            "-f", "image2", "-update", "1", palettePath],
        pass2: ["ffmpeg", "-y", "-loglevel", "error", "-i", inPath, "-i", palettePath,
            "-lavfi", chain + " [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle",
            "-loop", "0", outPath]
    };
}

// "MM:SS" under an hour, "H:MM:SS" past it.
function elapsedLabel(ms) {
    var total = Math.max(0, Math.floor(ms / 1000));
    var p = function (n) { return (n < 10 ? "0" : "") + n; };
    var s = total % 60;
    var m = Math.floor(total / 60) % 60;
    var h = Math.floor(total / 3600);
    return h > 0 ? h + ":" + p(m) + ":" + p(s) : p(m) + ":" + p(s);
}

// The OCR pipeline's own exit codes, not tesseract's. 3 means the region
// held no text (a real outcome, with no clipboard write and no error to
// report), while 2 means one of the four commands in the chain actually
// failed.
function ocrOutcome(exitCode) {
    if (exitCode === 0)
        return "ok";
    if (exitCode === 3)
        return "empty";
    return "failed";
}

// finalize_recording's own trim (bin/omarchy-capture-screenrecording:253-280,
// upstream, MIT), ported verbatim in intent: PipeWire emits a click at the
// start of every captured stream, so the first 0.1s is always cut. Kept as
// pure functions rather than one shell script (unlike _setupAudio's) so the
// reencode/audio decisions are directly testable.

// ffprobe -select_streams v:0 -read_intervals %+0.2 -show_entries
// packet=flags -of csv=p=0: one flag string per packet in the first 0.2s.
// A "D" (discard) flag is what a stream copy can't trim past -- it rewinds
// to the keyframe instead -- so its presence is what forces a re-encode.
function finalizeNeedsReencode(packetFlagsText) {
    return /D/.test("" + packetFlagsText);
}

// ffprobe -select_streams a -show_entries stream=codec_type -of csv=p=0:
// one "audio" line per audio stream, nothing at all when there is none.
function finalizeHasAudio(streamTypesText) {
    return ("" + streamTypesText).indexOf("audio") >= 0;
}

// Sits next to its source, the same dotfile-safe stem logic as
// gifOutputPath, so the two temp-output conventions read the same way.
function finalizeOutputPath(source) {
    if (!source)
        return "";
    var slash = source.lastIndexOf("/");
    var dot = source.lastIndexOf(".");
    var stem = dot > slash + 1 ? source.slice(0, dot) : source;
    return stem + "-processed.mp4";
}

// `-ss` before `-i` trims frame-accurately on the reencode path and at the
// nearest keyframe on the copy path -- both are upstream's own command,
// ported as-is. The audio filter chain hard-mutes the first 400ms (the
// PipeWire capture-open pop a fade alone can't attenuate enough), fades the
// next 50ms, then normalizes the rest to -14 LUFS.
function finalizeArgv(inPath, outPath, opts) {
    var argv = ["ffmpeg", "-y", "-ss", "0.1", "-i", inPath];
    if (opts && opts.reencode)
        argv.push("-c:v", "libx264", "-preset", "veryfast", "-crf", "20");
    else
        argv.push("-c:v", "copy");
    if (opts && opts.hasAudio)
        argv.push("-af", "volume=enable='lt(t,0.4)':volume=0,afade=t=in:st=0.4:d=0.05,loudnorm=I=-14:TP=-1.5:LRA=11");
    argv.push(outPath);
    return argv;
}

// The SAVED toast's own thumbnail (bin/omarchy-capture-screenrecording:224,
// upstream, MIT). Same dotfile-safe stem logic as gifOutputPath/
// finalizeOutputPath, so all three temp-output conventions read the same way.
function previewFramePath(source) {
    if (!source)
        return "";
    var slash = source.lastIndexOf("/");
    var dot = source.lastIndexOf(".");
    var stem = dot > slash + 1 ? source.slice(0, dot) : source;
    return stem + "-preview.png";
}

// One frame at 0.1s in -- the same offset finalizeArgv trims to, so the
// thumbnail matches what the finalized file actually opens on -- at
// upstream's own -q:v 2 (bin/omarchy-capture-screenrecording:227, MIT).
function previewFrameArgv(source, outPath) {
    return ["ffmpeg", "-y", "-loglevel", "error", "-ss", "0.1", "-i", source,
        "-vframes", "1", "-q:v", "2", outPath];
}

// Webcam overlay (M27 Task 5): mpv's own low-latency profile and 8:9
// portrait crop (bin/omarchy-capture-screenrecording:86-92, upstream, MIT),
// given its own title/app-id so the compositor placement below (and the map
// poll that precedes it) can find exactly this window and nothing else mpv
// might already have open. No forced --demuxer-lavf-o video_size: the crop
// filter derives its width from whatever height the device actually opens
// at, so there is nothing here that needs a v4l2-ctl format probe first.
function webcamArgv(device, appId) {
    return ["mpv", "av://v4l2:" + device,
        "--profile=low-latency", "--untimed", "--no-cache",
        "--vf=lavfi=[crop=ih*8/9:ih]",
        "--title=" + appId, "--wayland-app-id=" + appId,
        "--no-border", "--no-audio", "--no-osc", "--osd-level=0", "--really-quiet"];
}

// `for f in /dev/video*; do [ -e "$f" ] && echo "$f"; done` output: one path
// per line, sorted by the shell's own glob order, empty when the glob
// matched nothing and stayed a literal unexpanded string the `-e` test
// rejects. The auto-detect pick is the first line -- no v4l2-ctl capability
// filter, which is what upstream's own list script adds and this shell
// doesn't pull in a second CLI dependency to replicate.
function parseWebcamDevices(text) {
    return ("" + text).split("\n")
        .map(function (s) { return s.trim(); })
        .filter(function (s) { return s !== ""; });
}

// webcamMapTimer's phase machine (defect fix, M27): 50ms x 100 = 5s to wait
// for mpv's window to map before giving up honestly -- upstream's own 2s
// budget (bin/omarchy-capture-screenrecording:96-99) was too tight for real
// v4l2 init on some USB cameras, and mpv is already spawned by the time the
// old code gave up, so a late map became an untracked window tiled across
// the recording forever. giveUpAttempts is when the WEBCAM UNAVAILABLE
// notification fires and the recording launches without the camera;
// reapAttempts is how much further the same poll keeps watching afterward so
// a straggler window that maps just past the timeout gets closed the instant
// it appears instead of leaking.
var WEBCAM_MAP_GIVEUP_ATTEMPTS = 100;
var WEBCAM_MAP_REAP_ATTEMPTS = 200;

function webcamMapPollAction(found, attempts, gaveUp, giveUpAttempts, reapAttempts) {
    if (found)
        return gaveUp ? "reap" : "place";
    if (!gaveUp && attempts >= giveUpAttempts)
        return "give-up";
    if (gaveUp && attempts >= reapAttempts)
        return "stop";
    return "wait";
}

// The 8:9 portrait presets, scaled from the captured region's own height so
// the camera occupies the same share of the frame at 1080p as at a scaled
// 6K capture (omarchy-capture-webcam-resize:78-95, upstream, MIT -- ported
// as intent, not its integer-bash arithmetic). `large`'s width is what a
// tall, narrow region can't fit at full scale, so the height every preset
// scales from is capped to what the region's own width (minus two margins)
// allows the widest preset to reach.
var WEBCAM_HEIGHT_FRACTION = { small: 9 / 50, medium: 1 / 4, large: 27 / 80 };

function webcamGeometry(sizeName, region, margin) {
    var frac = WEBCAM_HEIGHT_FRACTION[sizeName] || WEBCAM_HEIGHT_FRACTION.medium;
    var scaleHeight = region.height;
    var availableWidth = region.width - 2 * margin;
    var largeWidth = scaleHeight * WEBCAM_HEIGHT_FRACTION.large * 8 / 9;
    if (availableWidth > 0 && largeWidth > availableWidth)
        scaleHeight = availableWidth * 10 / 3;
    var height = Math.max(1, Math.round(scaleHeight * frac));
    var width = Math.max(1, Math.round(height * 8 / 9));
    var x = region.x + region.width - width - margin;
    var y = region.y + region.height - height - margin;
    if (x < region.x + margin)
        x = region.x + margin;
    if (y < region.y + margin)
        y = region.y + margin;
    return { width: width, height: height, x: Math.round(x), y: Math.round(y) };
}

// The "X,Y WxH" geometry a region/window recording already resolved, back
// into the {x,y,width,height} webcamGeometry needs -- parseGeometry's own
// shape, minus the round trip through a string.
function regionFromGeometry(geometryStr) {
    var m = GEOMETRY_RE.exec(("" + geometryStr).trim());
    if (!m)
        return null;
    return { x: Number(m[1]), y: Number(m[2]), width: Number(m[3]), height: Number(m[4]) };
}
