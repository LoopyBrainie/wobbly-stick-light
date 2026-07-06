/**
 * @file    it.c
 * @brief   3 个 ISR 入口：SysTick / TIM7 / EXTI3
 *
 * 强符号覆盖 c/startup/startup_stm32f10x_hd.s 中的 weak 默认 handler。
 * 每个 handler 极短：清 pending + 调一个内部函数，无 printf/无 SysTick 等待。
 */
#include "board.h"
#include "led_pov.h"
#include "vibration.h"

/* === 全局 1ms 计数（Zig 侧 extern 读） === */
volatile uint32_t g_systick_ms = 0;

/* === 各 ISR 钩子计数（调试用：probe-rs attach 后读看是否递增） === */
volatile uint32_t g_isr_count_systick = 0;
volatile uint32_t g_isr_count_tim7    = 0;
volatile uint32_t g_isr_count_exti3   = 0;

/* SysTick 1ms 周期：单条自增，零函数调用 */
void SysTick_Handler(void) {
    g_systick_ms++;
    g_isr_count_systick++;
}

/* TIM7 每 250us 周期：清 UIF + 调 led_pov_tick() */
void TIM7_IRQHandler(void) {
    if ((TIM7->SR & TIM_SR_UIF) != 0) {
        TIM7->SR = ~TIM_SR_UIF;          /* 写 0 清 UIF */
        g_isr_count_tim7++;
        led_pov_tick();
    }
}

/* EXTI3 上升沿：清 PR3 + 调 vibration_exti_isr() */
void EXTI3_IRQHandler(void) {
    if ((EXTI->PR & VIBE_EXTI_LINE) != 0) {
        EXTI->PR = VIBE_EXTI_LINE;       /* 写 1 清 pending（CMSIS 行为） */
        g_isr_count_exti3++;
        vibration_exti_isr();
    }
}
