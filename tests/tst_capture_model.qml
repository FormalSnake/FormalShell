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

    function test_scale_cap_filter_is_empty_without_a_cap() {
        compare(Capture.scaleCapFilter(0), "");
        compare(Capture.scaleCapFilter(-5), "");
        compare(Capture.scaleCapFilter(undefined), "");
        compare(Capture.scaleCapFilter(""), "");
        compare(Capture.scaleCapFilter("not a number"), "");
    }

    function test_scale_cap_filter_clamps_height_and_keeps_width_even() {
        compare(Capture.scaleCapFilter(720), "scale=-2:'min(ih,720)'");
        compare(Capture.scaleCapFilter("1080"), "scale=-2:'min(ih,1080)'");
        compare(Capture.scaleCapFilter(480.9), "scale=-2:'min(ih,480)'");
    }

    function test_recorder_argv_adds_the_scale_filter_only_when_capped() {
        var uncapped = Capture.recorderArgv({ path: "/v/a.mp4", framerate: 30, output: "DP-1" });
        verify(uncapped.indexOf("-F") < 0);

        var capped = Capture.recorderArgv({ path: "/v/a.mp4", framerate: 30, output: "DP-1", maxHeight: 720 });
        compare(capped[capped.indexOf("-F") + 1], "scale=-2:'min(ih,720)'");
    }

    function test_resolve_max_height_defers_to_the_config_default_on_empty() {
        compare(Capture.resolveMaxHeight("", 720), 720);
        compare(Capture.resolveMaxHeight(undefined, 720), 720);
        compare(Capture.resolveMaxHeight(null, 0), 0);
        compare(Capture.resolveMaxHeight("  ", 720), 720);
    }

    function test_resolve_max_height_accepts_a_plain_non_negative_integer() {
        compare(Capture.resolveMaxHeight("480", 720), 480);
        compare(Capture.resolveMaxHeight("0", 720), 0);
    }

    function test_resolve_max_height_rejects_anything_that_is_not_a_number() {
        verify(isNaN(Capture.resolveMaxHeight("tall", 0)));
        verify(isNaN(Capture.resolveMaxHeight("-5", 0)));
        verify(isNaN(Capture.resolveMaxHeight("720p", 0)));
        verify(isNaN(Capture.resolveMaxHeight("7.5", 0)));
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

    function test_webcam_argv_targets_the_device_and_carries_the_app_id() {
        var argv = Capture.webcamArgv("/dev/video0", "formalshell-webcam");
        compare(argv[0], "mpv");
        compare(argv[1], "av://v4l2:/dev/video0");
        verify(argv.indexOf("--title=formalshell-webcam") >= 0);
        verify(argv.indexOf("--wayland-app-id=formalshell-webcam") >= 0);
        verify(argv.indexOf("--vf=lavfi=[crop=ih*8/9:ih]") >= 0);
    }

    function test_parse_webcam_devices_reads_one_path_per_line() {
        compare(Capture.parseWebcamDevices("/dev/video0\n/dev/video1\n"),
            ["/dev/video0", "/dev/video1"]);
        compare(Capture.parseWebcamDevices(""), []);
        compare(Capture.parseWebcamDevices("\n\n"), []);
    }

    function test_webcam_geometry_scales_the_medium_preset_from_region_height() {
        var g = Capture.webcamGeometry("medium", { x: 100, y: 200, width: 1920, height: 1080 }, 18);
        compare(g, { width: 240, height: 270, x: 1762, y: 992 });
    }

    function test_webcam_geometry_falls_back_to_medium_for_an_unknown_size() {
        var known = Capture.webcamGeometry("medium", { x: 0, y: 0, width: 1920, height: 1080 }, 18);
        var unknown = Capture.webcamGeometry("bogus", { x: 0, y: 0, width: 1920, height: 1080 }, 18);
        compare(unknown, known);
    }

    function test_webcam_geometry_caps_the_scale_height_for_a_narrow_region() {
        var g = Capture.webcamGeometry("large", { x: 0, y: 0, width: 300, height: 1000 }, 18);
        compare(g, { width: 264, height: 297, x: 18, y: 685 });
    }

    function test_webcam_geometry_clamps_to_the_region_when_margins_overwhelm_it() {
        var g = Capture.webcamGeometry("medium", { x: 0, y: 0, width: 10, height: 10 }, 18);
        compare(g, { width: 3, height: 3, x: 18, y: 18 });
    }

    function test_webcam_map_poll_waits_while_unfound_and_under_the_giveup_bound() {
        compare(Capture.webcamMapPollAction(false, 1, false, 100, 200), "wait");
        compare(Capture.webcamMapPollAction(false, 99, false, 100, 200), "wait");
    }

    function test_webcam_map_poll_places_the_window_the_first_time_it_is_found() {
        compare(Capture.webcamMapPollAction(true, 3, false, 100, 200), "place");
    }

    function test_webcam_map_poll_gives_up_honestly_at_the_bound_but_keeps_polling() {
        compare(Capture.webcamMapPollAction(false, 100, false, 100, 200), "give-up");
    }

    function test_webcam_map_poll_reaps_a_straggler_window_found_after_giveup() {
        compare(Capture.webcamMapPollAction(true, 150, true, 100, 200), "reap");
    }

    function test_webcam_map_poll_stops_once_the_reap_bound_is_hit_with_nothing_found() {
        compare(Capture.webcamMapPollAction(false, 199, true, 100, 200), "wait");
        compare(Capture.webcamMapPollAction(false, 200, true, 100, 200), "stop");
    }

    function test_region_from_geometry_parses_the_slurp_shape() {
        compare(Capture.regionFromGeometry("100,200 800x600"), { x: 100, y: 200, width: 800, height: 600 });
        compare(Capture.regionFromGeometry("-10,-20 100x50"), { x: -10, y: -20, width: 100, height: 50 });
        compare(Capture.regionFromGeometry(""), null);
        compare(Capture.regionFromGeometry("bogus"), null);
    }
}
