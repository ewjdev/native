//! System-wide shortcuts through Carbon hot keys, loaded at runtime so no link
//! dependency is added. Hot keys need no Accessibility permission.
const std = @import("std");
const builtin = @import("builtin");
const types = @import("../types.zig");

const OSStatus = i32;
const Ref = ?*anyopaque;
const HotKeyId = extern struct { signature: u32, id: u32 };
const EventTypeSpec = extern struct { class: u32, kind: u32 };
const Handler = *const fn (Ref, Ref, ?*anyopaque) callconv(.c) OSStatus;

const event_not_handled: OSStatus = -9874;
const hot_key_exists: OSStatus = -9878;
const keyboard_class: u32 = 0x6B657962;
const hot_key_pressed: u32 = 5;
const hot_key_released: u32 = 6;
const signature: u32 = 0x4E534753;

const Carbon = struct {
    RegisterEventHotKey: *const fn (u32, u32, HotKeyId, Ref, u32, *Ref) callconv(.c) OSStatus,
    UnregisterEventHotKey: *const fn (Ref) callconv(.c) OSStatus,
    GetApplicationEventTarget: *const fn () callconv(.c) Ref,
    InstallEventHandler: *const fn (Ref, Handler, usize, [*]const EventTypeSpec, ?*anyopaque, *Ref) callconv(.c) OSStatus,
    RemoveEventHandler: *const fn (Ref) callconv(.c) OSStatus,
    GetEventKind: *const fn (Ref) callconv(.c) u32,
    GetEventParameter: *const fn (Ref, u32, u32, ?*u32, usize, ?*usize, ?*anyopaque) callconv(.c) OSStatus,
    TISCopyCurrentKeyboardLayoutInputSource: *const fn () callconv(.c) Ref,
    TISGetInputSourceProperty: *const fn (Ref, Ref) callconv(.c) Ref,
    kTISPropertyUnicodeKeyLayoutData: *const Ref,
    UCKeyTranslate: *const fn (?*const anyopaque, u16, u16, u32, u32, u32, *u32, usize, *usize, [*]u16) callconv(.c) OSStatus,
    LMGetKbdType: *const fn () callconv(.c) u8,
    CFDataGetBytePtr: *const fn (Ref) callconv(.c) ?*const anyopaque,
    CFRelease: *const fn (Ref) callconv(.c) void,
};

var carbon: ?Carbon = null;
var carbon_loaded = false;

fn load() ?Carbon {
    if (comptime builtin.os.tag != .macos or builtin.is_test) return null;
    if (carbon_loaded) return carbon;
    carbon_loaded = true;
    const library = std.c.dlopen("/System/Library/Frameworks/Carbon.framework/Carbon", .{ .LAZY = true }) orelse return null;
    var api: Carbon = undefined;
    inline for (std.meta.fields(Carbon)) |field| {
        @field(api, field.name) = @ptrCast(@alignCast(std.c.dlsym(library, field.name) orelse return null));
    }
    carbon = api;
    return api;
}

pub fn available() bool {
    return load() != null;
}

const Entry = struct {
    binding: types.OwnedShortcut,
    hot_key: Ref = null,
    id: u32 = 0,
    pressed: bool = false,
};

/// The registered hot keys. It must not move after `configure`, because the
/// Carbon handler points at it.
pub const Registry = struct {
    entries: [types.max_global_shortcuts]Entry = undefined,
    count: usize = 0,
    sink: types.GlobalShortcutSink = .{},
    handler: Ref = null,
    next_id: u32 = 0,

    pub fn configure(self: *Registry, shortcuts: []const types.Shortcut, sink: types.GlobalShortcutSink, statuses: []types.GlobalShortcutStatus) !void {
        const api = load() orelse return error.UnsupportedService;
        self.sink = sink;
        if (self.handler == null) {
            const specs = [_]EventTypeSpec{ .{ .class = keyboard_class, .kind = hot_key_pressed }, .{ .class = keyboard_class, .kind = hot_key_released } };
            if (api.InstallEventHandler(api.GetApplicationEventTarget(), handle, specs.len, &specs, self, &self.handler) != 0) return error.UnsupportedService;
        }
        for (self.entries[0..self.count]) |*entry| {
            for (shortcuts) |shortcut| {
                if (entry.binding.matches(shortcut)) break;
            } else self.retire(api, entry);
        }
        var next: [types.max_global_shortcuts]Entry = undefined;
        var count: usize = 0;
        for (shortcuts, statuses) |shortcut, *status| {
            status.* = .registered;
            for (self.entries[0..self.count]) |*entry| {
                if (entry.hot_key != null and entry.binding.matches(shortcut)) {
                    next[count] = entry.*;
                    entry.hot_key = null;
                    break;
                }
            } else {
                self.next_id +%= 1;
                next[count] = .{ .binding = .init(shortcut), .id = self.next_id };
                const code = keyCode(api, shortcut.key) orelse {
                    status.* = .rejected;
                    continue;
                };
                const result = api.RegisterEventHotKey(code, modifierMask(shortcut.modifiers), .{ .signature = signature, .id = self.next_id }, api.GetApplicationEventTarget(), 1, &next[count].hot_key);
                if (result != 0) {
                    status.* = if (result == hot_key_exists) .conflict else .rejected;
                    continue;
                }
            }
            count += 1;
        }
        @memcpy(self.entries[0..count], next[0..count]);
        self.count = count;
    }

    pub fn deinit(self: *Registry) void {
        const api = load() orelse return;
        for (self.entries[0..self.count]) |*entry| self.retire(api, entry);
        self.count = 0;
        if (self.handler != null) _ = api.RemoveEventHandler(self.handler);
        self.handler = null;
    }

    fn retire(self: *Registry, api: Carbon, entry: *Entry) void {
        if (entry.pressed) self.sink.push(.{ .shortcut = entry.binding.shortcut(), .phase = .released });
        entry.pressed = false;
        if (entry.hot_key != null) _ = api.UnregisterEventHotKey(entry.hot_key);
        entry.hot_key = null;
    }
};

