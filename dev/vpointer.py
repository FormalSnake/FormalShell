#!/usr/bin/env python3
"""A held-button pointer drag over zwlr_virtual_pointer_v1, which wlrctl
cannot do (its `pointer click` presses and releases in one go).

    vpointer.py down | up | move DX DY | wait MS ...

Steps run in order on one virtual pointer. Every event carries the
monotonic clock in milliseconds as its time, the way a real device's
events do, and is followed by a frame. Talks the Wayland wire protocol
directly, so it needs nothing but python3 and WAYLAND_DISPLAY.
"""

import os
import socket
import struct
import sys
import time

BTN_LEFT = 0x110


class Wire:
    def __init__(self):
        name = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
        path = name if name.startswith("/") else os.path.join(os.environ["XDG_RUNTIME_DIR"], name)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.next_id = 2
        self.buf = b""

    def new_id(self):
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj, opcode, payload=b""):
        self.sock.sendall(struct.pack("<II", obj, ((8 + len(payload)) << 16) | opcode) + payload)

    def read(self):
        while len(self.buf) < 8 or len(self.buf) < (struct.unpack_from("<I", self.buf, 4)[0] >> 16):
            chunk = self.sock.recv(65536)
            if not chunk:
                sys.exit("vpointer: compositor closed the connection")
            self.buf += chunk
        obj, word = struct.unpack_from("<II", self.buf)
        size = word >> 16
        body = self.buf[8:size]
        self.buf = self.buf[size:]
        return obj, word & 0xFFFF, body

    def roundtrip(self, on_event=None):
        callback = self.new_id()
        self.send(1, 0, struct.pack("<I", callback))
        while True:
            obj, op, body = self.read()
            if obj == 1 and op == 0:
                _, code, n = struct.unpack_from("<III", body)
                sys.exit(f"vpointer: protocol error {code}: {body[12:12 + n - 1].decode()}")
            if obj == callback:
                return
            if on_event:
                on_event(obj, op, body)


def string(s):
    b = s.encode() + b"\0"
    return struct.pack("<I", len(b)) + b + b"\0" * (-len(b) % 4)


def fixed(v):
    return struct.pack("<i", int(round(v * 256)))


def main(steps):
    w = Wire()
    registry = w.new_id()
    w.send(1, 1, struct.pack("<I", registry))
    found = {}

    def global_(obj, op, body):
        if obj == registry and op == 0:
            name, n = struct.unpack_from("<II", body)
            iface = body[8:8 + n - 1].decode()
            version = struct.unpack_from("<I", body, 8 + n + (-n % 4))[0]
            found[iface] = (name, version)

    w.roundtrip(global_)
    if "zwlr_virtual_pointer_manager_v1" not in found:
        sys.exit("vpointer: no zwlr_virtual_pointer_manager_v1")
    name, _ = found["zwlr_virtual_pointer_manager_v1"]
    manager = w.new_id()
    w.send(registry, 0, struct.pack("<I", name) + string("zwlr_virtual_pointer_manager_v1") + struct.pack("<II", 1, manager))
    pointer = w.new_id()
    w.send(manager, 0, struct.pack("<II", 0, pointer))
    w.roundtrip()

    def stamp():
        return int(time.monotonic() * 1000) & 0xFFFFFFFF

    i = 0
    while i < len(steps):
        step = steps[i]
        if step in ("down", "up"):
            w.send(pointer, 2, struct.pack("<III", stamp(), BTN_LEFT, 1 if step == "down" else 0))
            w.send(pointer, 4)
            i += 1
        elif step == "move":
            dx, dy = float(steps[i + 1]), float(steps[i + 2])
            w.send(pointer, 0, struct.pack("<I", stamp()) + fixed(dx) + fixed(dy))
            w.send(pointer, 4)
            i += 3
        elif step == "wait":
            w.roundtrip()
            time.sleep(float(steps[i + 1]) / 1000)
            i += 2
        else:
            sys.exit(f"vpointer: unknown step {step}")
    w.send(pointer, 8)
    w.roundtrip()


if __name__ == "__main__":
    main(sys.argv[1:])
