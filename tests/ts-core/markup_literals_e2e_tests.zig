const std = @import("std");
const sdk = @import("native_sdk");
const core = @import("surface_fixture_core");
const c = sdk.canvas;
const m = c.ui_markup;
fn exact(a: anytype, b: @TypeOf(a)) anyerror!void {
    const T = @TypeOf(a);
    switch (@typeInfo(T)) {
        .@"struct" => |info| inline for (info.fields) |field| try exact(@field(a, field.name), @field(b, field.name)),
        .optional => {
            try std.testing.expectEqual(a != null, b != null);
            if (a) |value| try exact(value, b.?);
        },
        .pointer => |info| if (info.size == .slice) {
            try std.testing.expectEqual(a.len, b.len);
            for (a, b) |l, r| try exact(l, r);
        } else if (info.size == .one and (@typeInfo(info.child) == .@"struct" or @typeInfo(info.child) == .@"union" or info.child == bool)) try exact(a.*, b.*) else try std.testing.expectEqual(a, b),
        .array => for (a, b) |l, r| try exact(l, r),
        .@"union" => {
            try std.testing.expectEqual(std.meta.activeTag(a), std.meta.activeTag(b));
            switch (a) {
                inline else => |value, tag| try exact(value, @field(b, @tagName(tag))),
            }
        },
        else => try @import("surface_layout_e2e_tests.zig").expectComplete(a, b),
    }
}

