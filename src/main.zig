const std = @import("std");
const c = @cImport({
    @cDefine("STB_IMAGE_IMPLEMENTATION", "");
    @cInclude("stb_image.h");
    @cInclude("jo_jpeg.h");
});

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = parseArgs(allocator) catch |err| {
        try displayHelp(if (err == error.NoArguments) null else err);
        return err;
    };
    std.debug.print("op: {}, infile: {s}, outfile: {s}", .{ args.operation, args.infile, args.outfile });
    // if (args.operation == .extract) {
    //     const ppm_image = try extractFileAsPpm(args.infile),

    // }
}

const Args = struct {
    operation: enum { extract, compress },
    infile: []const u8,
    outfile: []const u8,

    infile_buf: [std.fs.MAX_PATH_BYTES]u8,
    outfile_buf: [std.fs.MAX_PATH_BYTES]u8,
};

fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args_it = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args_it.deinit();

    var args: Args = undefined;
    _ = args_it.skip(); // skip exe name

    const operation = args_it.next() orelse return error.NoArguments;
    if (std.ascii.eqlIgnoreCase(operation, "extract")) {
        args.operation = .extract;
    } else if (std.ascii.eqlIgnoreCase(operation, "compress")) {
        args.operation = .compress;
    } else {
        return error.InvalidOperation;
    }

    const infile = args_it.next() orelse return error.MissingArgument;
    @memcpy(args.infile_buf[0..infile.len], infile);
    args.infile = args.infile_buf[0..infile.len];

    if (args_it.next()) |outfile| {
        @memcpy(args.outfile_buf[0..outfile.len], outfile);
        args.outfile = args.outfile_buf[0..outfile.len];
    } else {
        const ext = if (args.operation == .compress) ".jpg" else ".out";
        @memcpy(args.outfile_buf[0..args.infile.len], args.infile);
        @memcpy(args.outfile_buf[args.infile.len..][0..ext.len], ext);
        args.outfile = args.outfile_buf[0 .. args.infile.len + ext.len];
    }

    if (args_it.next() != null)
        return error.TooManyArguments;

    return args;
}

fn displayHelp(parse_error: ?anyerror) !void {
    const stderr = std.io.getStdErr().writer();
    if (parse_error) |err| {
        try stderr.print("ERROR: {}\n\n", .{err});
    }

    try stderr.writeAll("jpeg-data-compressor\n");
    try stderr.writeAll("--------------------\n");
    try stderr.writeAll("Usage:\n");
    try stderr.writeAll("    jpeg-data-compressor compress <infile> [outfile]\n");
    try stderr.writeAll("    jpeg-data-compressor extract <infile> [outfile]\n\n");
}
