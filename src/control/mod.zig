//! Pure logic layer — no I/O, no globals, no FFI calls.
//!
//! Everything in `src/control/` is host-testable in isolation. Side effects
//! happen in `src/app.zig` (LOOP 6), which translates these pure decisions
//! into `c_bridge` driver calls.

const std = @import("std");
const testing = std.testing;

pub const pov = @import("pov.zig");
pub const debounce = @import("debounce.zig");
pub const font = @import("font.zig");

// ── Aggregator test: forces analysis of every submodule so `zig test mod.zig`
//    discovers the per-submodule test blocks (each submodule owns its own
//    golden-output tests; this file only acts as the test root). ──

test "control submodules are reachable" {
    // Touch every submodule's public surface so the compiler fully analyzes
    // their `test` blocks. None of these are real assertions — the real
    // assertions live alongside the implementations they cover.
    const f = font.decodeByte(0x00);
    try testing.expectEqual(@as(u3, 0), f.b);

    const _vibration: u8 = 1;
    const result = pov.step(.idle, _vibration, 1000, 0);
    try testing.expectEqual(pov.PovState.active, result.next);
    try testing.expectEqual(pov.Action.request_start, result.action);

    try testing.expect(debounce.within_ms(100, 50, 60));
    try testing.expect(!debounce.within_ms(100, 50, 40));
}