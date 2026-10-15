//! Copied markup value builder facts and explicit typed native capabilities.
const std = @import("std");
const markup = @import("ui_markup.zig");
const elements = @import("ui_markup_elements.zig");
const code_model = @import("code.zig");
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
pub fn iconValue(owner: markup.expr.Policy, raw: []const u8, base_message: []const u8) markup.IconValue {
    var request = Request.init(14);
    defer request.deinit();
    request.blob(raw);
    request.names(&markup.known_icon_names);
    const row = request.decision(owner);
    return switch (row.action) {
        72 => if (row.code == 0) .{ .builtin = raw } else if (row.code == 1) .{ .app = raw } else @panic("invalid icon kind"),
        73 => .{ .binding = raw },
        255 => .{ .invalid = if (row.code == 42) base_message else message(row.code) },
        else => @panic("invalid icon capability"),
    };
}
pub fn language(owner: markup.expr.Policy, raw: []const u8) ?code_model.Language {
    var request = Request.init(16);
    defer request.deinit();
    request.blob(raw);
    const fields = @typeInfo(code_model.Language).@"enum".fields;
    request.word(fields.len);
    inline for (fields) |field| request.blob(field.name);
    const row = request.decision(owner);
    if (row.action == 255 and row.code == 45) return null;
    if (row.action != 76 or row.fields[0] >= fields.len) @panic("invalid code language capability");
    inline for (fields, 0..) |field, i| if (row.fields[0] == i) return @enumFromInt(field.value);
    unreachable;
}
pub fn lineNumbers(owner: markup.expr.Policy, raw: []const u8, storage: *[code_model.max_diff_lines]usize) ?[]const usize {
    var request = Request.init(17);
    defer request.deinit();
    request.blob(raw);
    var pieces = request.program(owner) catch @panic("code line transport allocation failed");
    defer pieces.deinit();
    var len: usize = 0;
    while (pieces.next()) |piece| switch (piece.action) {
        77 => {
            const f = piece.fields;
            if (f[0] > f[1] or f[1] > raw.len or f[2] > f[3] or f[3] > raw.len) @panic("invalid code line span");
            const first = std.fmt.parseInt(usize, raw[f[0]..f[1]], 10) catch null;
            // Preserve conversion order and transport no inexact native integers.
            const last = if (first != null) std.fmt.parseInt(usize, raw[f[2]..f[3]], 10) catch null else null;
            var range = Request.init(18);
            defer range.deinit();
            for ([_]?usize{ first, last }) |value| {
                const within = if (value) |number| number <= storage.len else false;
                range.words(&.{ @intFromBool(value != null), @intFromBool(within), if (within) value.? else 0 });
            }
            range.words(&.{ storage.len, len });
            range.words(storage[0..len]);
            var writes = range.program(owner) catch @panic("code line transport allocation failed");
            defer writes.deinit();
            while (writes.next()) |write| switch (write.action) {
                78 => {
                    if (write.fields[0] != len or len >= storage.len or write.fields[1] == 0 or write.fields[1] > storage.len) @panic("invalid code line write");
                    storage[len] = write.fields[1];
                    len += 1;
                },
                255 => return null,
                else => @panic("invalid code line range capability"),
            };
        },
        200 => return storage[0..len],
        255 => return null,
        else => @panic("invalid code line piece capability"),
    };
    @panic("code line program did not publish");
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
        43 => markup.app_icon_shape_message,
        44 => markup.icon_namespace_message,
        45 => markup.code_language_message,
        46 => markup.code_diff_lines_message,
        else => @panic("invalid markup value diagnostic"),
    };
}
