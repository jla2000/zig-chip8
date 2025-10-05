const std = @import("std");

pub fn build(b: *std.Build) void {
    const windows = b.option(bool, "windows", "Cross compile for windows") orelse false;

    const target = b.resolveTargetQuery(.{
        .os_tag = if (windows) .windows else null,
    });

    const exe = b.addExecutable(.{
        .name = "zig-chip8",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
        }),
    });

    if (windows) {
        // When cross compiling for windows, build raylib from source
        const raylib = b.dependency("raylib", .{
            .target = target,
        });
        exe.linkLibrary(raylib.artifact("raylib"));
    } else {
        // When building for linux, raylib is provided by nix
        exe.linkSystemLibrary("raylib");
        exe.linkLibC();
    }

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);

    if (b.args) |args| {
        run_exe.addArgs(args);
    }
}
