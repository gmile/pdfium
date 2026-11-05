const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const erts = b.option([]const u8, "erts", "OTP include directory") orelse
        b.graph.environ_map.get("ERTS_INCLUDE_DIR") orelse @panic("pass -Derts or set ERTS_INCLUDE_DIR");
    const os = target.result.os.tag;
    const arch = target.result.cpu.arch;
    const abi = target.result.abi;
    const triple = b.fmt("{s}-{s}-{s}", .{
        @tagName(arch),
        if (os == .macos) "apple" else "linux",
        if (os == .macos) "darwin" else if (abi.isMusl()) "musl" else "gnu",
    });
    const pdfium = b.lazyDependency(b.fmt("pdfium_{s}", .{triple}), .{}) orelse return;
    const fine = b.lazyDependency("fine", .{}) orelse return;
    const library = if (os == .macos) "libpdfium.dylib" else "libpdfium.so";

    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .strip = true,
    });
    module.addCSourceFile(.{
        .file = b.path("c_src/pdfium_nif.cpp"),
        .flags = &.{ "-std=c++17", "-fvisibility=hidden", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter" },
    });
    module.addIncludePath(.{ .cwd_relative = erts });
    module.addIncludePath(pdfium.path("include"));
    module.addIncludePath(fine.path("c_include"));
    if (os == .macos) {
        const rename = b.addRunArtifact(b.addExecutable(.{
            .name = "dylib_id",
            .root_module = b.createModule(.{ .root_source_file = b.path("build/dylib_id.zig"), .target = b.graph.host }),
        }));
        rename.addFileArg(pdfium.path("lib/libpdfium.dylib"));
        module.addObjectFile(rename.addOutputFileArg("libpdfium.dylib"));
        rename.addArg("@rpath/libpdfium.dylib");
    } else {
        module.addLibraryPath(pdfium.path("lib"));
        module.linkSystemLibrary("pdfium", .{});
    }
    module.addRPath(.{ .cwd_relative = if (os == .macos) "@loader_path" else "$ORIGIN" });

    const nif = b.addLibrary(.{ .name = "pdfium_nif", .linkage = .dynamic, .root_module = module });
    if (os == .macos) {
        nif.linker_allow_shlib_undefined = true;
        nif.install_name = "@rpath/pdfium_nif.so";
    }

    const install = b.addInstallArtifact(nif, .{ .dest_dir = .{ .override = .{ .custom = "." } }, .dest_sub_path = "pdfium_nif.so" });
    b.getInstallStep().dependOn(&install.step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(pdfium.path(b.fmt("lib/{s}", .{library})), .{ .custom = "." }, library).step);
}
