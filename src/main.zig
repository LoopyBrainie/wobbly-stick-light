//! Firmware entry point — LED blink + SRAM heartbeat for verification.
//!
//! Execution flow:
//!   Power-on → Reset_Handler (startup.s) → SystemInit() (C) → main() (here)
//!
//! `heartbeat` lives at .bss start (0x20000000). Read with probe-rs:
//!   probe-rs read b32 0x20000000 1
//! — value must increase over time, confirming the CPU is running our code.

const std = @import("std");

// ── Memory-mapped peripheral registers ──
const RCC_BASE    = 0x40021000;
const RCC_APB2ENR = @as(*volatile u32, @ptrFromInt(RCC_BASE + 0x18));

const GPIOB_BASE = 0x40010C00;
const GPIOB_CRL  = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x00));
const GPIOB_BSRR = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x10));

// ── RCC APB2ENR bits ──
const RCC_APB2ENR_IOPBEN = 1 << 3;

// ── GPIOB pin ──
const LED_PIN = 0; // PB0

// ── Heartbeat counter in .bss (lives at _sbss = 0x20000000) ──
export var heartbeat: u32 = 0;

// ── Entry point ──
export fn main() callconv(.c) noreturn {
    // Enable GPIOB clock
    RCC_APB2ENR.* |= RCC_APB2ENR_IOPBEN;
    _ = RCC_APB2ENR.*;

    // Configure PB0 as 50 MHz push-pull output
    GPIOB_CRL.* &= ~@as(u32, 0xF << (LED_PIN * 4));
    GPIOB_CRL.* |= 0x3 << (LED_PIN * 4);

    while (true) {
        heartbeat += 1;
        GPIOB_BSRR.* = @as(u32, 1 << LED_PIN);
        heartbeat += 1;
        GPIOB_BSRR.* = @as(u32, 1 << (LED_PIN + 16));
        heartbeat += 1;
    }
}

// ── Panic handler ──
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}