var operations: [33]usize = @splat(0);
fn observed(input: []const u8, output: []u8) usize {
    if (input[0] == 113) {
        operations[input[2]] += 1;
    }
    const n = core.nativeWindowPolicy(input, output);
    core.rt.frameReset();
    return n;
}
var trace: [2048]i64 = undefined;
var trace_len: usize = 0;
fn event(value: i64) void {
    trace[trace_len] = value;
    trace_len += 1;
}
const Row = struct { id: i64, title: []const u8 };
const Model = struct {
    body: []const u8 = "# Title\n\nText [link](https://example.com)\n\n<details><summary>Summary</summary>Body</details>\n\n![alt](sample)",
    code: []const u8 = "const value = 42;\nreturn value;\n",
    diff: []const u8 = "1-2",
    flags: []const bool = &.{ true, false },
    images: []const c.markdown.ResolvedImage = &.{.{ .source = "sample", .image = 18446744073709551615, .width = 20, .height = 10 }},
    levels: []const f32 = &.{ 1, 3, 2 },
    labels: []const []const u8 = &.{ "One", "Two", "Three" },
    rows_data: []const Row = &.{ .{ .id = -9223372036854775808, .title = "First" }, .{ .id = 9223372036854775807, .title = "Second" } },
    title: []const u8 = "Borrowed\x00\xff",
    yes: bool = true,
    scale: f64 = 0.5,
    pub fn first(_: *const Model) f64 {
        event(1);
        return 1.5;
    }
    pub fn second(_: *const Model) f64 {
        event(2);
        return 2.5;
    }
    pub fn count(_: *const Model) i64 {
        event(3);
        return 2;
    }
    pub fn source(self: *const Model) []const u8 {
        event(4);
        return self.body;
    }
};
const Msg = union(enum) { tick, pick: i64, input: c.TextInputEvent, link: []const u8, details: usize };
const Ui = c.Ui(Msg);
const View = c.MarkupView(Model, Msg);
const unlimited = std.math.maxInt(usize);
var last_resizes: usize = 0;
fn sink(_: *anyopaque, _: u64, _: *const c.ui_provenance.NodeSource, _: []const c.ui_provenance.Key, _: bool) void {}
fn compare(doc: m.MarkupDocument, model: Model, failure: usize, resize: usize) !usize {
    var aa = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer aa.deinit();
    var ab = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ab.deinit();
    var fa = std.testing.FailingAllocator.init(aa.allocator(), .{ .fail_index = failure, .resize_fail_index = resize });
    var fb = std.testing.FailingAllocator.init(ab.allocator(), .{ .fail_index = failure, .resize_fail_index = resize });
    var ui_a = Ui.init(fa.allocator());
    var ui_b = Ui.init(fb.allocator());
    ui_b.expression_policy = observed;
    var context: u8 = 0;
    const provenance: c.ui_provenance.Sink = .{ .context = &context, .record_fn = sink };
    ui_a.provenance_sink = provenance;
    ui_b.provenance_sink = provenance;
    var a = View.fromDocument(doc);
    var b = View.fromDocument(doc);
    trace_len = 0;
    const left = View.ConstructionTest.run(&a, &ui_a, &model, 0, 0, 0, null);
    const before = trace;
    const length = trace_len;
    trace_len = 0;
    const right = View.ConstructionTest.run(&b, &ui_b, &model, 0, 0, 0, null);
    var stage: []const u8 = "callbacks";
    errdefer std.debug.print("failure={d} resize={d} comparison={s}\n", .{ failure, resize, stage });
    try exact(before[0..length], trace[0..trace_len]);
    stage = "failure";
    try exact(left.failure, right.failure);
    stage = "node";
    try exact(left.node, right.node);
    stage = "scope.entries";
    try exact(left.scope.entries, right.scope.entries);
    stage = "scope.len";
    try exact(left.scope.len, right.scope.len);
    stage = "scope.floor";
    try exact(left.scope.floor, right.scope.floor);
    stage = "scope.use_depth";
    try exact(left.scope.use_depth, right.scope.use_depth);
    stage = "scope.template_ctx";
    try exact(left.scope.template_ctx, right.scope.template_ctx);
    stage = "scope.source_chain";
    try exact(left.scope.source_chain, right.scope.source_chain);
    if (left.node) |node| {
        const lt = ui_a.finalize(node);
        const rt = ui_b.finalize(right.node.?);
        if (lt) |tree| try exact(tree, try rt) else |err| try std.testing.expectError(err, rt);
    }
    stage = "effects and allocator";
    try exact(ui_a.video_declaration, ui_b.video_declaration);
    try exact(ui_a.virtualWindows(), ui_b.virtualWindows());
    try exact(a.diagnostic, b.diagnostic);
    try exact(ui_a.failed, ui_b.failed);
    try exact(fa.alloc_index, fb.alloc_index);
    try exact(fa.resize_index, fb.resize_index);
    last_resizes = fa.resize_index;
    return fa.alloc_index;
}
fn document(arena: std.mem.Allocator, source: []const u8, typed: bool) !m.MarkupDocument {
    var parser = m.Parser.init(arena, source);
    const doc = try parser.parse();
    return if (typed) m.canonicalize(arena, doc) else doc;
}
fn check(source: []const u8, model: Model, failures: bool) !void {
    errdefer std.debug.print("literal and capture parity failed: {s}\n", .{source});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_]bool{ false, true }) |typed| {
        const doc = try document(arena.allocator(), source, typed);
        const count = try compare(doc, model, unlimited, unlimited);
        const resizes = last_resizes;
        if (failures) {
            for (0..count + 1) |index| _ = try compare(doc, model, index, unlimited);
            for (0..resizes + 1) |index| _ = try compare(doc, model, unlimited, index);
        }
    }
}
fn literalEqual(raw: []const u8, attribute: ?[]const u8) !void {
    const expected = if (attribute) |name| View.LiteralTest.referenceAttribute(raw, name) else View.LiteralTest.reference(raw);
    const actual = View.LiteralTest.literal(observed, raw, attribute);
    try exact(expected, actual);
    if (expected == .float) try std.testing.expectEqual(@as(u32, @bitCast(expected.float)), @as(u32, @bitCast(actual.float)));
    if (expected == .string) try std.testing.expectEqual(@intFromPtr(raw.ptr), @intFromPtr(actual.string.ptr));
}
test "compiled markup literals preserve exact native integers floats schema precedence and borrowed bytes" {
    _ = core.initialModel();
    operations = @splat(0);
    const values = [_][]const u8{ "true", "false", "TRUE", "False", " true", "false ", "", " ", "0", "-0", "+0", "01", "1_000", "0x10", "9007199254740993", "-9007199254740993", "9223372036854775807", "-9223372036854775808", "9223372036854775808", "-9223372036854775809", "1.000000059604644775390625", "1.000000178813934326171875", "3.4028234663852886e38", "1e40", "-1e40", "1e-50", "-1e-50", "0.0", "-0.0", "nan", "NaN", "-nan", "inf", "-inf", "Infinity", "1e", "1.2.3", "\x00", "\xff", "12\x00\xff", "caf\xc3\xa9" };
    for (values) |raw| {
        try literalEqual(raw, null);
        for (m.schema.attrs) |info| try literalEqual(raw, info.name);
        for ([_][]const u8{ "unknown", "Text", "text\x00", "\xff", "" }) |name| try literalEqual(raw, name);
    }
    // Arbitrary malformed bytes are data, never decoded through replacement text.
    var bytes: [2]u8 = undefined;
    for (0..256) |byte| {
        bytes = .{ @intCast(byte), 0xff };
        try literalEqual(&bytes, null);
        try literalEqual(&bytes, "text");
    }
    try std.testing.expect(operations[31] > 0);
}
test "compiled markup literals preserve defaults attribute values and complete eager failure effects" {
    _ = core.initialModel();
    for ([_][]const u8{
        "<column><text text=\"true\"/><input placeholder=\"123\" text=\"false\"/><button label=\"9223372036854775807\" on-press=\"tick\">Value</button><slider value=\"1.000000059604644775390625\" width=\"123\"/></column>",
        "<template name=\"t\" args=\"a=true b=false c=9223372036854775807 d=-9223372036854775808 e=9007199254740993 f=1.5 g=plain h=\"><column><text>{a} {b} {c} {d} {e} {f} {g} [{h}]</text><if test=\"{a}\"><text>visible</text></if></column></template><use template=\"t\"/>",
        "<template name=\"t\" args=\"title=true value=1.5\"><column><text>{title} {value}</text><slot/></column></template><column><use template=\"t\"/><use template=\"t\" title=\"false\" value=\"9223372036854775807\"><text>{source}</text></use></column>",
        "<column><video src=\"synthetic.mp4\"/><input placeholder=\"123\" width=\"{first}\" text=\"true\"/><code source=\"{count}\"/></column>",
        "<template name=\"t\" args=\"a=9223372036854775807 b\"><text>{a}</text></template><use template=\"t\" b=\"{missing}\"/>",
        "<column><text text=\"{first == second}\"/><button disabled=\"{first + second}\">Eager</button></column>",
    }) |source| try check(source, .{}, true);
}
test "compiled markup literals preserve raw and contradictory cached literal channels" {
    _ = core.initialModel();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cached = [_]m.TypedAttrValue{ .{ .literal = "true" }, .{ .literal = "9007199254740993" }, .{ .literal = "-0.0" }, .{ .literal = "\x00\xff" }, .{ .binding = "source" }, .{ .equals = .{ .left = "first", .right = "second" } }, .{ .expression = .{ .inner = "first + second" } }, .invalid };
    for ([_][]const u8{ "<input text=\"false\" placeholder=\"123\" width=\"15\"/>", "<button disabled=\"false\" label=\"true\" on-press=\"tick\">Test</button>" }) |source| for (cached) |value| {
        const doc = try document(arena.allocator(), source, false);
        for (0..doc.root.?.attrs.len) |index| {
            const attrs = try arena.allocator().dupe(m.MarkupAttr, doc.root.?.attrs);
            const cache = try arena.allocator().create(m.TypedAttrValue);
            cache.* = value;
            attrs[index].typed = cache;
            var changed = doc;
            changed.root.?.attrs = attrs;
            const count = try compare(changed, .{}, unlimited, unlimited);
            const resizes = last_resizes;
            for (0..count + 1) |failure| _ = try compare(changed, .{}, failure, unlimited);
            for (0..resizes + 1) |failure| _ = try compare(changed, .{}, unlimited, failure);
        }
    };
}
test "compiled markup literals preserve innermost empty captures lexical floors and full borrowed capture metadata" {
    _ = core.initialModel();
    const model: Model = .{};
    const nodes = [_]m.MarkupNode{.{ .kind = .element, .name = "step", .text = "borrowed" }};
    const chain = [_]c.ui_provenance.UseSite{.{ .src_path = "synthetic.native", .line = 3, .column = 2 }};
    var captures: [8]?View.LiteralTest.Capture = undefined;
    for (0..captures.len + 1) |length| for (0..@as(usize, 1) << @intCast(length)) |mask| {
        for (captures[0..length], 0..) |*entry, i| entry.* = if (mask & (@as(usize, 1) << @intCast(i)) != 0) .{ .nodes = if (i % 2 == 0) &nodes else &.{}, .len = i, .floor = i / 2, .template_ctx = i, .chain = &chain } else null;
        for (0..length + 1) |floor| {
            const expected = View.LiteralTest.capture(null, &model, captures[0..length], floor);
            const actual = View.LiteralTest.capture(observed, &model, captures[0..length], floor);
            try exact(expected, actual);
            if (expected) |value| {
                try std.testing.expectEqual(@intFromPtr(value.nodes.ptr), @intFromPtr(actual.?.nodes.ptr));
                try std.testing.expectEqual(@intFromPtr(value.chain.ptr), @intFromPtr(actual.?.chain.ptr));
            }
        }
    };
    try std.testing.expect(operations[32] > 0);
}
test "compiled markup literals preserve stepper nested captures provenance restoration and allocation order" {
    _ = core.initialModel();
    for ([_][]const u8{
        "<template name=\"steps\" args=\"title=true\"><stepper active=\"1\"><slot/></stepper></template><column><for each=\"rows_data\" as=\"row\"><use template=\"steps\"><step>{row.title} {source}</step><step>{count}</step></use></for></column>",
        "<template name=\"steps\"><stepper><slot/></stepper></template><use template=\"steps\"/>",
        "<template name=\"inner\"><stepper><slot/></stepper></template><template name=\"outer\"><column><use template=\"inner\"/><slot/></column></template><use template=\"outer\"><step>{second}</step></use>",
        "<template name=\"inner\"><stepper><slot/></stepper></template><template name=\"outer\" args=\"title=Outer\"><column><use template=\"inner\"><step>{title}</step><step>{missing}</step></use><slot/></column></template><use template=\"outer\"><text>{source}</text></use>",
        "<stepper><slot/></stepper>",
        "<stepper><slot/><step>{second}</step></stepper>",
        "<template name=\"steps\"><stepper><slot/></stepper></template><column><video src=\"synthetic.mp4\"/><use template=\"steps\"><step>{source}</step><step>{missing}</step></use></column>",
    }) |source| try check(source, .{}, true);
}
