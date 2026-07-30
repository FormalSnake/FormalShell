// formalshell-eds: Evolution Data Server calendar companion CLI (M12).
//
// EDS's CalendarFactory watches the calling client's unique bus name and
// tears the opened backend down the instant that name vanishes, so the
// whole OpenCalendar -> Open -> GetObjectList handshake must run over one
// held connection (docs/spikes/2026-07-28-eds-calendar-events.md). This
// process opens a single sd-bus connection, does every call on it, and only
// then exits. libc carries IO/argv/formatting; Zig std use is confined to
// stable slice helpers (std.mem) so the file doesn't chase std API churn.
//
// Wire facts, introspected against EDS 3.60.2 (not guessed):
//   OpenCalendar(s uid) -> (ss path busname)   [path arrives typed s, not o]
//   Open() -> (as)   GetObjectList(s sexp) -> (as)
//   CreateObjects(as ics, u opflags) -> (as uids)

const std = @import("std");
const c = @cImport({
    // ReleaseSafe defines __OPTIMIZE__, which arms glibc's fortify wrapper
    // headers (bits/fcntl2.h et al) whose error-attribute guards
    // translate-c cannot digest. Fortification guards nothing in
    // translated declarations, so switch it off for this unit only.
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("systemd/sd-bus.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
});

const sources_dest = "org.gnome.evolution.dataserver.Sources5";
const sources_path = "/org/gnome/evolution/dataserver/SourceManager";
const cal_dest = "org.gnome.evolution.dataserver.Calendar8";
const factory_path = "/org/gnome/evolution/dataserver/CalendarFactory";
const factory_iface = "org.gnome.evolution.dataserver.CalendarFactory";
const cal_iface = "org.gnome.evolution.dataserver.Calendar";
const source_iface = "org.gnome.evolution.dataserver.Source";

const usage_text =
    \\formalshell-eds - Evolution Data Server calendar companion for FormalShell
    \\
    \\usage:
    \\  formalshell-eds sources
    \\      JSON array of calendar sources: [{"uid","displayName","backend"}].
    \\      Only sources carrying a [Calendar] extension are listed.
    \\  formalshell-eds events [--days N] [--source UID ...]
    \\      Raw ICS (concatenated VEVENTs) for events from yesterday through
    \\      today+N days (default 45), from every calendar source unless
    \\      --source narrows the set. Empty output with exit 0 means no
    \\      events; exit 1 with a stderr line means the bus or EDS is
    \\      unreachable. A single failing source is a stderr warning, not a
    \\      failure, unless every requested source fails.
    \\  formalshell-eds seed <summary> <YYYY-MM-DD>
    \\      Test-rig helper: CreateObjects one timed VEVENT (12:00Z-13:00Z)
    \\      into system-calendar and print its UID. Exists for the headless
    \\      smoke rig; not part of the shell's runtime contract.
    \\
;

const Source = struct { uid: [*c]u8, display: [*c]u8, backend: [*c]u8 };
var g_sources: [512]Source = undefined;
var g_nsources: usize = 0;

fn cstr(p: [*c]const u8) []const u8 {
    return p[0..c.strlen(p)];
}

fn busErr(what: [*c]const u8, err: *const c.sd_bus_error, r: c_int) void {
    if (err.name != null) {
        const msg: [*c]const u8 = if (err.message != null) err.message else "unknown";
        _ = c.fprintf(c.stderr, "formalshell-eds: %s: %s (%s)\n", what, msg, err.name);
    } else {
        _ = c.fprintf(c.stderr, "formalshell-eds: %s: %s\n", what, c.strerror(-r));
    }
}

// --- keyfile helpers over the Source Data property (GKeyFile text) ---

fn keyfileGet(data: []const u8, group: []const u8, key: []const u8) ?[]const u8 {
    var in_group = false;
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '[') {
            in_group = line.len >= 2 and line[line.len - 1] == ']' and
                std.mem.eql(u8, line[1 .. line.len - 1], group);
            continue;
        }
        if (!in_group) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        if (std.mem.eql(u8, line[0..eq], key)) return line[eq + 1 ..];
    }
    return null;
}

