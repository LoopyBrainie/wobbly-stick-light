//! Firmware entry point —— Phase 0 heartbeat
//!
//! 5-Phase 底层验证已全部 PASS(详见 c/tests/ 与 docs/)。生产路径只保留:
//!   - PB0 LED 心跳(visor 反馈)
//!   - 板级 clock + SysTick 由 board_init() 配好
//!   - TIM7 ISR (250us) 由 led_pov.c 接好,刷新 POV 字模
//!   - EXTI3 (PC3) 由 vibration.c 接好,触发 POV 复位

const std = @import("std");

// ── C 函数声明 ──
extern fn board_init() callconv(.c) void;
extern fn led_pov_init() callconv(.c) void;

// ── probe-rs 可见的全局 (.data 起始,life-of-flash 给 debug 用) ──
export var phase: u32 = 0xA5A5A5A5;

// ── PB0 LED ──
const RCC_BASE    = 0x40021000;
const RCC_APB2ENR = @as(*volatile u32, @ptrFromInt(RCC_BASE + 0x18));
const GPIOB_BASE  = 0x40010C00;
const GPIOB_CRL   = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x00));
const GPIOB_BSRR  = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x10));
const RCC_APB2ENR_IOPBEN = 1 << 3;
const LED_PIN = 0;

export fn main() callconv(.c) noreturn {
    // PB0 init: 推挽 50MHz 输出 (heartbeat 信号)
    RCC_APB2ENR.* |= RCC_APB2ENR_IOPBEN;
    _ = RCC_APB2ENR.*;
    GPIOB_CRL.* &= ~@as(u32, 0xF << (LED_PIN * 4));
    GPIOB_CRL.* |= 0x3 << (LED_PIN * 4);
    GPIOB_BSRR.* = @as(u32, 1) << LED_PIN;   // LED on = "boot 完成"

    board_init();
    led_pov_init();   // 配 SPI1 + TIM7 + NVIC

    phase = 0x16161616;   // 进入 halted 状态

    // Halt: TIM7 ISR (250us) 持续翻 PB0,EXTI3 ISR 准备响应振动。
    // asm volatile nop 作副作用锚点 —— 不被 -Os 优化掉 (符合 CLAUDE.md)。
    while (true) {
        asm volatile ("nop");
    }
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?*usize) noreturn {
    phase = 0xDEADBEEF;
    while (true) {
        asm volatile ("nop");
    }
}
