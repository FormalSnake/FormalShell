#!/usr/bin/env bash
# Records how `qs ipc` answers, as the goldens formalshell-ipc is held to
# (crates/formalshell-rs/tests/ipc-golden.jsonl). Runs inside the VM:
#
#   dev/vm-lock.sh just vm-ipc-golden > crates/formalshell-rs/tests/ipc-golden.jsonl
#
# The shell is a stub of IpcHandlers on Qt's offscreen platform, so no
# compositor is involved: what is recorded is qs's own argument parsing,
# type conversion, error strings, output framing and exit codes. `debug`,
# `theme` and `wallpaper` carry DebugIpc.qml's, ThemeIpc.qml's and
# WallpaperIpc.qml's exact signatures, `bar`, `panel`, `media`, `radio`,
# `airplay`, `visualizer`, `overnight`, `earbuds`, `display`, `hdr` and
# `workspaces` their own IPC files' (WorkspacesIpc.qml's `status` only: peek
# and close wait for the preview), `calendar`, `iphone`, `notifications` and
# `reminder` their own; `probe` covers every type qs converts and the
# function names that collide with qs's subcommands.
set -euo pipefail

dir=$(mktemp -d)
trap 'kill "$qs_pid" 2>/dev/null || true; rm -rf "$dir"' EXIT
mkdir -p "$dir/shell" "$dir/run"
export XDG_RUNTIME_DIR="$dir/run" QT_QPA_PLATFORM=offscreen
unset WAYLAND_DISPLAY

