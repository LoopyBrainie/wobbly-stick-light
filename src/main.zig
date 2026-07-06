//! Firmware entry point —— Phase 0 最小化诊断版本
//!
//! 仅做：1) PB0 设推挽 50MHz 输出；2) 调 board_init()；3) 死循环翻转 PB0
//! 不调 led_pov_init / vibration_init（这些之后再加）
//! 目的：判断 Lockup 发生在 board_init 之前还是之后

const std = @import("std");

// ── C 函数声明 ──
extern fn board_init() callconv(.c) void;

// ── 调试可见的全局变量（写在 0x20000000 附近，halt 后 probe-rs 可读） ──
export var phase: u32 = 0xAAAAAAAA;
export var phase2: u32 = 0xBBBBBBBB;

// ── PB0 LED ──
const RCC_BASE    = 0x40021000;
const RCC_APB2ENR = @as(*volatile u32, @ptrFromInt(RCC_BASE + 0x18));
const GPIOB_BASE  = 0x40010C00;
const GPIOB_CRL   = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x00));
const GPIOB_BSRR  = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x10));
const RCC_APB2ENR_IOPBEN = 1 << 3;
const LED_PIN = 0;

export fn main() callconv(.c) noreturn {
    phase = 0x11111111;  // 进入 main 标记

    // PB0 init
    RCC_APB2ENR.* |= RCC_APB2ENR_IOPBEN;
    _ = RCC_APB2ENR.*;
    GPIOB_CRL.* &= ~@as(u32, 0xF << (LED_PIN * 4));
    GPIOB_CRL.* |= 0x3 << (LED_PIN * 4);

    phase = 0x22222222;  // PB0 OK，准备调 board_init

    // 调 C 板级初始化（HAL 等价序列）
    board_init();

    phase = 0x33333333;  // board_init 返回

    // 死循环翻 PB0
    // 注意：-Os 下空 while 循环会被优化掉，必须在循环体里读 volatile 寄存器
    //      作副作用锚点。这里读 SysTick->VAL（72 MHz SysTick，每 ms 倒数一次）
    const SysTick_VAL = @as(*volatile u32, @ptrFromInt(0xE000E018));
    while (true) {
        GPIOB_BSRR.* = @as(u32, 1) << LED_PIN;       // set PB0=1
        // 约 250ms 延迟：读 SysTick VAL 72000 次 × 一次循环 4 instr ≈ 4 ms... 改用 200 万次
        var i: u32 = 0;
        while (i < 2000000) : (i += 1) {
            _ = SysTick_VAL.*;  // 防优化
        }
        GPIOB_BSRR.* = @as(u32, 1) << (LED_PIN + 16); // reset PB0=0
        var j: u32 = 0;
        while (j < 2000000) : (j += 1) {
            _ = SysTick_VAL.*;  // 防优化
        }
    }
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    phase = 0xDEADBEEF;  // panic 标记
    _ = msg;
    while (true) {}
}
