const std = @import("std");
const network = @import("network");
const coerce = @import("coerce.zig");
const parse = @import("parse.zig");
const binutils = @import("binutils");
const enums = @import("enums.zig");
const msg = @import("msg.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    params: Params,
    socket: network.Socket,

    connected: bool = false,
    connection_id: ?i32 = null,
    car_map: std.AutoHashMap(isize, msg.Car),
    pointers: Pointers,
    thread: std.Thread = undefined,
    should_stop: bool = false,

    pub const Params = struct {
        address: []const u8 = "localhost",
        port: u16 = 9000,
        client_name: []const u8,
        password: []const u8,
        command_password: []const u8,
        update_ms: u16,
    };

    pub const Pointers = struct {
        registration_result: *msg.RegistrationResult,
        realtime_update: *msg.RealtimeUpdate,
        realtime_car_update: *msg.RealtimeCarUpdate,
        entry_list: *[]u16,
        track_data: *msg.TrackData,
        entry_list_car: *msg.EntryListCar,
        broadcasting_event: *msg.BroadcastingEvent,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        params: Params,
    ) !@This() {
        try network.init();

        return @This(){
            .allocator = allocator,
            .params = params,
            .socket = try network.connectToHost(allocator, params.address, params.port, .udp),
            .car_map = std.AutoHashMap(isize, msg.Car).init(allocator),
            .pointers = Pointers{
                .registration_result = try allocator.create(msg.RegistrationResult),
                .realtime_update = try allocator.create(msg.RealtimeUpdate),
                .realtime_car_update = try allocator.create(msg.RealtimeCarUpdate),
                .entry_list = try allocator.create([]u16),
                .track_data = try allocator.create(msg.TrackData),
                .entry_list_car = try allocator.create(msg.EntryListCar),
                .broadcasting_event = try allocator.create(msg.BroadcastingEvent),
            },
        };
    }

    pub fn deinit(self: *@This()) void {
        self.disconnect();
        self.socket.close();
        network.deinit();
        self.car_map.deinit();
        {
            self.allocator.destroy(self.pointers.registration_result);
            self.allocator.destroy(self.pointers.realtime_update);
            self.allocator.destroy(self.pointers.realtime_car_update);
            self.allocator.destroy(self.pointers.entry_list);
            self.allocator.destroy(self.pointers.track_data);
            self.allocator.destroy(self.pointers.entry_list_car);
            self.allocator.destroy(self.pointers.broadcasting_event);
        }
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
        self.stopReceive();
        self.connected = false;
    }

    pub fn receive(self: *@This()) !void {
        self.thread = try std.Thread.spawn(.{}, receiveThread, .{self});
    }

    pub fn stopReceive(self: *@This()) void {
        self.should_stop = true;
        self.thread.join();
    }

    pub fn receiveThread(self: *@This()) !void {
        while (!self.should_stop) try self.blockingReceive();
    }

    fn blockingReceive(self: *@This()) !void {
        var buf: [1024]u8 = undefined;
        const len = try self.socket.receive(&buf);
        var reader = binutils.Reader{ .buffer = buf[0..len], .endian = .little };
        const msg_type = try std.meta.intToEnum(enums.MessageType, try reader.read(u8));
        switch (msg_type) {
            .registration_result => {
                const registration_result = try parse.parseRegistrationResult(&reader);
                self.connection_id = registration_result.connection_id;
                if (registration_result.success) self.connected = true;
                std.debug.print("Registration result: {any}\n\n", .{registration_result});
                self.pointers.registration_result.* = registration_result;
                if (registration_result.read_only) return;
                try self.requestTrackData();
                try self.requestEntryList();
            },
            .realtime_update => {
                const realtime_update = try parse.parseRealtimeUpdate(&reader);
                std.debug.print("Realtime update: {any}\n\n", .{realtime_update});
                self.pointers.realtime_update.* = realtime_update;
            },
            .realtime_car_update => {
                const realtime_car_update = try parse.parseRealTimeCarUpdate(&reader);
                std.debug.print("Realtime car update: {any}\n\n", .{realtime_car_update});
                self.pointers.realtime_car_update.* = realtime_car_update;
            },
            .entry_list => {
                self.car_map.clearRetainingCapacity();
                const entry_list = try parse.parseEntryList(self.allocator, &reader);
                for (entry_list) |id| self.car_map.putAssumeCapacity(id, msg.Car{});
                std.debug.print("Entry list: {d}\n\n", .{entry_list});
                self.pointers.entry_list.* = entry_list;
            },
            .track_data => {
                const track_data = try parse.parseTrackData(self.allocator, &reader);
                self.connection_id = track_data.connection_id;
                std.debug.print("Track data: {any}\n\n", .{track_data});
                self.pointers.track_data.* = track_data;
            },
            .entry_list_car => {
                const entry_list_car = try parse.parseEntryListCar(self.allocator, &reader, &self.car_map);
                std.debug.print("Entry list car: {any}\n\n", .{entry_list_car});
                self.pointers.entry_list_car.* = entry_list_car;
            },
            .broadcasting_event => {
                const broadcasting_event = try parse.parseBroadcastingEvent(&reader, &self.car_map);
                std.debug.print("Broadcasting event: {any}\n\n", .{broadcasting_event});
                self.pointers.broadcasting_event.* = broadcasting_event;
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
