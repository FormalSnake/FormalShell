import Quickshell.Io

import qs.Services

// `qs ipc call lights toggle|status|refresh`, plus
// `effect <id>`, `color <hex>`, `source wallpaper|custom`,
// `speed low|med|high` and `brightness 0-3` for keybinds and the smoke rig.
// A value LightsService refuses, or a machine with no asusd, answers an
// error string rather than "ok".
IpcHandler {
    target: "lights"

    function _answer(ok, what) {
        if (!LightsService.available)
            return "error: no keyboard lights (asusctl/asusd not found)";
        return ok ? "ok" : "error: refused '" + what + "'";
    }

    function toggle(): string {
        LightsService.toggle();
        return _answer(true, "");
    }

    function effect(id: string): string {
        return _answer(LightsService.setEffect(id), id);
    }

    function color(hex: string): string {
        return _answer(LightsService.setColour(hex), hex);
    }

    function source(value: string): string {
        return _answer(LightsService.setSource(value), value);
    }

    function speed(value: string): string {
        return _answer(LightsService.setSpeed(value), value);
    }

    function brightness(level: string): string {
        return _answer(/^[0-3]$/.test(level) && LightsService.setBrightness(parseInt(level, 10)), level);
    }

    function refresh(): string {
        LightsService.refresh();
        return "ok";
    }

    function status(): string {
        return JSON.stringify({
            available: LightsService.available,
            on: LightsService.on,
            brightness: LightsService.brightness,
            effect: LightsService.effect,
            color: LightsService.colour,
            speed: LightsService.speed,
            source: LightsService.source,
            customColor: LightsService.customColour,
            paletteColor: LightsService.paletteColour,
            effects: LightsService.effects.map(e => e.id),
            lastError: LightsService.lastError
        });
    }
}
