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

    const termbox = b.addModule("termbox", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    termbox.addImport("wcwidth", wcwidth);
    termbox.addImport("ansi_term", ansi_term);

    const main_tests = b.addTest(.{
        .name = "termbox",
        .root_module = termbox,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = main_tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);

    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example,
            .root_source_file = b.path("examples/" ++ example ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step("example-" ++ example, "Run the " ++ example ++ " example");
        run_step.dependOn(&run_cmd.step);

        exe.root_module.addImport("termbox", termbox);
    }
}
