//! Copied markup value builder facts and explicit typed native capabilities.
const std = @import("std");
const markup = @import("ui_markup.zig");
const elements = @import("ui_markup_elements.zig");
const scratch = std.heap.page_allocator;
pub const Request = struct {
    inner: elements.Request,
    pub fn init(mode: u8) Request {
        var inner = elements.Request.init(mode);
        inner.bytes.items[0] = 113;
        return .{ .inner = inner };
    }
    pub fn deinit(self: *Request) void {
        self.inner.deinit();
    }
    pub fn word(self: *Request, value: usize) void {
        self.inner.word(value);
    }
    pub fn words(self: *Request, values: []const usize) void {
        self.inner.words(values);
    }
    pub fn blob(self: *Request, value: []const u8) void {
        self.inner.blob(value);
    }
    pub fn names(self: *Request, value: []const []const u8) void {
        self.inner.names(value);
    }
    pub fn node(self: *Request, value: markup.MarkupNode, children: bool) void {
        self.inner.node(value, children);
    }
    pub fn decision(self: *Request, owner: markup.expr.Policy) elements.Record {
        var result = self.program(owner) catch @panic("markup value transport allocation failed");
        defer result.deinit();
        const row = result.next() orelse @panic("missing markup value decision");
        if (result.next() != null) @panic("extra markup value decision");
        return row;
    }
    pub fn program(self: *Request, owner: markup.expr.Policy) error{OutOfMemory}!elements.Program {
        self.inner.bytes.items[3] = 0;
        var sizing: [16]u8 = undefined;
        if (owner(self.inner.bytes.items, &sizing) != sizing.len) @panic("invalid markup value sizing");
        const count = header(&sizing, 0);
        const size = std.math.add(usize, 16, std.math.mul(usize, count, 48) catch return error.OutOfMemory) catch return error.OutOfMemory;
        const out = try scratch.alloc(u8, size);
        errdefer scratch.free(out);
        self.inner.bytes.items[3] = 1;
        if (owner(self.inner.bytes.items, out) != size or header(out, 1) != count) @panic("invalid markup value program");
        return .{ .bytes = out };
    }
};
fn header(bytes: []const u8, phase: u8) usize {
    if (bytes.len < 16 or bytes[0] != 113 or bytes[1] != 1 or bytes[2] != phase) @panic("invalid markup value header");
    for (bytes[3..8]) |byte| if (byte != 0) @panic("invalid markup value reserved byte");
    return elements.number(bytes, 8);
}
pub fn decide(owner: markup.expr.Policy, mode: u8, facts: []const usize) elements.Record {
    var request = Request.init(mode);
    defer request.deinit();
    request.words(facts);
    return request.decision(owner);
}
pub fn kind(value: markup.expr.Value) usize {
    return switch (value) {
        .integer => 0,
        .float => 1,
        .boolean => 2,
        .string => 3,
    };
}
pub fn typeClass(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .float => 1,
        .bool => 2,
        .@"enum" => 3,
        .int => 4,
        .pointer => 5,
        else => 0,
    };
}
pub fn message(code: u8) []const u8 {
    return switch (code) {
        1 => markup.image_binding_element_message,
        2 => markup.image_binding_message,
        3 => markup.media_surface_surface_element_message,
        4 => markup.media_surface_surface_message,
        5 => markup.terminal_pty_element_message,
        6 => markup.terminal_pty_message,
        7 => markup.button_icon_element_message,
        8 => markup.anchor_element_message,
        9 => markup.quiet_hover_element_message,
        10 => markup.anchor_dependent_attr_message,
        11 => markup.anchor_value_message,
        12 => markup.anchor_alignment_value_message,
        13 => markup.anchor_offset_value_message,
        20 => "expected a number",
        21 => "expected an option name",
        22 => "unknown option value",
        23 => "expected a non-negative whole number",
        24 => "expected a whole number",
        25 => "attribute is not settable from markup",
        26 => "expected text",
        27 => "payload type does not match the message",
        28 => "message does not take a payload",
        29 => "message requires a payload",
        30 => "unknown message tag",
        31 => markup.on_drag_payload_message,
        32 => markup.invalid_expression_message,
        33 => markup.arena_scalar_equality_message,
        34 => "binding does not name a field on the loop item",
        35 => "loop items of this type cannot be used as values",
        36 => "slice-valued template args are only usable with for each",
        37 => "template arg values have no fields",
        38 => markup.binding_text_buffer_message,
        39 => "binding does not name a model field",
        40 => "unknown virtual range field",
        41 => "virtual window requires a range field",
        42 => markup.button_icon_message,
        else => @panic("invalid markup value diagnostic"),
    };
}
