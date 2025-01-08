const std = @import("std");
const Client = @import("client.zig").Client;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var client = try Client.init(alloc, .{
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

    while (true) try client.blockingReceive();
}
