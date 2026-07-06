//! Firmware entry point.
//!
//! Execution flow:
//!   Power-on → Reset_Handler (startup.s) → SystemInit() (C) → main() (here)
//!
//! Bare-metal: no OS, no heap, no argv. Everything we use must be self-contained.

const std = @import("std");

// ── Entry point ──
// Called from C startup code (Reset_Handler) after SystemInit().
// Must use C calling convention and never return.
export fn main() callconv(.c) noreturn {
    while (true) {
        // Spin. On Cortex-M3 in thumb mode, this compiles to: b .
    }
}

// ── Panic handler ──
// Called by Zig runtime on @panic().
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}

// ── Overridden interrupt handlers ──
// Each is declared [WEAK] in startup.s; exporting a symbol here overrides it.

export fn SysTick_Handler() callconv(.c) void {
    // TODO: increment global tick counter
}
