const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("string.h");
    @cInclude("errno.h");
});

const python27 = switch (builtin.os.tag) {
    .linux => "Python 2.7.16rc1 (default, Feb 18 2019, 11:05:09)\n[GCC 8.2.0] on linux2\nType \"help\", \"copyright\", \"credits\" or \"license\" for more information.\n",
    .macosx => "Python 2.7.10 (default, Aug 17 2018, 19:45:58)\n[GCC 4.2.1 Compatible Apple LLVM 10.0.0 (clang-1000.0.42)] on darwin\nType \"help\", \"copyright\", \"credits\" or \"license\" for more information.\n",
    else => unreachable,
};

const python37 = switch (builtin.os.tag) {
    .linux => "Python 3.7.2+ (default, Feb 27 2019, 15:41:59)\n[GCC 8.2.0] on linux\nType \"help\", \"copyright\", \"credits\" or \"license\" for more information.\n",
    .macosx => "Python 3.7.2+ (default, Feb 27 2019, 15:41:59)\n[GCC 4.2.1 Compatible Apple LLVM 10.0.0 (clang-1000.0.42)] on darwin\nType \"help\", \"copyright\", \"credits\" or \"license\" for more information.\n",
    else => unreachable,
};

const stdout = std.io.getStdOut().outStream();
const stderr = std.io.getStdErr().outStream();
const stdin = std.io.getStdIn().inStream();

fn printPrompt() !void {
    try stdout.print(">>> ", .{});
}

fn printVersion(name: []const u8) !void {
    const py3k = std.mem.indexOf(u8, name, "python3") != null;
    const ver_string = if (py3k) python37 else python27;
    try stdout.print("{}", .{ver_string});
}

fn notCommentOrBlank(line: []const u8) bool {
    for (line) |ch| {
        const answer = switch (ch) {
            ' ', '\t' => null,
            '#', '\n', 0 => false,
            else => true,
        };
        if (answer) |ans| {
            return ans;
        } else {
            continue;
        }
    }
    return false;
}

/// Reads a line of code from the file into buf, returns a slice with
/// the same .ptr address as buf, and updates lineno to be the line
/// number of the in_stream.
fn readLine(in_stream: anytype, lineno: *usize, buf: []u8, prompt: bool) ![]u8 {
    lineno.* = 0;
    while (true) {
        const line = try in_stream.readUntilDelimiterOrEof(buf, '\n');
        lineno.* += 1;
        if (line) |nnline| {
            if (notCommentOrBlank(nnline)) {
                return nnline;
            } else if (prompt) {
                try printPrompt();
            }
        } else {
            return error.EOFError;
        }
    }
}

fn printError(filename: []const u8, lineno: usize, errline: []const u8) !void {
    try stderr.print(
        \\  File "{}", line {}
        \\    {}
        \\    ^
        \\SyntaxError: invalid syntax
    , .{ filename, lineno, errline });
    try stderr.print("\n", .{});
}

/// Returns the first non-empty line in filename, using the memory in buf.
fn getLine(
    progname: []const u8,
    filename: []const u8,
    lineno: *usize,
    buf: []u8,
) ![]u8 {
    const dir = std.fs.cwd();
    const fh = dir.openFile(filename, .{ .read = true }) catch {
        const errno = c.__errno_location().*; // Linux only? Maybe.
        const errstr = @ptrCast([*:0]const u8, c.strerror(errno));
        try stderr.print(
            "{}: can't open file '{}': [Errno {}] {}\n",
            .{ progname, filename, errno, errstr },
        );
        return error.OpenError;
    };
    const line = try readLine(fh.inStream(), lineno, buf, false);
    return line;
}

pub fn main() anyerror!u8 {
    var args = std.process.args();
    const cmd = args.nextPosix().?;
    const filename = args.nextPosix();
    var lineno: usize = undefined;
    var buf: [1024]u8 = undefined;

    if (filename) |fname| {
        if (getLine(cmd, fname, &lineno, buf[0..])) |errline| {
            try printError(fname, lineno, errline);
            return 1;
        } else |err| {
            return 2;
        }
    } else {
        lineno = 1;
        // Read lines from stdin.
        try printVersion(cmd);
        while (true) {
            try printPrompt();
            if (readLine(stdin, &lineno, buf[0..], true)) |line| {
                try printError("<stdin>", lineno, line);
            } else |err| {
                switch (err) {
                    error.EOFError => {
                        try stdout.print("\n", .{});
                    },
                    else => {},
                }
                return 130;
            }
        }
    }
}
