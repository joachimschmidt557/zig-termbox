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

    inline for (examples) |example| {
        var exe = b.addExecutable(example, "examples/" ++ example ++ ".zig");
        exe.addPackagePath("termbox", "src/main.zig");
        exe.setBuildMode(mode);

        const run_cmd = exe.run();
        const run_step = b.step(example, "Run the " ++ example ++ " example");
        run_step.dependOn(&run_cmd.step);
    }
}
