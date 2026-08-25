import Quickshell.Io

import qs.Services

// `qs ipc call osd volume|brightness|media|close|state`, external triggers
// for the bottom-center OSD. Osd.qml auto-shows itself on
// AudioService.changed; this target covers everything else:
// BrightnessService has no polling loop to hook a signal off of (see its own
// header), so a brightness keybind is expected to run
// `brightnessctl set 5%+ && qs ipc call osd brightness`, the ctl call lands
// first, this handler's job is only to catch BrightnessService's cached
// percent up to what the hardware already did before showing.
IpcHandler {
    target: "osd"

    // Set from shell.qml, the single Osd instance (same reasoning as
    // MenuIpc's `menu` property: one instance, no singleton of its own).
    property var osd: null

    function volume(): string {
        if (!osd)
            return "error: osd not ready";
        osd.showVolume();
        return "ok";
    }

    function brightness(): string {
        if (!osd)
            return "error: osd not ready";
        BrightnessService.refresh();
        osd.showBrightness();
        return "ok";
    }

    function media(text: string): string {
        if (!osd)
            return "error: osd not ready";
        osd.showMedia(text);
        return "ok";
    }

    function close(): string {
        if (!osd)
            return "error: osd not ready";
        osd.close();
        return "ok";
    }

    function state(): string {
        if (!osd)
            return "error: osd not ready";
        return JSON.stringify({
            visible: osd.visible,
            kind: osd.kind,
            mediaText: osd.mediaText
        });
    }
}
