{ lib, stdenvNoCC, makeWrapper, quickshell, brightnessctl, wl-clipboard, curl, grim, slurp, wtype, qt6, formalshell-eds
, matugen, qrencode, cava, ddcutil, tensaku, ttfx, lucide-font, nerd-fonts
, wf-recorder, tesseract, ffmpeg-headless, pulseaudio, git, mpv, util-linux }:
stdenvNoCC.mkDerivation {
  pname = "formalshell";
  version = "0.1.0-dev";
  src = ../shell;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/formalshell $out/bin
    cp -r . $out/share/formalshell/
    # Bundled default screensaver banner (M8b Task 7) — a sibling of shell/
    # in the repo, so Quickshell.shellPath("branding/...") still resolves it
    # once installed here alongside the copied shell tree.
    cp -r ${../branding} $out/share/formalshell/branding
    # The shipped Hyprland config (blur layer rules, the colours source line,
    # every default bind). Nothing in the shell reads it: a nix install has no
    # checkout to copy it out of, so the closure has to carry it.
    mkdir -p $out/share/formalshell/examples
    cp -r ${../docs/examples}/. $out/share/formalshell/examples/
    # wtype (the menu's emoji instant-paste, M13 Task 6) is suffixed, not
    # prefixed: an environment wtype must stay able to shadow the bundled
    # one — the smoke rig substitutes an argv-logging shim to prove the
    # spawn (real typing into a refocused window is host-trial territory),
    # and any real wtype is equivalent for the typing itself.
    # ttfx animates the screensaver banner (the shell parses its ANSI frame
    # stream); without it on PATH the screensaver falls back to effect.js's
    # five builtin effects rather than going blank.
    # lucide-font is prefixed onto XDG_DATA_DIRS rather than PATH: fontconfig's
    # default config scans "$dir/fonts" for every dir named there, which is
    # what makes Icon.qml's "lucide" font.family resolve without depending
    # on the host also declaring it in fonts.packages.
    # nerd-fonts.symbols-only rides the same mechanism for one reason only:
    # it embeds font-logos, which is where the launcher's distro mark comes
    # from (Theme/icons/distro.js). Symbols-only rather than a patched face,
    # since nothing here wants the glyphs merged into a text font.
    # matugen/qrencode/cava/ddcutil back shipped features (theming, the Wi-Fi
    # QR share, the visualizer widget, external-monitor brightness) and were
    # only ever on PATH because nix/testvm.nix lists them in
    # environment.systemPackages — a real install through the home-manager
    # module got none of them. Daemon-paired CLIs stay out on purpose:
    # nmcli and bluetoothctl must match the NetworkManager/bluez the system
    # is actually running, and their callers already guard with `command -v`.
    # wf-recorder/tesseract/ffmpeg-headless back the capture suite
    # (RecordingService's screen recording, the `capture text` OCR verb, and
    # the two-pass GIF transcode). wf-recorder rather than
    # gpu-screen-recorder: it captures through wlr-screencopy, which a nested
    # compositor implements, so recording is reachable by the smoke rig
    # instead of needing real KMS. pulseaudio is CLI-only here (pactl):
    # RecordingService's desktop/desktopmic audio setup resolves the
    # default sink/source and mixes the two through it, and pipewire's own
    # pulse compat layer (services.pipewire.pulse.enable) provides the
    # protocol without ever installing the client tool itself. git is
    # read-only here, probing the locked revision of a flake input for the
    # system-update widget. mpv backs the recording.webcam overlay
    # (RecordingService spawns it against a v4l2 device through the
    # compositor, never through this wrapper's own child process tree).
    # util-linux is here for setpriv alone (shell/Core/proc.js): quickshell
    # takes no SIGTERM handler, so a `systemctl --user restart` leaves every
    # long-lived child it owned running, and PR_SET_PDEATHSIG is what closes
    # that. Unlike the optional CLIs above this one has no fallback state,
    # which is why it is wired here rather than guarded with `command -v`.
    makeWrapper ${lib.getExe' quickshell "qs"} $out/bin/formalshell \
      --add-flags "-p $out/share/formalshell" \
      --prefix PATH : ${lib.makeBinPath [ brightnessctl wl-clipboard curl grim slurp formalshell-eds matugen qrencode cava ddcutil ttfx wf-recorder tesseract ffmpeg-headless pulseaudio git mpv util-linux ]} \
      --suffix PATH : ${lib.makeBinPath [ wtype tensaku ]} \
      --prefix XDG_DATA_DIRS : ${lucide-font}/share \
      --prefix XDG_DATA_DIRS : ${nerd-fonts.symbols-only}/share \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qt6.qtpositioning}/lib/qt-6/qml \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qt6.qtmultimedia}/lib/qt-6/qml \
      --prefix QT_PLUGIN_PATH : ${qt6.qtpositioning}/lib/qt-6/plugins \
      --prefix QT_PLUGIN_PATH : ${qt6.qtmultimedia}/lib/qt-6/plugins

    # lock-before-sleep contract (spec §8): whatever a systemd unit calls
    # before suspend must keep an exit-0-always behaviour so a lock failure
    # can never block suspend. `qs ipc call` itself exits nonzero (255) when
    # no shell instance is running at all — this wrapper is the actual
    # command such a unit invokes, and it never propagates that.
    cat > $out/bin/formalshell-lock-before-sleep <<SCRIPT
#!/usr/bin/env bash
${lib.getExe' quickshell "qs"} ipc --any-display -p $out/share/formalshell call lock lock >/dev/null 2>&1 || true
exit 0
SCRIPT
    chmod +x $out/bin/formalshell-lock-before-sleep
    runHook postInstall
  '';
  meta = { mainProgram = "formalshell"; license = lib.licenses.mit; platforms = lib.platforms.linux; };
}
