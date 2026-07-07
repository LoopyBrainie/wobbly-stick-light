//! Frozen bit-domain color decoder — golden output for host tests.
//!
//! The byte layout is locked by `c/drivers/led_pov.c::LEDSHOW()` and must
//! never change without re-running the 5-Phase hardware validation:
//!
//!     b = (byte >> 6) & 0x03;   // [7:6] Blue   (2 bits)
//!     g = (byte >> 3) & 0x07;   // [5:3] Green  (3 bits)
//!     r =  byte       & 0x07;   // [2:0] Red    (3 bits)

const std = @import("std");
const testing = std.testing;

pub const Channel = packed struct {
    b: u3,
    g: u3,
    r: u3,

    const Self = @This();
};

/// Decode one font byte into its (Blue, Green, Red) channels.
/// Returned as a `packed struct` so the layout is bit-for-bit
/// verifiable from the test side without ABI surprises.
pub fn decodeByte(byte: u8) Channel {
    return .{
        .b = @intCast((byte >> 6) & 0x03),
        .g = @intCast((byte >> 3) & 0x07),
        .r = @intCast(byte & 0x07),
    };
}

// ── Host-native golden-output tests ───────────────────────────────────────

test "0x89 decomposes to {b=2, g=1, r=1}" {
    const result = decodeByte(0x89);
    try testing.expectEqual(@as(u3, 2), result.b);
    try testing.expectEqual(@as(u3, 1), result.g);
    try testing.expectEqual(@as(u3, 1), result.r);
}

test "POV_COLOR_BLUE=0x80 -> {b=2,g=0,r=0}" {
    const result = decodeByte(0x80);
    try testing.expectEqual(@as(u3, 2), result.b);
    try testing.expectEqual(@as(u3, 0), result.g);
    try testing.expectEqual(@as(u3, 0), result.r);
}

test "POV_COLOR_GREEN=0x08 -> {b=0,g=1,r=0}" {
    const result = decodeByte(0x08);
    try testing.expectEqual(@as(u3, 0), result.b);
    try testing.expectEqual(@as(u3, 1), result.g);
    try testing.expectEqual(@as(u3, 0), result.r);
}

test "POV_COLOR_RED=0x01 -> {b=0,g=0,r=1}" {
    const result = decodeByte(0x01);
    try testing.expectEqual(@as(u3, 0), result.b);
    try testing.expectEqual(@as(u3, 0), result.g);
    try testing.expectEqual(@as(u3, 1), result.r);
}

test "POV_COLOR_YELLOW=0x09 -> {b=0,g=1,r=1}" {
    const result = decodeByte(0x09);
    try testing.expectEqual(@as(u3, 0), result.b);
    try testing.expectEqual(@as(u3, 1), result.g);
    try testing.expectEqual(@as(u3, 1), result.r);
}

test "0x00 -> {b=0,g=0,r=0} (off)" {
    const result = decodeByte(0x00);
    try testing.expectEqual(@as(u3, 0), result.b);
    try testing.expectEqual(@as(u3, 0), result.g);
    try testing.expectEqual(@as(u3, 0), result.r);
}

test "0xFF -> {b=3,g=7,r=7} (max)" {
    const result = decodeByte(0xFF);
    try testing.expectEqual(@as(u3, 3), result.b);
    try testing.expectEqual(@as(u3, 7), result.g);
    try testing.expectEqual(@as(u3, 7), result.r);
}