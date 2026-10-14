const std = @import("std");
const sdk = @import("native_sdk");
const core = @import("virtual_fixed_core");
const decoder = @import("virtual_fixed_decoder");
test "fixed-only compiled virtual view emits usable mirror capabilities without numeric helpers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const model = core.initialModel();
    defer core.rt.frameReset();
    try std.testing.expectEqual(@as(?u32, null), core.Model.virtualExtentHelper("absent"));
    try std.testing.expectEqual(@as(?u32, null), core.RuntimeModel.virtualExtentHelper("absent"));
    // Force Zig to analyze the complete callback, even though fixed lists
    // never invoke it. It must trap for invalid identities, not fail to compile.
    std.mem.doNotOptimizeAway(&core.Model.virtualExtentEstimate);
    std.mem.doNotOptimizeAway(&core.RuntimeModel.virtualExtentEstimate);
    var ui = sdk.canvas.Ui(core.Msg).init(arena.allocator());
    const tree = try ui.finalize(decoder.build(&ui, model));
    try std.testing.expect(tree.root.children.len > 0);
    const records = ui.virtualWindows();
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqual(@as(usize, 100), records[0].item_count);
    try std.testing.expect(!records[0].variable);
    var nodes: [1024]sdk.canvas.WidgetLayoutNode = undefined;
    const layout = try sdk.canvas.layoutWidgetTree(tree.root, .init(0, 0, 400, 300), &nodes);
    try std.testing.expect(layout.findById(records[0].id) != null);
}
