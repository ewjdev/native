//! Windows keyboard synthesis: SendInput with virtual keys for chords.
const std = @import("std");
const types = @import("../types.zig");
const key_codes = @import("key_codes.zig");

const input_keyboard: u32 = 1;
const keyeventf_extendedkey: u32 = 0x0001;
const keyeventf_keyup: u32 = 0x0002;

const vk_shift: u16 = 0x10;
const vk_control: u16 = 0x11;
const vk_menu: u16 = 0x12;
const vk_lwin: u16 = 0x5B;

const KeyboardInput = extern struct {
    virtual_key: u16,
    scan: u16,
    flags: u32,
    time: u32 = 0,
    extra_info: usize = 0,
};

const Input = extern struct {
    kind: u32 = input_keyboard,
    keyboard: KeyboardInput,
    mouse_input_padding: [8]u8 = @splat(0),
};

extern "user32" fn SendInput(count: u32, inputs: [*]const Input, size: c_int) callconv(.winapi) u32;
extern "user32" fn MapVirtualKeyW(code: u32, map_type: u32) callconv(.winapi) u32;

pub fn sendKeyChord(_: ?*anyopaque, chord: types.KeyChord) anyerror!void {
    const key = key_codes.virtualKey(chord.key()) orelse return error.KeyboardInputFailed;
    const modifiers = modifierKeys(chord.modifiers);
    var inputs: [10]Input = undefined;
    var count: usize = 0;
    for (modifiers.keys[0..modifiers.len]) |modifier| {
        inputs[count] = virtualKeyInput(modifier, false);
        count += 1;
    }
    inputs[count] = virtualKeyInput(key, false);
    inputs[count + 1] = virtualKeyInput(key, true);
    count += 2;
    var index = modifiers.len;
    while (index > 0) : (count += 1) {
        index -= 1;
        inputs[count] = virtualKeyInput(modifiers.keys[index], true);
    }
    const sent: usize = SendInput(@intCast(count), &inputs, @sizeOf(Input));
    if (sent == count) return;
    var cleanup: [5]Input = undefined;
    var cleanup_len: usize = 0;
    if (sent == modifiers.len + 1) {
        cleanup[0] = virtualKeyInput(key, true);
        cleanup_len = 1;
    }
    const released = if (sent > modifiers.len + 2) sent - modifiers.len - 2 else 0;
    var held = @min(sent, modifiers.len) - released;
    while (held > 0) : (cleanup_len += 1) {
        held -= 1;
        cleanup[cleanup_len] = virtualKeyInput(modifiers.keys[held], true);
    }
    if (cleanup_len > 0) _ = SendInput(@intCast(cleanup_len), &cleanup, @sizeOf(Input));
    return error.KeyboardInputBlocked;
}

pub fn access(_: ?*anyopaque, _: bool) anyerror!types.KeyboardInputAccess {
    return .not_required;
}

const ModifierKeys = struct {
    keys: [4]u16 = undefined,
    len: usize = 0,
};

fn modifierKeys(modifiers: types.ShortcutModifiers) ModifierKeys {
    var result: ModifierKeys = .{};
    for ([_]struct { bool, u16 }{
        .{ modifiers.primary or modifiers.control, vk_control },
        .{ modifiers.option, vk_menu },
        .{ modifiers.shift, vk_shift },
        .{ modifiers.command, vk_lwin },
    }) |entry| {
        if (!entry[0]) continue;
        result.keys[result.len] = entry[1];
        result.len += 1;
    }
    return result;
}

fn virtualKeyInput(vk: u16, key_up: bool) Input {
    const extended = switch (vk) {
        0x21...0x28, 0x2D, 0x2E, vk_lwin => true,
        else => false,
    };
    return .{ .keyboard = .{
        .virtual_key = vk,
        .scan = @truncate(MapVirtualKeyW(vk, 0)),
        .flags = (if (key_up) keyeventf_keyup else 0) | (if (extended) keyeventf_extendedkey else 0),
    } };
}

test "input records match the Win32 INPUT layout" {
    try std.testing.expectEqual(@as(usize, if (@sizeOf(usize) == 8) 40 else 28), @sizeOf(Input));
    try std.testing.expectEqual(@as(usize, @sizeOf(usize)), @offsetOf(Input, "keyboard"));
}