cat > "$dir/shell/shell.qml" <<'EOF'
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    IpcHandler {
        target: "debug"
        function dump(): string { return "{}" }
        function join(edge: string, x: int, width: int): string { return "join " + edge + " " + x + " " + width }
        function joinClear(): string { return "ok" }
        function motionScale(percent: int): string { return "ms " + percent }
        function query(q: string): string { return JSON.stringify([q]) }
    }
    IpcHandler {
        target: "theme"
        function retheme(): string { return "ok" }
        function mode(m: string): string { return "mode " + m }
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "wallpaper"
        function set(path: string): string { return "set " + path }
        function get(): string { return "" }
    }
    IpcHandler {
        target: "bar"
        function chevron(action: string): string { return "chevron " + action }
        function chevronAt(action: string, region: string): string { return "chevronAt " + action + " " + region }
        function room(): string { return "[]" }
        function paint(): string { return "[]" }
    }
    IpcHandler {
        target: "panel"
        function open(name: string): string { return "open " + name }
        function close(): string { return "ok" }
        function toggle(name: string): string { return "toggle " + name }
        function toggleAt(n: int): string { return "toggleAt " + n }
        function state(): string { return "" }
    }
    IpcHandler {
        target: "media"
        function playPause(): string { return "playPause" }
        function next(): string { return "next" }
        function previous(): string { return "previous" }
        function shuffle(mode: string): string { return "shuffle " + mode }
        function loop(mode: string): string { return "loop " + mode }
        function volume(percent: int): string { return "volume " + percent }
        function raise(): string { return "raise" }
        function select(id: string): string { return "select " + id }
        function players(): string { return "[]" }
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "radio"
        function status(): string { return "{}" }
        function play(id: string): string { return "play " + id }
        function toggle(): string { return "toggle" }
        function random(): string { return "random" }
        function stop(): string { return "stop" }
    }
    IpcHandler {
        target: "airplay"
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "visualizer"
        function style(name: string): string { return "style " + name }
        function styles(): string { return "bars\nline" }
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "tray"
        function status(): string { return "{}" }
        function activate(id: string): string { return "activate " + id }
        function menu(id: string): string { return "menu " + id }
        function menucursor(delta: string): string { return "menucursor " + delta }
        function menuactivate(): string { return "ok" }
    }
    IpcHandler {
        target: "overnight"
        function toggle(): string { return "ok" }
        function enable(): string { return "ok" }
        function disable(): string { return "ok" }
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "earbuds"
        function status(): string { return "{}" }
        function devices(): string { return "[]" }
        function select(key: string): string { return "select " + key }
        function set(control: string, value: string): string { return "set " + control + " " + value }
    }
    IpcHandler {
        target: "workspaces"
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "network"
        function status(): string { return "{}" }
        function connect(ssid: string, psk: string): string { return "connect " + ssid + " " + psk }
        function connectEap(ssid: string, identity: string, password: string): string { return "connectEap " + ssid + " " + identity + " " + password }
        function forget(ssid: string): string { return "forget " + ssid }
        function wifi(enabled: bool): string { return "wifi " + enabled }
        function speedtest(): string { return "ok" }
        function speedstatus(): string { return "{}" }
    }
    IpcHandler {
        target: "monitor"
        function status(): string { return "{}" }
        function processes(query: string): string { return "processes " + query }
        function kill(pid: string, signal: string): string { return "kill " + pid + " " + signal }
        function restart(pid: string): string { return "restart " + pid }
        function gpu(): string { return "{}" }
    }
    IpcHandler {
        target: "plugins"
        function list(): string { return "[]" }
        function status(): string { return "{}" }
        function reload(): string { return "ok" }
    }
    IpcHandler {
        target: "caffeinate"
        function toggle(): string { return "ok" }
        function enable(): string { return "ok" }
        function disable(): string { return "ok" }
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "lock"
        function lock(): string { return "ok" }
        function isLocked(): string { return "false" }
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "gallery"
        function open(): string { return "ok" }
        function close(): string { return "ok" }
        function toggle(): string { return "ok" }
        function status(): string { return JSON.stringify({ isOpen: false }) }
    }
    IpcHandler {
        target: "menu"
        function toggle(): string { return "ok" }
        function summon(route: string): string { return "summon " + route }
        function activate(index: int): string { return "activate " + index }
        function activateAlternate(index: int): string { return "activateAlternate " + index }
        function filter(text: string): string { return "filter " + text }
        function close(): string { return "ok" }
        function refresh(): string { return "ok" }
        function ping(): string { return "pong" }
        function status(): string { return "{}" }
        function select(prompt: string, optionsJson: string, token: string): string { return "select " + prompt + " " + optionsJson + " " + token }
        function input(prompt: string, token: string): string { return "input " + prompt + " " + token }
    }
    IpcHandler {
        target: "calendar"
        function select(date: string): string { return "select " + date }
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "iphone"
        function status(): string { return "{}" }
        function pair(): string { return "ok" }
        function invoke(id: string, action: string): string { return "invoke " + id + " " + action }
        function dismiss(id: string): string { return "dismiss " + id }
        function clear(): string { return "ok" }
        function markRead(): string { return "ok" }
    }
    IpcHandler {
        target: "display"
        function scale(output: string, scale: real): string { return "scale " + output + " " + scale }
        function mirror(output: string, source: string): string { return "mirror " + output + " " + source }
        function enable(output: string, enabled: bool): string { return "enable " + output + " " + enabled }
    }
    IpcHandler {
        target: "hdr"
        function toggle(): string { return "ok" }
        function enable(): string { return "ok" }
        function disable(): string { return "ok" }
        function setOutput(output: string, enabled: bool): string { return "setOutput " + output + " " + enabled }
        function rule(output: string): string { return "rule " + output }
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "notifications"
        function status(): string { return "{}" }
        function dndState(): string { return "off" }
        function toggleDnd(): string { return "on" }
        function setDnd(on: bool): string { return on ? "on" : "off" }
        function showHistory(): string { return "ok" }
        function clear(): string { return "ok" }
        function clearPending(): string { return "ok" }
        function markAllSeen(): string { return "ok" }
        function dismissAll(): string { return "ok" }
        function dismissOne(): string { return "none" }
        function invokeLast(): string { return "ok" }
        function expand(state: string): string { return "expand " + state }
    }
    IpcHandler {
        target: "reminder"
        function set(duration: string, message: string): string { return "set " + duration + " " + message }
        function show(): string { return "ok" }
        function clear(): string { return "ok: cleared 0" }
        function status(): string { return "{}" }
    }
    IpcHandler {
        target: "probe"
        function s(a: string): string { return "[" + a + "]" }
        function ss(a: string, b: string): string { return "[" + a + "][" + b + "]" }
        function sss(a: string, b: string, c: string): string { return "[" + a + "][" + b + "][" + c + "]" }
        function i(a: int): string { return "" + a }
        function b(a: bool): string { return "" + a }
        function r(a: real): string { return "" + a }
        function ri(a: real): real { return a }
        function ii(a: int): int { return a }
        function bb(a: bool): bool { return a }
        function v(): void {}
        function empty(): string { return "" }
        function nl(): string { return "a\nb\n" }
        function show(): string { return "probe-show" }
        function call(): string { return "probe-call" }
    }
}
EOF

qs -p "$dir/shell" > "$dir/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 50); do
  qs ipc -p "$dir/shell" call debug dump > /dev/null 2>&1 && break
  sleep 0.2
done