fn keyfileHasGroup(data: []const u8, group: []const u8) bool {
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len >= 2 and line[0] == '[' and line[line.len - 1] == ']' and
            std.mem.eql(u8, line[1 .. line.len - 1], group)) return true;
    }
    return false;
}

fn enabled(data: []const u8, group: []const u8) bool {
    const v = keyfileGet(data, group, "Enabled") orelse return true;
    return !std.mem.eql(u8, v, "false");
}

// --- source discovery ---

// GetManagedObjects reply: a{oa{sa{sv}}}. Collect UID/Data off every
// org.gnome.evolution.dataserver.Source interface, keep only sources whose
// Data carries an enabled [Calendar] extension.
fn collectSources(bus: ?*c.sd_bus) bool {
    var err: c.sd_bus_error = std.mem.zeroes(c.sd_bus_error);
    defer c.sd_bus_error_free(&err);
    var reply: ?*c.sd_bus_message = null;
    defer _ = c.sd_bus_message_unref(reply);

    var r = c.sd_bus_call_method(bus, sources_dest, sources_path,
        "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", &err, &reply, "");
    if (r < 0) {
        busErr("GetManagedObjects", &err, r);
        return false;
    }

    r = c.sd_bus_message_enter_container(reply, 'a', "{oa{sa{sv}}}");
    if (r < 0) return false;
    while (c.sd_bus_message_enter_container(reply, 'e', "oa{sa{sv}}") > 0) {
        var objpath: [*c]const u8 = null;
        if (c.sd_bus_message_read(reply, "o", &objpath) < 0) return false;
        if (c.sd_bus_message_enter_container(reply, 'a', "{sa{sv}}") < 0) return false;
        while (c.sd_bus_message_enter_container(reply, 'e', "sa{sv}") > 0) {
            var iface: [*c]const u8 = null;
            if (c.sd_bus_message_read(reply, "s", &iface) < 0) return false;
            if (c.strcmp(iface, source_iface) == 0) {
                var uid: [*c]const u8 = null;
                var data: [*c]const u8 = null;
                if (c.sd_bus_message_enter_container(reply, 'a', "{sv}") < 0) return false;
                while (c.sd_bus_message_enter_container(reply, 'e', "sv") > 0) {
                    var key: [*c]const u8 = null;
                    if (c.sd_bus_message_read(reply, "s", &key) < 0) return false;
                    if (c.strcmp(key, "UID") == 0 or c.strcmp(key, "Data") == 0) {
                        if (c.sd_bus_message_enter_container(reply, 'v', "s") < 0) return false;
                        var val: [*c]const u8 = null;
                        if (c.sd_bus_message_read(reply, "s", &val) < 0) return false;
                        _ = c.sd_bus_message_exit_container(reply);
                        if (key[0] == 'U') uid = val else data = val;
                    } else {
                        _ = c.sd_bus_message_skip(reply, "v");
                    }
                    _ = c.sd_bus_message_exit_container(reply);
                }
                _ = c.sd_bus_message_exit_container(reply);
                if (uid != null and data != null and g_nsources < g_sources.len) {
                    const d = cstr(data);
                    if (keyfileHasGroup(d, "Calendar") and
                        enabled(d, "Data Source") and enabled(d, "Calendar"))
                    {
                        const display = keyfileGet(d, "Data Source", "DisplayName") orelse "";
                        const backend = keyfileGet(d, "Calendar", "BackendName") orelse "";
                        g_sources[g_nsources] = .{
                            .uid = c.strdup(uid),
                            .display = c.strndup(display.ptr, display.len),
                            .backend = c.strndup(backend.ptr, backend.len),
                        };
                        g_nsources += 1;
                    }
                }
            } else {
                _ = c.sd_bus_message_skip(reply, "a{sv}");
            }
            _ = c.sd_bus_message_exit_container(reply);
        }
        _ = c.sd_bus_message_exit_container(reply);
        _ = c.sd_bus_message_exit_container(reply);
    }
    _ = c.sd_bus_message_exit_container(reply);
    return true;
}

