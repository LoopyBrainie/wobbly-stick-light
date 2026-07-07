//! Firmware entry —— only delegates to `app.run()` and provides a panic sink.

const std = @import("std");
const app = @import("app.zig");

/// Bare-metal entry: startup_stm32f10x_hd.s does `bl main`. Everything else
/// lives in `app.zig`.
export fn main() callconv(.c) noreturn {
    app.run();
}

/// Required by Zig's runtime; `app.run()` is `noreturn` so this only fires
/// on a true panic (assertion failure, OOB index, etc.).
pub fn panic(
    _: []const u8,
    _: ?*std.builtin.StackTrace,
    _: ?*usize,
) noreturn {
    while (true) {
        asm volatile ("nop");
    }
}
