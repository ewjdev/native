const std = @import("std");
const effects_mod = @import("effects.zig");
const platform = @import("../platform/root.zig");

const testing = std.testing;

const Msg = union(enum) { hotkey: effects_mod.EffectGlobalShortcutEvent };
const Fx = effects_mod.Effects(Msg);
const on_event = Fx.globalShortcutMsg(.hotkey);

fn take(fx: *Fx, kind: effects_mod.EffectGlobalShortcutEventKind, id: []const u8) !void {
    const msg = fx.takeMsg() orelse return error.TestExpectedMsg;
    try testing.expectEqual(kind, msg.hotkey.kind);
    try testing.expectEqualStrings(id, msg.hotkey.shortcut.id);
}

const dictate: platform.Shortcut = .{ .id = "dictate", .key = "space", .modifiers = .{ .option = true } };
const palette: platform.Shortcut = .{ .id = "palette", .key = "p", .modifiers = .{ .primary = true, .shift = true } };

test "invalid, duplicate, and same-combination bindings are reported" {
    var fx = Fx.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    fx.setGlobalShortcuts(.{ .key = 11, .shortcuts = &.{
        .{ .id = "bare", .key = "k" },
        .{ .id = "bogus", .key = "f13", .modifiers = .{ .shift = true } },
        dictate,
        .{ .id = "dictate", .key = "f5" },
        .{ .id = "twin", .key = "SPACE", .modifiers = .{ .option = true } },
    }, .on_event = on_event });
    try take(&fx, .rejected, "bare");
    try take(&fx, .rejected, "bogus");
    try take(&fx, .rejected, "dictate");
    try take(&fx, .registered, "dictate");
    try take(&fx, .conflict, "twin");
}

test "a set past the limit rejects the excess bindings" {
    var fx = Fx.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    const letters = "abcdefghijklmnopq";
    var shortcuts: [letters.len]platform.Shortcut = undefined;
    for (&shortcuts, 0..) |*shortcut, index| shortcut.* = .{ .id = letters[index..][0..1], .key = letters[index..][0..1], .modifiers = .{ .shift = true } };
    fx.setGlobalShortcuts(.{ .key = 12, .shortcuts = &shortcuts, .on_event = on_event });
    try take(&fx, .rejected, "q");
    for (letters[0..platform.max_global_shortcuts], 0..) |_, index| try take(&fx, .registered, letters[index..][0..1]);
}

test "reconciling reports only new, changed, and failing bindings" {
    var fx = Fx.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    fx.setGlobalShortcuts(.{ .key = 3, .shortcuts = &.{ dictate, palette }, .on_event = on_event });
    try take(&fx, .registered, "dictate");
    try take(&fx, .registered, "palette");
    fx.setGlobalShortcuts(.{ .key = 3, .shortcuts = &.{ dictate, palette }, .on_event = on_event });
    try testing.expectEqual(@as(?Msg, null), fx.takeMsg());
    fx.setGlobalShortcuts(.{ .key = 3, .shortcuts = &.{ dictate, .{ .id = "palette", .key = "k", .modifiers = .{ .primary = true } } }, .on_event = on_event });
    try take(&fx, .registered, "palette");
    try testing.expectEqual(@as(?Msg, null), fx.takeMsg());
}

test "clearing a held shortcut reports its release before the stopped terminal" {
    var host = platform.NullPlatform.init(.{});
    defer host.deinit();
    var host_platform = host.platform();
    var fx = Fx.init(testing.allocator);
    defer fx.deinit();
    fx.bindServices(&host_platform.services);
    fx.setGlobalShortcuts(.{ .key = 21, .shortcuts = &.{dictate}, .on_event = on_event });
    try take(&fx, .registered, "dictate");
    try testing.expect(host.pushGlobalShortcut("dictate", .pressed));
    fx.clearGlobalShortcuts(21);
    try take(&fx, .pressed, "dictate");
    try take(&fx, .released, "dictate");
    try take(&fx, .stopped, "");
    try testing.expectEqual(@as(usize, 0), host.configuredGlobalShortcuts().len);
}

test "a host without the service reports every binding unsupported" {
    var host = platform.NullPlatform.init(.{});
    defer host.deinit();
    host.global_shortcuts = false;
    var host_platform = host.platform();
    var fx = Fx.init(testing.allocator);
    defer fx.deinit();
    fx.bindServices(&host_platform.services);
    fx.setGlobalShortcuts(.{ .key = 5, .shortcuts = &.{ dictate, palette }, .on_event = on_event });
    try take(&fx, .unsupported, "dictate");
    try take(&fx, .unsupported, "palette");
}

test "session replay never touches the host registration" {
    var host = platform.NullPlatform.init(.{});
    defer host.deinit();
    var host_platform = host.platform();
    var fx = Fx.init(testing.allocator);
    defer fx.deinit();
    fx.bindServices(&host_platform.services);
    fx.armReplay();
    fx.setGlobalShortcuts(.{ .key = 13, .shortcuts = &.{dictate}, .on_event = on_event });
    fx.clearGlobalShortcuts(13);
    try testing.expectEqual(@as(usize, 0), host.global_shortcut_configure_count);
}