live=true
rec() {
  local code=0
  qs ipc -p "$dir/shell" "$@" > "$dir/out" 2> "$dir/err" || code=$?
  jq -cn --argjson live "$live" --argjson exit "$code" \
    --rawfile stdout "$dir/out" --rawfile stderr "$dir/err" \
    '{argv: $ARGS.positional, live: $live, stdout: $stdout, stderr: $stderr, exit: $exit}' \
    --args -- "$@"
}

rec call debug dump
rec call tray status
rec call tray activate fixture-1
rec call tray activate
rec call tray activate a b
rec call tray menu 'Tray Fixture 2'
rec call tray menucursor 1
rec call tray menucursor -1
rec call tray menucursor abc
rec call tray menucursor
rec call tray menuactivate
rec call tray menuactivate x
rec call tray nope
rec call debug joinClear
rec call debug join top 10 20
rec call debug join top 10
rec call debug join top 10 20 30
rec call debug join top x 20
rec call debug motionScale 1000
rec call debug motionScale " 12 "
rec call debug motionScale +12
rec call debug motionScale 0x10
rec call debug motionScale 1.5
rec call debug motionScale -5
rec call debug motionScale -- -5
rec call debug query ''
rec call debug query 'a b'
rec call debug query '[1,2]'
rec call debug query ' [1,2]'
rec call debug query '[x]'
rec call debug query '[]'
rec call debug query 'a,b'
rec call debug query '{a,b}'
rec call debug query --x
rec call debug query -x
rec call debug query show
rec call debug query call
rec call debug query prop
rec call debug query 'é ✓'
rec call probe ss '[a,b]'
rec call probe sss '[a,b]' c
rec call probe sss '[a,b,c]'
rec call probe ss a '[]'
rec call probe s '['
rec call probe s ']'
rec call probe s '[a'
rec call probe s '"q"'
rec call probe s "'q'"
rec call probe s 'a\nb'
rec call probe s "$(printf 'a\nb')"
rec call probe ss -- a
rec call probe s --
rec call probe s -
rec call probe show
rec call probe call
rec call probe s show
rec call probe b true
rec call probe b false
rec call probe b 1
rec call probe b 0
rec call probe b 2
rec call probe b yes
rec call probe b TRUE
rec call probe i 2147483648
rec call probe i 007
rec call probe i ' 7'
rec call probe r 1.5
rec call probe r 1e3
rec call probe r nan
rec call probe r inf
rec call probe r ' 2 '
rec call probe ri 0.1
rec call probe ri 3
rec call probe ri 1e21
rec call probe ri 1e-7
rec call probe ri 123456789
rec call probe ii -7
rec call probe bb 1
rec call probe v
rec call probe empty
rec call probe nl
rec call nope dump
rec call debug nope
rec call DEBUG dump
rec call debug
rec call
rec call '' dump
rec call debug ''
rec show
rec call debug dump extra
rec call debug dump --any-display
rec call debug motionScale -1.5
rec call debug motionScale -.5
rec call debug motionScale --5
rec call debug query ---
rec call debug query '-!'
rec call debug query '- x'
rec call debug query -é
rec call debug query --x=1
rec call probe s -- --
rec call probe s -- -x
rec call probe s -- show
rec call probe s -- '[a]'
rec call probe ss a --
rec call probe ss '[a, b]'
rec call probe sss '[a,,b]'
rec call probe ss '[,]'
rec call probe ss '["a,b",c]'
rec call probe s '[[a]]'
rec call probe s '[ ]'
rec call media playPause
rec call media shuffle on
rec call media shuffle
rec call media loop cycle
rec call media volume 30
rec call media volume ' 30 '
rec call media volume -5
rec call media volume 1.5
rec call media volume x
rec call media volume
rec call media select ''
rec call media select 'org.mpris.MediaPlayer2.mpv'
rec call media players
rec call radio play smoke-radio-1
rec call radio play
rec call radio toggle
rec call radio random
rec call radio stop
rec call radio status
rec call airplay status
rec call airplay start
rec call visualizer style next
rec call visualizer style config
rec call visualizer styles
rec call probe s 'x[a,b]'
rec call probe i 'a"b'
rec call probe i 'a\b'
rec call probe i é
rec call probe i "$(printf 'a\tb')"
rec call probe i "$(printf 'a\nb')"
rec call nope show
rec call debug nope show
rec call probe s show extra
rec call debug query wait
rec call debug query listen
rec call debug query get
rec call debug query list
rec call debug query log
rec call debug query msg
rec call debug query ipc
rec call debug query instances
rec show debug
rec show debug query
rec call theme retheme
rec call theme mode toggle
rec call theme mode
rec call theme mode dark light
rec call theme status
rec call theme status x
rec call wallpaper set /tmp/a.png
rec call wallpaper set 'a b'
rec call wallpaper set
rec call wallpaper get
rec call wallpaper get x
rec show theme
rec show wallpaper
rec show wallpaper set
rec call bar chevron status
rec call bar chevron expand
rec call bar chevron
rec call bar chevronAt collapse right
rec call bar chevronAt collapse
rec call bar room
rec call bar room x
rec call bar paint
rec show bar
rec show bar chevronAt
rec call panel open audio
rec call panel open
rec call panel close
rec call panel toggle weather
rec call panel toggleAt 2
rec call panel toggleAt x
rec call panel toggleAt -1
rec call panel state
rec show panel
rec call media status
rec call media status x
rec show media
rec call overnight toggle
rec call overnight status x
rec show overnight
rec call earbuds status
rec call earbuds select
rec call earbuds select 'nothing:AA:BB:CC:DD:EE:FF'
rec call earbuds set anc
rec call earbuds set anc transparency
rec call earbuds set eq-bass -2
rec call earbuds set eq-bass -- -2
rec call earbuds set '[noise,anc]'
rec show earbuds
rec show earbuds set
rec call workspaces status
rec call workspaces status x
rec show workspaces
rec call network status
rec call network connect FORMALTEST
rec call network connect FORMALTEST psk
rec call network connect 'a b' ''
rec call network connectEap FORMALTEST-EAP id pw
rec call network forget FORMALTEST
rec call network wifi true
rec call network wifi 0
rec call network wifi maybe
rec call network speedtest
rec call network speedstatus x
rec show network
rec show network connectEap
rec call monitor status
rec call monitor status x
rec call monitor gpu
rec call monitor processes
rec call monitor processes smokevictim
rec call monitor kill 42
rec call monitor kill 42 TERM
rec call monitor restart 42
rec call monitor nope
rec show monitor
rec call plugins list
rec call plugins list x
rec call plugins status
rec call plugins reload
rec call plugins nope
rec show plugins
rec call caffeinate toggle
rec call caffeinate enable
rec call caffeinate disable
rec call caffeinate status
rec call caffeinate status x
rec show caffeinate
rec call lock isLocked
rec call lock status
rec call lock status x
rec call lock unlock
rec call gallery open
rec call gallery status
rec call gallery status x
rec call gallery toggle
rec call gallery close
rec show gallery
rec call menu toggle
rec call menu summon ''
rec call menu summon emoji
rec call menu summon ':e sob'
rec call menu summon
rec call menu activate 3
rec call menu activate x
rec call menu activate -1
rec call menu activateAlternate 0
rec call menu filter 'a b'
rec call menu filter
rec call menu close
rec call menu refresh
rec call menu ping
rec call menu status
rec call menu select Pick ' ["a","b","c"]' tok1
rec call menu select Pick '["a","b"]' tok1
rec call menu select Pick x
rec call menu input Prompt tok2
rec call menu nope
rec show menu
rec call calendar select 2026-10-06
rec call calendar select
rec call calendar status
rec call calendar status x
rec show calendar
rec call iphone status
rec call iphone pair
rec call iphone invoke 1 positive
rec call iphone invoke 1
rec call iphone invoke
rec call iphone dismiss 1
rec call iphone dismiss
rec call iphone clear
rec call iphone markRead
rec call iphone nope
rec show iphone
rec call display scale DP-1 1.5
rec call display scale DP-1 x
rec call display scale DP-1
rec call display mirror DP-1 ''
rec call display mirror DP-1 eDP-1
rec call display enable DP-1 false
rec call display enable DP-1 1
rec show display
rec call hdr toggle
rec call hdr enable
rec call hdr disable
rec call hdr setOutput DP-1 true
rec call hdr setOutput DP-1
rec call hdr rule DP-1
rec call hdr status
rec call hdr status x
rec show hdr
rec call notifications status
rec call notifications setDnd true
rec call notifications setDnd 1
rec call notifications setDnd
rec call notifications dismissOne
rec call notifications expand on
rec call notifications expand
rec call notifications nope
rec show notifications
rec call reminder set 12s 'SMOKE REMINDER FIXTURE'
rec call reminder set 25m
rec call reminder set 25m ''
rec call reminder clear
rec show reminder

kill "$qs_pid"
wait "$qs_pid" 2>/dev/null || true
live=false
rec call debug dump
rec show
