//! A compiled core's global shortcut through the real effects engine and the null platform host.
const std = @import("std");
const sdk = @import("native_sdk");
const core = @import("global_shortcut_core");
const testing = std.testing;
const Host = sdk.TsCoreHost(core);

test "press and release reach the core, a rebind re-registers, and a conflict reaches the app" {
    var host = sdk.platform.NullPlatform.init(.{});
    defer host.deinit();
    var platform = host.platform();
    var fx: Host.Fx = .init(testing.allocator);
    defer fx.deinit();
    fx.bindServices(&platform.services);
    Host.init(&fx);
    Host.drain(&fx);
    try testing.expectEqualStrings("registered", @tagName(Host.model().last));
    try testing.expectEqualStrings("space", host.configuredGlobalShortcuts()[0].binding.shortcut().key);

    try testing.expect(host.pushGlobalShortcut("talk", .pressed));
    Host.drain(&fx);
    try testing.expectEqualStrings("pressed", @tagName(Host.model().last));
    try testing.expect(host.pushGlobalShortcut("talk", .released));
    Host.drain(&fx);
    try testing.expectEqualStrings("released", @tagName(Host.model().last));

    try testing.expect(host.pushGlobalShortcut("talk", .pressed));
    Host.drain(&fx);
    Host.dispatch(&fx, .rebind);
    Host.drain(&fx);
    try testing.expectEqualStrings("registered", @tagName(Host.model().last));
    try testing.expectEqualStrings("f6", host.configuredGlobalShortcuts()[0].binding.shortcut().key);

    host.claimGlobalShortcut("space", .{ .option = true });
    Host.dispatch(&fx, .rebind);
    Host.drain(&fx);
    try testing.expectEqualStrings("conflict", @tagName(Host.model().last));
    try testing.expectEqual(@as(usize, 0), host.configuredGlobalShortcuts().len);
}
