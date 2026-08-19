import Quickshell
import Quickshell.Io
import qs.Compositor
import qs.Core as Core
import qs.Services
import "../Monitor/gpu.js" as Gpu

// `qs ipc call monitor status|gpu|launch <desktopId> <card>|mode <target>`
// (M38 Task 5). The headless evidence path for the system monitor and
// multi-GPU launch (plan decisions D3-D5).
//
// IpcHandler replies are synchronous QMetaMethod invocations
// (ScreenshotIpc.qml's own header), so status()/gpu() can never wait out a
// fresh tick: each reply is built from whatever the PREVIOUS collector run
// left. Both still pulse SystemMonitorService.subscribe()/unsubscribe()
// before reading (GpuService.refresh()'s own pattern). That cannot help
// the reply already in flight, but it leaves a fresh sample behind for the
// next caller, so a poller sees live data rather than one frozen frame.
// `_warmMonitor` below lands the first such sample at shell construction,
// before any IPC caller could possibly connect (DebugIpc's _warmBrightness
// idiom). Every reply also carries sampledAtMs/ageMs (SystemMonitorService's
// own lastTickAt) so a caller sees exactly how stale it is rather than
// trusting it blind.
//
// `card`/`target` below are still required strings, never an omittable
// trailing argument: quickshell dispatches IPC on exact arity (BarIpc.qml's
// own note, ipccomm.cpp: `argumentTypes.length() != arguments.length()` is
// rejected before the handler runs), so an empty string is the sentinel for
// "use the default" instead.
// Scope root, not a bare IpcHandler: IpcHandler has no default property,
// so the supergfxctl Process below cannot live inside it. CaptureIpc and
// ScreenshotIpc already carry the same structure for the same reason.
Scope {
    id: root

    readonly property bool _warmMonitor: GpuService.available !== undefined

    IpcHandler {
        target: "monitor"

        function status(): string {
            SystemMonitorService.subscribe();
            SystemMonitorService.unsubscribe();
            var sampledAt = SystemMonitorService.lastTickAt;
            return JSON.stringify({
                sampledAtMs: sampledAt || null,
                ageMs: sampledAt ? (Date.now() - sampledAt) : null,
                cpu: SystemMonitorService.cpu,
                mem: SystemMonitorService.mem,
                load: SystemMonitorService.load,
                uptime: SystemMonitorService.uptime,
                temps: SystemMonitorService.temps,
                net: SystemMonitorService.net,
                disk: SystemMonitorService.disk
            });
        }

        function gpu(): string {
            SystemMonitorService.subscribe();
            SystemMonitorService.unsubscribe();
            var sampledAt = SystemMonitorService.lastTickAt;
            return JSON.stringify({
                sampledAtMs: sampledAt || null,
                ageMs: sampledAt ? (Date.now() - sampledAt) : null,
                available: GpuService.available,
                cards: GpuService.cards,
                gfxMode: GpuService.gfxMode,
                tools: GpuService.tools
            });
        }

        // Single-quotes `value` for a sh -c string (HyprlandBackend.qml's
        // _quoteArg, Menu/providers.js's _shq): close the quote, an escaped
        // literal quote, reopen.
        function _shq(value) {
            return "'" + String(value).replace(/'/g, "'\\''") + "'";
        }

        // console.command's own argv (ConsoleService.qml's default), or []
        // when unset. A runInTerminal launch leads with this and trails with
        // the offload argv as the command to run: foot/kitty/alacritty/wezterm
        // all treat trailing args as the command, while ghostty needs its own
        // -e, which a configured console.command is free to include already.
        function _terminalArgv() {
            var cmd = Core.Config.get("console.command", "");
            if (Array.isArray(cmd))
                return cmd;
            return cmd ? [cmd] : [];
        }

        // `card`: a GpuService card id, or "" for GpuService.defaultDiscrete().
        // DesktopEntry.execute() cannot carry an environment (upstream docs:
        // "Currently ignores runInTerminal and field codes"), so the argv is
        // built by hand with gpu.js's offloadArgv (D4) and spawned directly
        // rather than through execute().
        function launch(desktopId: string, card: string): string {
            var entry = DesktopEntries.byId(desktopId);
            if (!entry)
                return "error: no desktop entry '" + desktopId + "'";

            var gpuTarget;
            if (card === undefined || card === "") {
                gpuTarget = GpuService.defaultDiscrete();
                if (!gpuTarget)
                    return "error: no discrete GPU on this machine";
            } else {
                gpuTarget = GpuService.cardById(card);
                if (!gpuTarget)
                    return "error: no GPU card '" + card + "'";
            }

            var exec = entry.execString;
            if (entry.workingDirectory)
                exec = "cd " + root._shq(entry.workingDirectory) + " && " + exec;

            var argv = Gpu.offloadArgv(exec, gpuTarget, GpuService.tools);
            var bare = true;
            if (entry.runInTerminal) {
                var term = root._terminalArgv();
                if (term.length > 0) {
                    argv = term.concat(argv);
                    bare = false;
                }
            }

            CompositorService.spawn(argv);

            var reply = "ok: launched '" + desktopId + "' on " + gpuTarget.card + " (" + gpuTarget.name + "): " + argv.join(" ");
            if (entry.runInTerminal && bare)
                reply += " [runInTerminal, but console.command is not set: spawned bare]";
            return reply;
        }

        // `target`: "" reports GpuService.gfxMode (the last collector tick's
        // reading of supergfxctl -g); "integrated" or "hybrid" switches it.
        // supergfxctl's own switch needs a logout or reboot to take effect, so
        // the reply says so rather than implying it happened live.
        function mode(target: string): string {
            if (target === undefined || target === "") {
                if (!GpuService.gfxMode.supported)
                    return "error: supergfxctl not found on PATH, GPU mode switching is unsupported";
                return "mode: " + GpuService.gfxMode.mode;
            }
            if (target !== "integrated" && target !== "hybrid")
                return "error: target must be integrated, hybrid, or '' to report the current mode";
            if (!GpuService.gfxMode.supported)
                return "error: supergfxctl not found on PATH, GPU mode switching is unsupported";
            modeProc.command = ["supergfxctl", "-m", target];
            modeProc.running = true;
            return "ok: supergfxctl -m " + target + " issued, needs a logout or reboot to take effect";
        }
    }

    // supergfxctl's actual exit status lands here, never in mode()'s own
    // reply: that reply already went out before this process could finish,
    // the same synchronous-reply constraint ScreenshotIpc's grim/slurp
    // pipeline documents.
    Process {
        id: modeProc
        stdout: StdioCollector { id: modeOut }
        stderr: StdioCollector { id: modeErr }
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("MonitorIpc: supergfxctl -m failed:", modeErr.text || modeOut.text);
        }
    }
}
