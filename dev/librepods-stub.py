#!/usr/bin/env python3
"""The omarchy-pods librepods daemon's IPC, for FormalShell's --earbuds leg.

Reconstructed from omarchy-pods v1.0.2 (daemon/main.cpp, the QLocalServer
newConnection handler, and writeStateFile), the build ~/.config/nix packages:
one connection carries one verb, read in one go with no terminator, matched
exactly, and the daemon hangs up after it. `status` is answered with the
status line; an unknown verb is logged as the daemon logs it. A noise verb
for the mode already held is dropped, as setNoiseControlMode does. The state
file is rewritten through a rename, as QSaveFile does.

--hang plays the daemon e1504g ran on 2026-10-09: its main thread blocked in
pa_threaded_mainloop_wait, the socket still listening and never accepting.

Every verb received is appended to --log, one per line, exactly as read.
"""
import argparse
import json
import os
import socket
import sys
import time

NOISE = {"noise:off": 0, "noise:anc": 1, "noise:transparency": 2, "noise:adaptive": 3}
EAR = {"ear:one": 0, "ear:both": 1, "ear:off": 2}


def write_status(path, status):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(json.dumps(status, sort_keys=True, separators=(",", ":")) + "\n")
    os.replace(tmp, path)


def apply(status, verb):
    if verb in NOISE:
        if status.get("noise_mode") != NOISE[verb]:
            status["noise_mode"] = NOISE[verb]
            status["noise_control_changes_total"] = status.get("noise_control_changes_total", 0) + 1
        return True
    if verb in EAR:
        status["ear_detection_behavior"] = EAR[verb]
        return True
    if verb in ("ca:on", "ca:off"):
        status["conversational_awareness"] = verb == "ca:on"
        return True
    if verb in ("onebud:on", "onebud:off"):
        status["one_bud_anc_mode"] = verb == "onebud:on"
        return True
    if verb.startswith("adaptive:"):
        tail = verb[len("adaptive:"):]
        if tail.isdigit() and 0 <= int(tail) <= 100 and status.get("noise_mode") == 3:
            status["adaptive_noise_level"] = int(tail)
        return True
    return verb in ("noise:cycle", "forget", "connect", "disconnect", "reopen", "status")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--socket", required=True)
    ap.add_argument("--status", required=True, help="status.json to publish, seeded from --fixture")
    ap.add_argument("--fixture", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--hang", action="store_true", help="listen and never accept, as a daemon with its event loop stuck")
    args = ap.parse_args()

    with open(args.fixture) as f:
        status = json.load(f)
    os.makedirs(os.path.dirname(args.status), exist_ok=True)
    write_status(args.status, status)

    try:
        os.unlink(args.socket)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(args.socket)
    server.listen(8)
    if args.hang:
        # The daemon with its event loop stuck: the kernel still queues
        # connections on the listening socket, nothing ever accepts them.
        while True:
            time.sleep(60)
    while True:
        conn, _ = server.accept()
        with conn:
            conn.settimeout(2)
            try:
                data = conn.recv(4096)
            except socket.timeout:
                data = b""
            if not data:
                continue
            verb = data.decode("utf-8", "replace")
            with open(args.log, "a") as log:
                log.write(verb + "\n")
            if not apply(status, verb):
                print(f"Unknown message received: {verb!r}", file=sys.stderr, flush=True)
            elif verb == "status":
                conn.sendall(json.dumps(status, sort_keys=True, separators=(",", ":")).encode() + b"\n")
            write_status(args.status, status)


if __name__ == "__main__":
    main()
