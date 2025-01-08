const std = @import("std");
const builtin = @import("builtin");
const util = @import("teilchen");

pub const Reader = struct {
    position: usize = 0,
    prev_position: ?usize = null,
    endian: std.builtin.Endian = builtin.cpu.arch.endian(),
    buffer: []const u8,

    pub fn read(self: *@This(), comptime T: type) !T {
        const size = @sizeOf(T);
        self.prev_position = self.position;
        defer self.position += size;
        if (self.position + size > self.buffer.len) return error.EndOfStream;
        const target = self.buffer[self.position..][0..size];
        return @bitCast(std.mem.readInt(util.ToInt(T), target, self.endian));
    }

    pub fn readBytes(self: *@This(), size: usize) ![]const u8 {
        self.prev_position = self.position;
        defer self.position += size;
        if (self.position + size > self.buffer.len) return error.EndOfStream;
        return self.buffer[self.position..][0..size];
    }

    pub fn readBytesWithLen(self: *@This(), comptime T: type) ![]const u8 {
        const size = try self.read(T);
        return self.readBytes(size);
    }

    pub fn undo(self: *@This()) void {
        self.position = self.prev_position orelse self.position;
    }
};

pub const Writer = struct {
    endian: std.builtin.Endian = builtin.cpu.arch.endian(),
    allocator: std.mem.Allocator,
    array_list: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return @This(){
            .allocator = allocator,
            .array_list = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.array_list.deinit();
    }

    pub fn write(self: *@This(), comptime T: type, value: T) !void {
        const as_endian = std.mem.nativeTo(util.ToInt(T), @bitCast(value), self.endian);
        const bytes = std.mem.asBytes(&as_endian);
        try self.array_list.appendSlice(bytes[0..@sizeOf(T)]);
    }

    pub fn writeBytes(self: *@This(), bytes: []const u8) !void {
        try self.array_list.appendSlice(bytes);
    }

    pub fn asBytes(self: *@This()) []const u8 {
        return self.array_list.items;
    }
};

pub const WriterKnownSize = struct {
    position: usize = 0,
    endian: std.builtin.Endian = builtin.cpu.arch.endian(),
    allocator: std.mem.Allocator,
    buffer: []u8,

    pub fn init(allocator: std.mem.Allocator, size: usize) !@This() {
        return @This(){
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, size),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.buffer);
    }

    pub fn write(self: *@This(), comptime T: type, value: T) void {
        const size = @sizeOf(T);
        defer self.position += size;
        const as_endian = std.mem.nativeTo(util.ToInt(T), @bitCast(value), self.endian);
        const bytes = std.mem.asBytes(&as_endian);
        std.mem.copyForwards(u8, self.buffer[self.position..][0..size], bytes[0..size]);
    }

    pub fn writeBytes(self: *@This(), bytes: []const u8) void {
        defer self.position += bytes.len;
        std.mem.copyForwards(u8, self.buffer[self.position..][0..bytes.len], bytes);
    }

    pub fn asBytes(self: *@This()) []const u8 {
        return self.buffer;
    }
};
