import Quickshell.Io
import qs.Services
import "../Visualizer/styles.js" as Styles

// `qs ipc call visualizer style|styles|status` (M73): the media panel
// spectrum's style picked at runtime, for exploring the styles without an
// edit to settings.json. The override is in memory only, `style config`
// drops it.
IpcHandler {
    target: "visualizer"

    function style(name: string): string {
        var err = VisualizerService.setStyle(name);
        return err !== "" ? err : VisualizerService.style;
    }

    function styles(): string {
        return Styles.ids().join("\n");
    }

    function status(): string {
        return JSON.stringify({
            style: VisualizerService.style,
            override: VisualizerService.styleOverride,
            configured: VisualizerService.configuredStyle,
            configuredKnown: VisualizerService.configuredStyleKnown,
            running: VisualizerService.running,
            state: VisualizerService.state
        });
    }
}
