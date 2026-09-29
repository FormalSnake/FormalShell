import Quickshell.Io

import qs.Compositor
import "../Display/outputs.js" as Outputs

// `qs ipc call display scale|mirror|enable`, the Display panel's three output
// controls without the panel. Each names its output and answers "ok" or why
// nothing was sent; the change lands in the compositor before the answer, so
// `hyprctl monitors -j` reads it back straight away.
IpcHandler {
    target: "display"

    function _known(output: string): bool {
        return Outputs.findOutput(CompositorService.backend.outputs, output) !== null;
    }

    function scale(output: string, scale: real): string {
        if (!CompositorService.backend.outputConfigAvailable)
            return "no compositor";
        if (!_known(output))
            return "unknown output: " + output;
        CompositorService.backend.setOutputScale(output, scale);
        return "ok";
    }

    // An empty `source` clears the mirror.
    function mirror(output: string, source: string): string {
        if (!CompositorService.backend.mirrorSupported)
            return "mirroring unsupported";
        if (!_known(output))
            return "unknown output: " + output;
        CompositorService.backend.setOutputMirror(output, source);
        return "ok";
    }

    function enable(output: string, enabled: bool): string {
        if (!CompositorService.backend.outputConfigAvailable)
            return "no compositor";
        if (!_known(output))
            return "unknown output: " + output;
        CompositorService.backend.setOutputEnabled(output, enabled);
        return "ok";
    }
}