fn handle(_: Ref, event: Ref, context: ?*anyopaque) callconv(.c) OSStatus {
    const registry: *Registry = @ptrCast(@alignCast(context.?));
    const api = carbon.?;
    const pressing = api.GetEventKind(event) == hot_key_pressed;
    var id: HotKeyId = .{ .signature = 0, .id = 0 };
    if (api.GetEventParameter(event, 0x2D2D2D2D, 0x686B6964, null, @sizeOf(HotKeyId), null, &id) != 0 or id.signature != signature) return event_not_handled;
    for (registry.entries[0..registry.count]) |*entry| {
        if (entry.id != id.id or entry.pressed == pressing) continue;
        entry.pressed = pressing;
        registry.sink.push(.{ .shortcut = entry.binding.shortcut(), .phase = if (pressing) .pressed else .released });
    }
    return 0;
}

fn modifierMask(modifiers: types.ShortcutModifiers) u32 {
    return @as(u32, if (modifiers.primary or modifiers.command) 0x100 else 0) | @as(u32, if (modifiers.shift) 0x200 else 0) |
        @as(u32, if (modifiers.option) 0x800 else 0) | @as(u32, if (modifiers.control) 0x1000 else 0);
}

fn keyCode(api: Carbon, key: []const u8) ?u32 {
    if (key.len == 1) layout: {
        const source = api.TISCopyCurrentKeyboardLayoutInputSource() orelse break :layout;
        defer api.CFRelease(source);
        const bytes = api.CFDataGetBytePtr(api.TISGetInputSourceProperty(source, api.kTISPropertyUnicodeKeyLayoutData.*) orelse break :layout) orelse break :layout;
        for (0..128) |code| {
            var dead_keys: u32 = 0;
            var chars: [4]u16 = undefined;
            var len: usize = 0;
            if (api.UCKeyTranslate(bytes, @intCast(code), 3, 0, api.LMGetKbdType(), 1, &dead_keys, chars.len, &len, &chars) == 0 and
                len == 1 and chars[0] < 128 and std.ascii.toLower(@intCast(chars[0])) == std.ascii.toLower(key[0])) return @intCast(code);
        }
    }
    return ansiKeyCode(key);
}

fn ansiKeyCode(key: []const u8) ?u32 {
    if (key.len == 1) return @intCast(std.mem.indexOfScalar(u8, "asdfhgzxcv\x00bqweryt123465=97-80]ou[ip\x00lj'k;\\,/nm.\x00\x00`", std.ascii.toLower(key[0])) orelse return null);
    const named = [_]struct { []const u8, u32 }{
        .{ "enter", 0x24 },    .{ "tab", 0x30 },       .{ "space", 0x31 },      .{ "backspace", 0x33 }, .{ "escape", 0x35 },
        .{ "insert", 0x72 },   .{ "home", 0x73 },      .{ "pageup", 0x74 },     .{ "delete", 0x75 },    .{ "end", 0x77 },
        .{ "pagedown", 0x79 }, .{ "arrowleft", 0x7B }, .{ "arrowright", 0x7C }, .{ "arrowdown", 0x7D }, .{ "arrowup", 0x7E },
        .{ "f1", 0x7A },       .{ "f2", 0x78 },        .{ "f3", 0x63 },         .{ "f4", 0x76 },        .{ "f5", 0x60 },
        .{ "f6", 0x61 },       .{ "f7", 0x62 },        .{ "f8", 0x64 },         .{ "f9", 0x65 },        .{ "f10", 0x6D },
        .{ "f11", 0x67 },      .{ "f12", 0x6F },
    };
    for (named) |entry| {
        if (std.ascii.eqlIgnoreCase(key, entry[0])) return entry[1];
    }
    return null;
}

test "portable shortcut keys map to US-layout macOS key codes" {
    for ([_][]const u8{ "a", "j", "z", "0", "9", "=", "-", ",", ".", "/", ";", "'", "[", "]", "\\", "`", "space", "arrowup", "insert", "f12" }, [_]u32{ 0x00, 0x26, 0x06, 0x1D, 0x19, 0x18, 0x1B, 0x2B, 0x2F, 0x2C, 0x29, 0x27, 0x21, 0x1E, 0x2A, 0x32, 0x31, 0x7E, 0x72, 0x6F }) |key, code| {
        try std.testing.expectEqual(@as(?u32, code), ansiKeyCode(key));
    }
}
