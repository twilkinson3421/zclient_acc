const std = @import("std");

pub fn build(b: *std.Build) void {
    // const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    // const exe = b.addExecutable(.{
    //     .name = "zclient_acc",
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    const network = b.dependency("network", .{});
    const zutil = b.dependency("zutil", .{});
    const zbinutils = b.dependency("zbinutils", .{});

    // exe.root_module.addImport("network", network.module("network"));
    // exe.root_module.addImport("zutil", zutil.module("zutil"));
    // exe.root_module.addImport("binutils", zbinutils.module("binutils"));

    // b.installArtifact(exe);

    // const run_cmd = b.addRunArtifact(exe);
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| run_cmd.addArgs(args);

    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);

    // Lib; all above can be ignored if only using this lib

    const lib = b.addModule("client", .{ .root_source_file = b.path("src/client.zig") });
    lib.addImport("network", network.module("network"));
    lib.addImport("zutil", zutil.module("zutil"));
    lib.addImport("binutils", zbinutils.module("binutils"));
}
