const Builder = @import("std").build.Builder;

const examples = [_][]const u8{
    "hello",
    "paint",
    "input",
};

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("zig-termbox", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const examples_step = b.step("examples", "Install examples");
    inline for (examples) |example| {
        var exe = b.addExecutable(example, "examples/" ++ example ++ ".zig");
        exe.addPackagePath("termbox", "src/main.zig");
        exe.setBuildMode(mode);
        exe.install();
    }
    examples_step.dependOn(b.getInstallStep());
}