// --- calendar handshake (one held connection, see file header) ---

const OpenedCal = struct {
    reply: ?*c.sd_bus_message, // owns objpath/busname storage
    objpath: [*c]const u8,
    busname: [*c]const u8,
};

fn openCalendar(bus: ?*c.sd_bus, uid: [*c]const u8) ?OpenedCal {
    var err: c.sd_bus_error = std.mem.zeroes(c.sd_bus_error);
    defer c.sd_bus_error_free(&err);

    var factory_reply: ?*c.sd_bus_message = null;
    var r = c.sd_bus_call_method(bus, cal_dest, factory_path, factory_iface,
        "OpenCalendar", &err, &factory_reply, "s", uid);
    if (r < 0) {
        busErr(uid, &err, r);
        return null;
    }
    var objpath: [*c]const u8 = null;
    var busname: [*c]const u8 = null;
    if (c.sd_bus_message_read(factory_reply, "ss", &objpath, &busname) < 0) {
        _ = c.sd_bus_message_unref(factory_reply);
        return null;
    }

    var open_reply: ?*c.sd_bus_message = null;
    r = c.sd_bus_call_method(bus, busname, objpath, cal_iface, "Open", &err, &open_reply, "");
    _ = c.sd_bus_message_unref(open_reply);
    if (r < 0) {
        busErr(uid, &err, r);
        _ = c.sd_bus_message_unref(factory_reply);
        return null;
    }
    return .{ .reply = factory_reply, .objpath = objpath, .busname = busname };
}

fn listObjects(bus: ?*c.sd_bus, cal: OpenedCal, sexp: [*c]const u8) bool {
    var err: c.sd_bus_error = std.mem.zeroes(c.sd_bus_error);
    defer c.sd_bus_error_free(&err);
    var reply: ?*c.sd_bus_message = null;
    defer _ = c.sd_bus_message_unref(reply);

    const r = c.sd_bus_call_method(bus, cal.busname, cal.objpath, cal_iface,
        "GetObjectList", &err, &reply, "s", sexp);
    if (r < 0) {
        busErr("GetObjectList", &err, r);
        return false;
    }
    if (c.sd_bus_message_enter_container(reply, 'a', "s") < 0) return false;
    while (true) {
        var obj: [*c]const u8 = null;
        const rr = c.sd_bus_message_read(reply, "s", &obj);
        if (rr <= 0) break;
        _ = c.fputs(obj, c.stdout);
        _ = c.fputc('\n', c.stdout);
    }
    _ = c.sd_bus_message_exit_container(reply);
    return true;
}

// --- date helpers (no std.time: civil date from epoch days, Hinnant) ---

const Civil = struct { y: i64, m: u32, d: u32 };

fn civilFromDays(z0: i64) Civil {
    const z = z0 + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d: u32 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u32 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    return .{ .y = yoe + era * 400 + @intFromBool(m <= 2), .m = m, .d = d };
}

fn fmtDayUtc(buf: []u8, epoch_day: i64) void {
    const cv = civilFromDays(epoch_day);
    _ = c.snprintf(buf.ptr, buf.len, "%04lld%02u%02uT000000Z", @as(c_longlong, cv.y), @as(c_uint, cv.m), @as(c_uint, cv.d));
}

// --- subcommands ---

