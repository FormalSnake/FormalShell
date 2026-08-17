import QtQuick
import QtTest
import "../shell/Capture/model.js" as Capture

TestCase {
    name: "CaptureModel"

    function test_timestamp_zero_pads_every_field() {
        compare(Capture.timestamp(new Date(2026, 7, 11, 6, 5, 4)), "20260811-060504");
        compare(Capture.timestamp(new Date(2026, 11, 31, 23, 59, 59)), "20261231-235959");
    }

    function test_output_path_composes_one_slash_and_the_extension() {
        var d = new Date(2026, 7, 11, 6, 5, 4);
        compare(Capture.outputPath("/home/k/Videos", "screenrecording", "mp4", d),
            "/home/k/Videos/screenrecording-20260811-060504.mp4");
        compare(Capture.outputPath("/home/k/Videos/", "screenrecording", "mp4", d),
            "/home/k/Videos/screenrecording-20260811-060504.mp4");
    }

    function test_gif_output_path_sits_next_to_its_source() {
        compare(Capture.gifOutputPath("/a/b/clip.mp4"), "/a/b/clip.gif");
        compare(Capture.gifOutputPath("/a/b/clip"), "/a/b/clip.gif");
        compare(Capture.gifOutputPath("/a/b.d/clip.mp4"), "/a/b.d/clip.gif");
        compare(Capture.gifOutputPath("/a/b.d/clip"), "/a/b.d/clip.gif");
        compare(Capture.gifOutputPath(""), "");
    }

    function test_parse_geometry_accepts_slurps_own_format() {
        compare(Capture.parseGeometry("10,-5 800x600"), "10,-5 800x600");
        compare(Capture.parseGeometry("  0,0 1920x1080\n"), "0,0 1920x1080");
        compare(Capture.parseGeometry("640,360 1x1"), "640,360 1x1");
    }

    function test_parse_geometry_rejects_degenerate_and_malformed_boxes() {
        compare(Capture.parseGeometry("0,0 0x10"), "");
        compare(Capture.parseGeometry("0,0 10x0"), "");
        compare(Capture.parseGeometry(""), "");
        compare(Capture.parseGeometry("not a geometry"), "");
        compare(Capture.parseGeometry("0,0 800x600 extra"), "");
    }

    function test_hex_from_ppm_bytes_formats_uppercase_rrggbb() {
        compare(Capture.hexFromPpmBytes("  67 133 190\n"), "#4385BE");
        compare(Capture.hexFromPpmBytes("0 0 0"), "#000000");
        compare(Capture.hexFromPpmBytes("255 255 255"), "#FFFFFF");
        compare(Capture.hexFromPpmBytes("1 2 3"), "#010203");
    }

    function test_hex_from_ppm_bytes_rejects_anything_that_is_not_three_bytes() {
        compare(Capture.hexFromPpmBytes(""), "");
        compare(Capture.hexFromPpmBytes("67 133"), "");
        compare(Capture.hexFromPpmBytes("67 133 190 255"), "");
        compare(Capture.hexFromPpmBytes("67 133 999"), "");
        compare(Capture.hexFromPpmBytes("grim: failed to capture"), "");
    }

    function test_parse_audio_setup_reads_modules_then_device() {
        var mic = Capture.parseAudioSetup("41 42 43\nformalshell-mix.monitor\n");
        compare(mic.modules.length, 3);
        compare(mic.modules[0], 41);
        compare(mic.modules[2], 43);
        compare(mic.device, "formalshell-mix.monitor");

        var desktop = Capture.parseAudioSetup("\nalsa_output.pci-0000_00_1f.3.analog-stereo.monitor\n");
        compare(desktop.modules.length, 0);
        compare(desktop.device, "alsa_output.pci-0000_00_1f.3.analog-stereo.monitor");
    }

    function test_parse_audio_setup_reports_no_device_on_a_failed_setup() {
        compare(Capture.parseAudioSetup("").device, "");
        compare(Capture.parseAudioSetup("\n").device, "");
        compare(Capture.parseAudioSetup("41 42 43\n").device, "");
        var broken = Capture.parseAudioSetup("41 oops\nformalshell-mix.monitor\n");
        compare(broken.modules.length, 0);
        compare(broken.device, "");
    }

    function test_recorder_argv_always_forces_overwrite() {
        var argv = Capture.recorderArgv({ path: "/v/a.mp4", framerate: 30, output: "DP-1" });
        verify(argv.indexOf("-y") >= 0);
        compare(argv[0], "wf-recorder");
        compare(argv[argv.indexOf("-f") + 1], "/v/a.mp4");
        compare(argv[argv.indexOf("-r") + 1], "30");
        compare(argv[argv.indexOf("-o") + 1], "DP-1");
    }

    function test_recorder_argv_attaches_the_audio_device_to_one_element() {
        var argv = Capture.recorderArgv({
            path: "/v/a.mp4", framerate: 30, output: "DP-1",
            audioDevice: "formalshell-mix.monitor", audioBackend: "pulse"
        });
        verify(argv.indexOf("-a") < 0);
        verify(argv.indexOf("formalshell-mix.monitor") < 0);
        verify(argv.indexOf("--audio=formalshell-mix.monitor") >= 0);
        compare(argv[argv.indexOf("--audio-backend") + 1], "pulse");
    }

    function test_recorder_argv_emits_no_audio_flag_without_a_device() {
        var argv = Capture.recorderArgv({ path: "/v/a.mp4", framerate: 30, output: "DP-1" });
        for (var i = 0; i < argv.length; i++)
            verify(argv[i].indexOf("--audio") !== 0);
        verify(argv.indexOf("--audio-backend") < 0);
    }

    function test_recorder_argv_emits_optional_flags_only_when_asked() {
        var bare = Capture.recorderArgv({ path: "/v/a.mp4", framerate: 0, output: "" });
        verify(bare.indexOf("-g") < 0);
        verify(bare.indexOf("-o") < 0);
        verify(bare.indexOf("-r") < 0);
        verify(bare.indexOf("-c") < 0);
        verify(bare.indexOf("--no-dmabuf") < 0);

        var full = Capture.recorderArgv({
            path: "/v/a.mp4", framerate: 15, output: "winit-0",
            geometry: "0,0 800x600", codec: "libx264", noDmabuf: true
        });
        compare(full[full.indexOf("-g") + 1], "0,0 800x600");
        compare(full[full.indexOf("-c") + 1], "libx264");
        verify(full.indexOf("--no-dmabuf") >= 0);
    }

    function test_gif_argv_pass_one_writes_a_single_frame_palette() {
        var a = Capture.gifArgv("/v/a.mp4", "/run/pal.png", "/v/a.gif", { fps: 12, width: 640 });
        compare(a.pass1[a.pass1.indexOf("-f") + 1], "image2");
        compare(a.pass1[a.pass1.indexOf("-update") + 1], "1");
        compare(a.pass1[a.pass1.length - 1], "/run/pal.png");
        var vf = a.pass1[a.pass1.indexOf("-vf") + 1];
        verify(vf.indexOf("fps=12") >= 0);
        verify(vf.indexOf("scale=640:-1") >= 0);
        verify(vf.indexOf("palettegen=stats_mode=diff") >= 0);
    }

    function test_gif_argv_pass_two_reads_the_palette_as_its_second_input() {
        var a = Capture.gifArgv("/v/a.mp4", "/run/pal.png", "/v/a.gif", { fps: 8, width: 320 });
        var inputs = [];
        for (var i = 0; i < a.pass2.length; i++)
            if (a.pass2[i] === "-i")
                inputs.push(a.pass2[i + 1]);
        compare(inputs.length, 2);
        compare(inputs[0], "/v/a.mp4");
        compare(inputs[1], "/run/pal.png");
        compare(a.pass2[a.pass2.length - 1], "/v/a.gif");
        var lavfi = a.pass2[a.pass2.indexOf("-lavfi") + 1];
        verify(lavfi.indexOf("[x][1:v] paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle") >= 0);
        verify(lavfi.indexOf("fps=8") >= 0);
    }

    function test_elapsed_label_grows_an_hour_field_only_when_needed() {
        compare(Capture.elapsedLabel(0), "00:00");
        compare(Capture.elapsedLabel(42000), "00:42");
        compare(Capture.elapsedLabel(599000), "09:59");
        compare(Capture.elapsedLabel(3600000), "1:00:00");
        compare(Capture.elapsedLabel(3661000), "1:01:01");
        compare(Capture.elapsedLabel(-500), "00:00");
    }

    function test_ocr_outcome_separates_empty_from_failed() {
        compare(Capture.ocrOutcome(0), "ok");
        compare(Capture.ocrOutcome(3), "empty");
        compare(Capture.ocrOutcome(2), "failed");
        compare(Capture.ocrOutcome(1), "failed");
        compare(Capture.ocrOutcome(127), "failed");
    }

    function test_finalize_needs_reencode_reads_the_discard_flag() {
        compare(Capture.finalizeNeedsReencode("K_\nD_\n__\n"), true);
        compare(Capture.finalizeNeedsReencode("K_\n__\n__\n"), false);
        compare(Capture.finalizeNeedsReencode(""), false);
    }

    function test_finalize_has_audio_reads_the_stream_list() {
        compare(Capture.finalizeHasAudio("audio\n"), true);
        compare(Capture.finalizeHasAudio(""), false);
        compare(Capture.finalizeHasAudio("\n"), false);
    }

    function test_finalize_output_path_sits_next_to_its_source() {
        compare(Capture.finalizeOutputPath("/v/a.mp4"), "/v/a-processed.mp4");
        compare(Capture.finalizeOutputPath("/v/b.d/a.mp4"), "/v/b.d/a-processed.mp4");
        compare(Capture.finalizeOutputPath(""), "");
    }

    function test_finalize_argv_always_trims_the_first_tenth_of_a_second() {
        var argv = Capture.finalizeArgv("/v/a.mp4", "/v/a-processed.mp4", { reencode: false, hasAudio: false });
        compare(argv[argv.indexOf("-ss") + 1], "0.1");
        verify(argv.indexOf("-af") < 0);
        compare(argv[argv.indexOf("-c:v") + 1], "copy");
        compare(argv[argv.length - 1], "/v/a-processed.mp4");
    }

    function test_finalize_argv_reencodes_only_when_the_gop_needs_it() {
        var argv = Capture.finalizeArgv("/v/a.mp4", "/v/out.mp4", { reencode: true, hasAudio: false });
        compare(argv[argv.indexOf("-c:v") + 1], "libx264");
        verify(argv.indexOf("-preset") >= 0);
        verify(argv.indexOf("-crf") >= 0);
    }

    function test_finalize_argv_skips_the_audio_filter_without_a_track() {
        var argv = Capture.finalizeArgv("/v/a.mp4", "/v/out.mp4", { reencode: false, hasAudio: false });
        verify(argv.indexOf("-af") < 0);
    }

    function test_finalize_argv_mutes_fades_and_normalizes_when_there_is_audio() {
        var argv = Capture.finalizeArgv("/v/a.mp4", "/v/out.mp4", { reencode: false, hasAudio: true });
        var af = argv[argv.indexOf("-af") + 1];
        verify(af.indexOf("volume=enable='lt(t,0.4)':volume=0") >= 0);
        verify(af.indexOf("afade=t=in:st=0.4:d=0.05") >= 0);
        verify(af.indexOf("loudnorm=I=-14:TP=-1.5:LRA=11") >= 0);
    }

    function test_preview_frame_path_sits_next_to_its_source() {
        compare(Capture.previewFramePath("/v/a.mp4"), "/v/a-preview.png");
        compare(Capture.previewFramePath("/v/b.d/a.mp4"), "/v/b.d/a-preview.png");
        compare(Capture.previewFramePath(""), "");
    }

    function test_preview_frame_argv_pulls_one_frame_near_the_start() {
        var argv = Capture.previewFrameArgv("/v/a.mp4", "/v/a-preview.png");
        compare(argv[0], "ffmpeg");
        compare(argv[argv.indexOf("-ss") + 1], "0.1");
        compare(argv[argv.indexOf("-i") + 1], "/v/a.mp4");
        compare(argv[argv.indexOf("-vframes") + 1], "1");
        compare(argv[argv.indexOf("-q:v") + 1], "2");
        compare(argv[argv.length - 1], "/v/a-preview.png");
    }
}
