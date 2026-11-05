const std = @import("std");
const macho = std.macho;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    const data = try std.Io.Dir.cwd().readFileAlloc(io, args[1], arena, .unlimited);
    const header = std.mem.bytesAsValue(macho.mach_header_64, data[0..@sizeOf(macho.mach_header_64)]);
    var offset: usize = @sizeOf(macho.mach_header_64);
    var found = false;

    for (0..header.ncmds) |_| {
        const command = std.mem.bytesAsValue(macho.dylib_command, data[offset..][0..@sizeOf(macho.dylib_command)]);
        if (command.cmd == .ID_DYLIB) {
            const name = data[offset + command.dylib.name ..][0 .. command.cmdsize - command.dylib.name];
            if (args[3].len >= name.len) return error.IdTooLong;
            @memset(name, 0);
            @memcpy(name[0..args[3].len], args[3]);
            found = true;
            break;
        }
        offset += command.cmdsize;
    }
    if (!found) return error.NoIdDylib;

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[2], .data = data });
}
