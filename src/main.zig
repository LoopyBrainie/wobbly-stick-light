//! Firmware entry point — LED blink (PB0) via direct register access.
//!
//! Execution flow:
//!   Power-on → Reset_Handler (startup.s) → SystemInit() (C) → main() (here)
//!
//! Zero HAL dependency — all register addresses and bit masks are inline.

const std = @import("std");

// ── Memory-mapped peripheral registers ──
const RCC_BASE    = 0x40021000;
const RCC_APB2ENR = @as(*volatile u32, @ptrFromInt(RCC_BASE + 0x18));

const GPIOB_BASE = 0x40010C00;
const GPIOB_CRL  = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x00));
const GPIOB_ODR  = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x0C));
const GPIOB_BSRR = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x10));

// ── RCC APB2ENR bits ──
const RCC_APB2ENR_IOPBEN = 1 << 3; // GPIOB clock enable

// ── GPIOB pin ──
const LED_PIN = 0; // PB0

// ── Entry point ──
export fn main() callconv(.c) noreturn {
    // Enable GPIOB clock
    RCC_APB2ENR.* |= RCC_APB2ENR_IOPBEN;
    _ = RCC_APB2ENR.*; // pipeline flush (DSB is implicit after STR on M3)

    // Configure PB0 as push-pull output (MODE=11b, CNF=00b)
    // CRL controls pins 0-7; each pin uses 4 bits.
    // Clear the 4-bit field for pin 0, then set MODE0 = 11b (50 MHz output).
    GPIOB_CRL.* &= ~@as(u32, 0xF << (LED_PIN * 4));
    GPIOB_CRL.* |= 0x3 << (LED_PIN * 4); // MODE0 = 11 (50 MHz), CNF0 = 00 (push-pull)

    // ── Main loop: blink PB0 at ~1 Hz ──
    while (true) {
        // Toggle PB0 via BSRR — atomic, no read-modify-write needed
        GPIOB_BSRR.* = @as(u32, 1 << LED_PIN);        // Set PB0
        delay(~@as(u32, 0));                            // ~0.5s
        GPIOB_BSRR.* = @as(u32, 1 << (LED_PIN + 16));  // Reset PB0 (BRy = BSy + 16)
        delay(~@as(u32, 0));                            // ~0.5s
    }
}

// ── Crude delay (72 MHz SysClk → ~2.4M iterations ≈ 0.5s at -OReleaseSmall) ──
fn delay(cycles: u32) void {
    var i: u32 = cycles;
    while (i > 0) : (i -= 1) {}
}

// ── Panic handler ──
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}
