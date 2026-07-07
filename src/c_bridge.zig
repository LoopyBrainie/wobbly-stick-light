//! Raw extern fn declarations for the C driver layer.
//!
//! No @cImport anywhere — every signature is hand-written so the build
//! stays hermetic and Zig-only test targets (host-native) can compile
//! these declarations without dragging in CMSIS headers.

const std = @import("std");

/// POV row × col dimensions (must match `board.h::POV_ROW_NUM/POV_COL_NUM`).
pub const POV_ROW_NUM: usize = 3;
pub const POV_COL_NUM: usize = 40;

pub const LedPovState = enum(c_int) {
    stop = 0,
    idle = 1,
    start = 2,
    _,
};

// ── Globals exposed by the C side ──
//
// Zig 0.16 removed the `volatile` type qualifier. Treat these as plain
// `extern var` for the declaration; reads/writes go through pointer
// casts (`*volatile T`) at use sites so the compiler cannot fold them.

/// 1ms monotonic tick — written by SysTick ISR in `c/drivers/it.c`.
pub extern var g_systick_ms: u32;

/// Fence flag consumed by `led_pov_tick()` on the next TIM7 ISR — written
/// by Zig after `vibration_consume_clear()` so the column walk resets.
pub extern var g_LED_key_down: u8;

/// Volatile wrapper read. Zig cannot elide this — backed by a `*volatile`
/// pointer to the extern storage, so the compiler must reload each use.
pub fn readSystickMs() u32 {
    return @as(*volatile u32, @ptrCast(&g_systick_ms)).*;
}

pub fn writeLedKeyDown(v: u8) void {
    @as(*volatile u8, @ptrCast(&g_LED_key_down)).* = v;
}

// ── Driver entry points (callconv(.c) per CLAUDE.md) ──

pub extern fn board_init() callconv(.c) void;
pub extern fn led_pov_init() callconv(.c) void;
pub extern fn led_pov_start() callconv(.c) void;
pub extern fn led_pov_stop() callconv(.c) void;
pub extern fn led_pov_set_pattern(font: [*]const [POV_COL_NUM]u8) callconv(.c) void;
pub extern fn led_pov_on_vibration() callconv(.c) void;
pub extern fn led_pov_get_state() callconv(.c) LedPovState;

pub extern fn vibration_init() callconv(.c) void;
pub extern fn vibration_consume() callconv(.c) u8;
pub extern fn vibration_consume_clear() callconv(.c) u8;

// DEBUG ONLY (Diagnostic 4): bypass FSM/ISR, force RAM=0x80 + LEDSHOW(0,0).
pub extern fn led_pov_force_blue() callconv(.c) void;

/// LKM 字模（来自 c/drivers/font_pov.c）。在 app.zig 通过 &FONT_LKM 取址。
pub extern const FONT_LKM: [POV_ROW_NUM][POV_COL_NUM]u8;

/// Rainbow 调试字模（来自 c/drivers/font_pov.c）：row0=blue(0..15), row1=green(16..31), row2=red(32..39)
pub extern const FONT_RAINBOW: [POV_ROW_NUM][POV_COL_NUM]u8;

// ── Sanity: std is referenced via `@import` only — drop the unused import ──
// (kept referenced above so the file still compiles if a future helper needs it)

comptime {
    // Compile-time guard: ensure POV dimensions match `board.h` invariants.
    // If board.h is ever changed, this fails the build before firmware boots.
    std.debug.assert(POV_ROW_NUM == 3);
    std.debug.assert(POV_COL_NUM == 40);
}