fn cmdSources(bus: ?*c.sd_bus) c_int {
    if (!collectSources(bus)) return 1;
    _ = c.fputc('[', c.stdout);
    for (0..g_nsources) |i| {
        if (i > 0) _ = c.fputc(',', c.stdout);
        _ = c.fputs("{\"uid\":\"", c.stdout);
        jsonEscape(cstr(g_sources[i].uid));
        _ = c.fputs("\",\"displayName\":\"", c.stdout);
        jsonEscape(cstr(g_sources[i].display));
        _ = c.fputs("\",\"backend\":\"", c.stdout);
        jsonEscape(cstr(g_sources[i].backend));
        _ = c.fputs("\"}", c.stdout);
    }
    _ = c.fputs("]\n", c.stdout);
    return 0;
}

fn jsonEscape(s: []const u8) void {
    for (s) |ch| {
        switch (ch) {
            '"' => _ = c.fputs("\\\"", c.stdout),
            '\\' => _ = c.fputs("\\\\", c.stdout),
            '\n' => _ = c.fputs("\\n", c.stdout),
            '\r' => _ = c.fputs("\\r", c.stdout),
            '\t' => _ = c.fputs("\\t", c.stdout),
            else => if (ch < 0x20) {
                _ = c.fprintf(c.stdout, "\\u%04x", @as(c_uint, ch));
            } else {
                _ = c.fputc(ch, c.stdout);
            },
        }
    }
}

fn cmdEvents(bus: ?*c.sd_bus, days: i64, req: []const [*c]const u8) c_int {
    const today = @divFloor(@as(i64, c.time(null)), 86400);
    var start_buf: [32]u8 = undefined;
    var end_buf: [32]u8 = undefined;
    fmtDayUtc(&start_buf, today - 1);
    fmtDayUtc(&end_buf, today + days + 1);
    var sexp_buf: [128]u8 = undefined;
    _ = c.snprintf(&sexp_buf, sexp_buf.len, "(occur-in-time-range? (make-time \"%s\") (make-time \"%s\"))", &start_buf, &end_buf);

    var uids: []const [*c]const u8 = req;
    var auto_uids: [512][*c]const u8 = undefined;
    if (req.len == 0) {
        if (!collectSources(bus)) return 1;
        for (0..g_nsources) |i| auto_uids[i] = g_sources[i].uid;
        uids = auto_uids[0..g_nsources];
    }

    var ok: usize = 0;
    for (uids) |uid| {
        const cal = openCalendar(bus, uid) orelse continue;
        defer _ = c.sd_bus_message_unref(cal.reply);
        if (listObjects(bus, cal, &sexp_buf)) ok += 1;
    }
    if (uids.len > 0 and ok == 0) return 1;
    return 0;
}

