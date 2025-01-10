const std = @import("std");
const acc = @import("client.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var client = try acc.Client.init(alloc, .{
        .address = "192.168.1.230",
        .port = 9000,
        .client_name = "test_client",
        .password = "asd",
        .command_password = "",
        .update_ms = 300,
    });

    try client.connect();

    defer {
        client.disconnect();
        client.deinit();
    }

    try client.receive();

    std.time.sleep(std.time.ns_per_s * 1);

    std.debug.print("Receiving is happening in a separate thread\n", .{});

    std.time.sleep(std.time.ns_per_s * 3);
}
