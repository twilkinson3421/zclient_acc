const std = @import("std");
const network = @import("network");
const coerce = @import("coerce.zig");
const parse = @import("parse.zig");
const binutils = @import("binutils/root.zig");
const enums = @import("enums.zig");
const msg = @import("msg.zig");

pub const ClientParams = struct {
    address: []const u8 = "localhost",
    port: u16 = 9000,
    client_name: []const u8,
    password: []const u8,
    command_password: []const u8,
    update_ms: u16,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    params: ClientParams,
    socket: network.Socket,

    connected: bool = false,
    connection_id: ?i32 = null,
    car_map: std.AutoHashMap(isize, msg.Car),

    pub fn init(allocator: std.mem.Allocator, params: ClientParams) !@This() {
        try network.init();
        return @This(){
            .allocator = allocator,
            .params = params,
            .socket = try network.connectToHost(allocator, params.address, params.port, .udp),
            .car_map = std.AutoHashMap(isize, msg.Car).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        if (self.connected) self.disconnect();
        self.socket.close();
        network.deinit();
    }

    fn send(self: *@This(), data: []const u8) !void {
        std.debug.print("Sending bytes: {x:0>2}\n\n", .{data});
        _ = try self.socket.send(data);
    }

    pub fn connect(self: *@This()) !void {
        if (self.connected) return;
        var writer = try coerce.connect(
            self.allocator,
            self.params.client_name,
            self.params.password,
            self.params.command_password,
            self.params.update_ms,
        );
        defer writer.deinit();
        try self.send(writer.buffer);
    }

    pub fn disconnect(self: *@This()) void {
        if (!self.connected) return;
        self.send(coerce.disconnect()) catch {};
        self.connected = false;
        std.debug.print("Connection terminated\n", .{});
    }

    pub fn blockingReceive(self: *@This()) !void {
        var buf: [1024]u8 = undefined;
        _ = try self.socket.reader().readAll(&buf);
        var reader = binutils.Reader{ .buffer = &buf, .endian = .little };
        const msg_type = try std.meta.intToEnum(enums.MessageType, try reader.read(u8));
        switch (msg_type) {
            .registration_result => {
                const registration_result = try parse.parseRegistrationResult(&reader);
                self.connection_id = registration_result.connection_id;
                if (registration_result.success) self.connected = true;
                std.debug.print("Registration result: {any}\n\n", .{registration_result});
                if (registration_result.read_only) return;
                try self.requestTrackData();
                try self.requestEntryList();
            },
            .realtime_update => {
                const realtime_update = try parse.parseRealtimeUpdate(&reader);
                std.debug.print("Realtime update: {any}\n\n", .{realtime_update});
            },
            .realtime_car_update => {
                const realtime_car_update = try parse.parseRealTimeCarUpdate(&reader);
                std.debug.print("Realtime car update: {any}\n\n", .{realtime_car_update});
            },
            .entry_list => {
                self.car_map.clearRetainingCapacity();
                const entry_list = try parse.parseEntryList(self.allocator, &reader);
                for (entry_list) |id| self.car_map.putAssumeCapacity(id, msg.Car{});
                std.debug.print("Entry list: {d}\n\n", .{entry_list});
            },
            .track_data => {
                const track_data = try parse.parseTrackData(self.allocator, &reader);
                self.connection_id = track_data.connection_id;
                std.debug.print("Track data: {any}\n\n", .{track_data});
            },
            .entry_list_car => {
                const entry_list_car = try parse.parseEntryListCar(self.allocator, &reader, &self.car_map);
                std.debug.print("Entry list car: {any}\n\n", .{entry_list_car});
            },
            .broadcasting_event => {
                const broadcasting_event = try parse.parseBroadcastingEvent(&reader, &self.car_map);
                std.debug.print("Broadcasting event: {any}\n\n", .{broadcasting_event});
            },
        }
    }

    fn requestEntryList(self: *@This()) !void {
        if (self.connection_id == null) return error.Noconnection_id;
        var writer = try coerce.requestEntryList(self.allocator, self.connection_id.?);
        defer writer.deinit();
        try self.send(writer.buffer);
    }

    fn requestTrackData(self: *@This()) !void {
        if (self.connection_id == null) return error.Noconnection_id;
        var writer = try coerce.requestTrackData(self.allocator, self.connection_id.?);
        defer writer.deinit();
        try self.send(writer.buffer);
    }
};