fn cmdSeed(bus: ?*c.sd_bus, summary: [*c]const u8, date: [*c]const u8) c_int {
    var y: c_int = 0;
    var mo: c_int = 0;
    var d: c_int = 0;
    if (c.strlen(date) != 10 or c.sscanf(date, "%4d-%2d-%2d", &y, &mo, &d) != 3 or
        y < 1970 or mo < 1 or mo > 12 or d < 1 or d > 31)
    {
        _ = c.fprintf(c.stderr, "formalshell-eds: seed date must be YYYY-MM-DD, got \"%s\"\n", date);
        return 2;
    }

    const now = @as(i64, c.time(null));
    const nc = civilFromDays(@divFloor(now, 86400));
    const secs = @mod(now, 86400);

    const slen = c.strlen(summary);
    const esc: [*c]u8 = @ptrCast(c.malloc(slen * 2 + 1));
    var n: usize = 0;
    for (summary[0..slen]) |ch| {
        switch (ch) {
            '\\', ';', ',' => {
                esc[n] = '\\';
                esc[n + 1] = ch;
                n += 2;
            },
            '\n' => {
                esc[n] = '\\';
                esc[n + 1] = 'n';
                n += 2;
            },
            else => {
                esc[n] = ch;
                n += 1;
            },
        }
    }
    esc[n] = 0;

    const vevent_buf: [*c]u8 = @ptrCast(c.malloc(n + 512));
    _ = c.snprintf(vevent_buf, n + 512,
        "BEGIN:VEVENT\r\nUID:formalshell-seed-%lld-%d\r\nDTSTAMP:%04lld%02u%02uT%02lld%02lld%02lldZ\r\nDTSTART:%04d%02d%02dT120000Z\r\nDTEND:%04d%02d%02dT130000Z\r\nSUMMARY:%s\r\nEND:VEVENT\r\n",
        @as(c_longlong, now), c.getpid(),
        @as(c_longlong, nc.y), @as(c_uint, nc.m), @as(c_uint, nc.d),
        @as(c_longlong, @divFloor(secs, 3600)), @as(c_longlong, @mod(@divFloor(secs, 60), 60)), @as(c_longlong, @mod(secs, 60)),
        y, mo, d, y, mo, d, esc);

    const cal = openCalendar(bus, "system-calendar") orelse return 1;
    defer _ = c.sd_bus_message_unref(cal.reply);

    var err: c.sd_bus_error = std.mem.zeroes(c.sd_bus_error);
    defer c.sd_bus_error_free(&err);
    var reply: ?*c.sd_bus_message = null;
    defer _ = c.sd_bus_message_unref(reply);
    const r = c.sd_bus_call_method(bus, cal.busname, cal.objpath, cal_iface,
        "CreateObjects", &err, &reply, "asu", @as(c_uint, 1), vevent_buf, @as(c_uint, 0));
    if (r < 0) {
        busErr("CreateObjects", &err, r);
        return 1;
    }
    if (c.sd_bus_message_enter_container(reply, 'a', "s") >= 0) {
        var uid: [*c]const u8 = null;
        if (c.sd_bus_message_read(reply, "s", &uid) > 0) {
            _ = c.fputs(uid, c.stdout);
            _ = c.fputc('\n', c.stdout);
        }
        _ = c.sd_bus_message_exit_container(reply);
    }
    return 0;
}

pub export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc < 2) {
        _ = c.fputs(usage_text, c.stderr);
        return 2;
    }
    const cmd = argv[1];
    if (c.strcmp(cmd, "--help") == 0 or c.strcmp(cmd, "-h") == 0 or c.strcmp(cmd, "help") == 0) {
        _ = c.fputs(usage_text, c.stdout);
        return 0;
    }

    var bus: ?*c.sd_bus = null;
    const br = c.sd_bus_open_user(&bus);
    if (br < 0) {
        _ = c.fprintf(c.stderr, "formalshell-eds: cannot connect to session bus: %s\n", c.strerror(-br));
        return 1;
    }
    defer _ = c.sd_bus_flush_close_unref(bus);

    if (c.strcmp(cmd, "sources") == 0) {
        if (argc != 2) {
            _ = c.fputs(usage_text, c.stderr);
            return 2;
        }
        return cmdSources(bus);
    }
    if (c.strcmp(cmd, "events") == 0) {
        var days: i64 = 45;
        var req: [128][*c]const u8 = undefined;
        var nreq: usize = 0;
        var i: usize = 2;
        while (i < @as(usize, @intCast(argc))) : (i += 1) {
            if (c.strcmp(argv[i], "--days") == 0 and i + 1 < argc) {
                i += 1;
                days = c.strtol(argv[i], null, 10);
                if (days < 0 or days > 3650) {
                    _ = c.fprintf(c.stderr, "formalshell-eds: --days must be 0..3650\n");
                    return 2;
                }
            } else if (c.strcmp(argv[i], "--source") == 0 and i + 1 < argc and nreq < req.len) {
                i += 1;
                req[nreq] = argv[i];
                nreq += 1;
            } else {
                _ = c.fputs(usage_text, c.stderr);
                return 2;
            }
        }
        return cmdEvents(bus, days, req[0..nreq]);
    }
    if (c.strcmp(cmd, "seed") == 0) {
        if (argc != 4) {
            _ = c.fputs(usage_text, c.stderr);
            return 2;
        }
        return cmdSeed(bus, argv[2], argv[3]);
    }
    _ = c.fputs(usage_text, c.stderr);
    return 2;
}
