const std = @import("std");
const Client = @import("client.zig").Client;

pub fn main() !void {
    var buffer: [2000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var client = try Client.init(allocator, .{
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

    std.debug.print("Current buffer state: {x:0>2}\n\n", .{buffer});

    while (true) try client.blockingReceive();
}
