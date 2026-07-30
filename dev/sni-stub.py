#!/usr/bin/env python3
"""Minimal StatusNotifierItem producer for FormalShell's --tray smoke fixture.

Registers a real org.kde.StatusNotifierItem object on the session bus and
announces it to whatever org.kde.StatusNotifierWatcher is running —
Quickshell.Services.SystemTray owns that name itself once referenced (see
shell/Surfaces/Bar/widgets/Tray.qml's own header comment) — so the tray
widget has genuine items to render, never anything faked inside the shell.
The icon is a flat color square built at runtime from --color (no icon-theme
lookup: the VM ships no icon theme), using the exact wire format quickshell
actually decodes for IconPixmap — network/big-endian ARGB32 bytes per pixel,
confirmed against quickshell's own src/services/status_notifier/
dbus_item_types.cpp. No DBusMenu is exposed here (hasMenu stays false): a
correct minimal DBusMenu server is a bigger lift than a headless smoke run
without synthetic pointer input can ever exercise (the shell's own
QsMenuAnchor consumption of a real menu is exercised on real hardware).
"""
import argparse
import sys
import time

import gi

gi.require_version("GLib", "2.0")
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

ITEM_INTERFACE_XML = """<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="u" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionMovieName" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <method name="ContextMenu">
      <arg type="i" direction="in" name="x"/>
      <arg type="i" direction="in" name="y"/>
    </method>
    <method name="Activate">
      <arg type="i" direction="in" name="x"/>
      <arg type="i" direction="in" name="y"/>
    </method>
    <method name="SecondaryActivate">
      <arg type="i" direction="in" name="x"/>
      <arg type="i" direction="in" name="y"/>
    </method>
    <method name="Scroll">
      <arg type="i" direction="in" name="delta"/>
      <arg type="s" direction="in" name="orientation"/>
    </method>
    <signal name="NewTitle"/>
    <signal name="NewIcon"/>
    <signal name="NewAttentionIcon"/>
    <signal name="NewOverlayIcon"/>
    <signal name="NewToolTip"/>
    <signal name="NewStatus">
      <arg type="s" name="status"/>
    </signal>
  </interface>
</node>"""


def make_icon_pixmap(color_hex, size=22):
    r = int(color_hex[0:2], 16)
    g = int(color_hex[2:4], 16)
    b = int(color_hex[4:6], 16)
    pixel = bytes([0xFF, r, g, b])  # A,R,G,B big-endian per pixel
    return GLib.Variant("a(iiay)", [(size, size, pixel * (size * size))])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--id", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--color", required=True, help="icon fill color, RRGGBB")
    parser.add_argument(
        "--activate-file",
        help="append '<id>: <method>(x, y)' here on Activate/SecondaryActivate, "
        "so the smoke rig can assert the shell's activate path reached this item",
    )
    args = parser.parse_args()

    props = {
        "Category": GLib.Variant("s", "ApplicationStatus"),
        "Id": GLib.Variant("s", args.id),
        "Title": GLib.Variant("s", args.title),
        "Status": GLib.Variant("s", "Active"),
        "WindowId": GLib.Variant("u", 0),
        "IconThemePath": GLib.Variant("s", ""),
        "IconName": GLib.Variant("s", ""),
        "IconPixmap": make_icon_pixmap(args.color),
        "OverlayIconName": GLib.Variant("s", ""),
        "OverlayIconPixmap": GLib.Variant("a(iiay)", []),
        "AttentionIconName": GLib.Variant("s", ""),
        "AttentionIconPixmap": GLib.Variant("a(iiay)", []),
        "AttentionMovieName": GLib.Variant("s", ""),
        "ToolTip": GLib.Variant("(sa(iiay)ss)", ("", [], args.title, "")),
    }

    def handle_method_call(connection, sender, object_path, interface_name, method_name, parameters, invocation):
        if method_name in ("Activate", "SecondaryActivate", "ContextMenu"):
            x, y = parameters.unpack()
            print(f"{args.id}: {method_name}({x}, {y})", flush=True)
            if args.activate_file and method_name in ("Activate", "SecondaryActivate"):
                with open(args.activate_file, "a") as f:
                    f.write(f"{args.id}: {method_name}({x}, {y})\n")
            invocation.return_value(None)
        elif method_name == "Scroll":
            delta, orientation = parameters.unpack()
            print(f"{args.id}: Scroll({delta}, {orientation})", flush=True)
            invocation.return_value(None)
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method_name)

    def handle_get_property(connection, sender, object_path, interface_name, property_name):
        return props.get(property_name)

    node_info = Gio.DBusNodeInfo.new_for_xml(ITEM_INTERFACE_XML)
    iface_info = node_info.lookup_interface("org.kde.StatusNotifierItem")

    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    connection.register_object(
        "/StatusNotifierItem",
        iface_info,
        handle_method_call,
        handle_get_property,
        None,
    )

    # The watcher (quickshell's own StatusNotifierWatcher, at
    # org.kde.StatusNotifierWatcher) only exists once the shell has
    # referenced SystemTray/StatusNotifierHost — retry briefly rather than
    # assume a fixed startup delay always wins that race.
    unique_name = connection.get_unique_name()
    last_error = None
    for _ in range(20):
        try:
            connection.call_sync(
                "org.kde.StatusNotifierWatcher",
                "/StatusNotifierWatcher",
                "org.kde.StatusNotifierWatcher",
                "RegisterStatusNotifierItem",
                GLib.Variant("(s)", (unique_name,)),
                None,
                Gio.DBusCallFlags.NONE,
                2000,
                None,
            )
            last_error = None
            break
        except GLib.Error as error:
            last_error = error
            time.sleep(0.5)

    if last_error is not None:
        print(f"{args.id}: failed to register with StatusNotifierWatcher: {last_error}", file=sys.stderr, flush=True)
        sys.exit(1)

    print(f"{args.id}: registered as {unique_name}", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
