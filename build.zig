const Builder = @import("std").build.Builder;

const examples = [_][]const u8{
    "hello",
    "paint",
    "input",
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("termbox", .{
        .source_file = .{ .path = "src/main.zig" },
    });

    const main_tests = b.addTest(.{
        .name = "main test suite",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example,
            .root_source_file = .{ .path = "examples/" ++ example ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });

        const run_cmd = exe.run();
        const run_step = b.step(example, "Run the " ++ example ++ " example");
        run_step.dependOn(&run_cmd.step);

        exe.addModule("termbox", module);
    }
}
