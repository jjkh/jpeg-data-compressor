const std = @import("std");
const c = @cImport({
    @cDefine("STB_IMAGE_IMPLEMENTATION", {});
    @cDefine("STBI_ONLY_JPEG", {});
    @cInclude("stb_image.h");
    @cDefine("STB_IMAGE_WRITE_IMPLEMENTATION", {});
    @cInclude("stb_image_write.h");
});

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = parseArgs(allocator) catch |err| {
        try displayHelp(if (err == error.NoArguments) null else err);
        return 1;
    };
    if (args.operation == .compress) {
        try compressFile(allocator, args);
    } else {
        try extractFile(allocator, args);
    }

    return 0;
}

fn writeJpegData(context: ?*anyopaque, data: ?*anyopaque, size: c_int) callconv(.C) void {
    const file: *std.fs.File = @alignCast(@ptrCast(context.?));
    const data_to_write: [*]u8 = @ptrCast(data.?);
    file.writeAll(data_to_write[0..@intCast(size)]) catch |err| std.debug.panic("failed to write data: {}", .{err});
}

fn compressFile(allocator: std.mem.Allocator, args: Args) !void {
    std.log.info("opening file {s}", .{args.infile()});
    const infile = try std.fs.cwd().openFile(args.infile(), .{});
    defer infile.close();

    const file_stat = try infile.stat();
    const file_size = file_stat.size;

    const img_size: u32 = @intFromFloat(@ceil(@sqrt(@as(f32, @floatFromInt(file_size)))));
    std.log.debug(
        "file size: {0}B, image size: {1}x{1}, {2} bytes wasted",
        .{ file_size, img_size, img_size * img_size - file_size },
    );

    var data = try allocator.alloc(u8, img_size * img_size);
    defer allocator.free(data);

    @memset(data, '=');
    _ = try infile.readAll(data);

    std.log.info("creating file {s}", .{args.outfile()});
    var outfile = try std.fs.cwd().createFile(args.outfile(), .{});
    defer outfile.close();

    const result = c.stbi_write_jpg_to_func(
        writeJpegData,
        &outfile,
        @intCast(img_size),
        @intCast(img_size),
        1,
        data.ptr,
        100,
    );
    if (result == 0) return error.WriteFailed;
}

fn extractFile(allocator: std.mem.Allocator, args: Args) !void {
    std.log.info("opening file {s}", .{args.infile()});
    const infile = try std.fs.cwd().openFile(args.infile(), .{});
    defer infile.close();

    const buffer = try infile.readToEndAlloc(allocator, std.math.maxInt(usize));
    var x: c_int = undefined;
    var y: c_int = undefined;
    var n: c_int = undefined;
    const data: ?[*]u8 = c.stbi_load_from_memory(
        buffer.ptr,
        @intCast(buffer.len),
        &x,
        &y,
        &n,
        1,
    );
    defer c.stbi_image_free(data);

    if (data == null) {
        std.log.err("{s}", .{c.stbi_failure_reason()});
        return error.ReadJpegFailed;
    }

    const jpeg_data = data.?[0..@intCast(x * y)];

    std.log.info("creating file {s}", .{args.outfile()});
    var outfile = try std.fs.cwd().createFile(args.outfile(), .{});
    defer outfile.close();

    _ = try outfile.writeAll(jpeg_data);
}

const Args = struct {
    operation: enum { extract, compress },

    infile_buf: [std.fs.MAX_PATH_BYTES]u8,
    infile_len: usize,
    outfile_buf: [std.fs.MAX_PATH_BYTES]u8,
    outfile_len: usize,

    pub inline fn infile(self: Args) []const u8 {
        return self.infile_buf[0..self.infile_len];
    }

    pub inline fn outfile(self: Args) []const u8 {
        return self.outfile_buf[0..self.outfile_len];
    }
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
    args.infile_len = infile.len;

    if (args_it.next()) |outfile| {
        @memcpy(args.outfile_buf[0..outfile.len], outfile);
        args.outfile_len = outfile.len;
    } else {
        const ext = if (args.operation == .compress) ".jpg" else ".out";
        @memcpy(args.outfile_buf[0..args.infile_len], args.infile());
        @memcpy(args.outfile_buf[args.infile_len..][0..ext.len], ext);
        args.outfile_len = args.infile_len + ext.len;
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
