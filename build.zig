const Build = @import("std").Build;

const examples = [_][]const u8{
    "hello",
    "paint",
    "input",
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wcwidth = b.dependency("wcwidth", .{
        .target = target,
        .optimize = optimize,
    }).module("wcwidth");

    const ansi_term = b.dependency("ansi_term", .{
        .target = target,
        .optimize = optimize,
    }).module("ansi_term");

    const module = b.addModule("termbox", .{
        .root_source_file = b.path("src/main.zig"),
    });
    module.addImport("wcwidth", wcwidth);
    module.addImport("ansi_term", ansi_term);

    const main_tests = b.addTest(.{
        .name = "main test suite",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example,
            .root_source_file = b.path("examples/" ++ example ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step(example, "Run the " ++ example ++ " example");
        run_step.dependOn(&run_cmd.step);

        exe.root_module.addImport("termbox", module);
    }
}
