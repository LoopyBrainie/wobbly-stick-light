/**
 * @file    vibration.c
 * @brief   振动 / 霍尔触发捕获 —— EXTI3 配置 + 极短 ISR
 *
 * == 信号链 ==
 *   PC3 上升沿 → EXTI3_IRQHandler (it.c) → vibration_exti_isr()
 *     → 写时间戳 + 设 pending 标志（无任何业务逻辑）
 *
 * == 消抖 ==
 *   软消抖窗口由振动 consume 函数在主循环里实现
 *   vibration_consume() 返回 1 时由 Zig 调 led_pov_on_vibration()
 */
#include "board.h"
#include "vibration.h"

extern volatile uint32_t g_systick_ms;   /* 来自 it.c */

static volatile uint8_t  s_pending        = 0;
static volatile uint32_t s_trigger_ms     = 0;

void vibration_init(void) {
    /* 1) AFIO: EXTI3 输入源 = PCx → EXTI3[3:0] = 0b0010 (AFIO_EXTICR1, bits 12..15) */
    AFIO->EXTICR[0] = (AFIO->EXTICR[0] & ~(0xFu << 12))
                     |  (0x2u << 12);

    /* 2) EXTI3: 上升沿触发（仅 RTSR） */
    EXTI->RTSR |=  VIBE_EXTI_LINE;
    EXTI->FTSR &= ~VIBE_EXTI_LINE;
    EXTI->IMR  |=  VIBE_EXTI_LINE;        /* 中断屏蔽使能 */

    /* 3) 清 pending（写 1 清） */
    EXTI->PR = VIBE_EXTI_LINE;

    /* 4) NVIC: IP[9] = 8<<4; ISER[0] |= bit9 */
    NVIC->IP[VIBE_EXTI_IRQn] = 8U << 4U;
    NVIC->ISER[VIBE_EXTI_IRQn >> 5] = (1U << (VIBE_EXTI_IRQn & 0x1Fu));

    s_pending = 0;
    s_trigger_ms = 0;
}

void vibration_exti_isr(void) {
    s_trigger_ms = g_systick_ms;
    s_pending = 1;
}

uint8_t vibration_consume(void) {
    if (s_pending == 0) return 0;

    /* 软消抖：5 ms 内重复触发只算一次
     * 注：g_systick_ms 单调递增；减法在 uint32 下自然环绕 */
    uint32_t now = g_systick_ms;
    if ((now - s_trigger_ms) < VIBE_DEBOUNCE_MS) {
        return 0;
    }
    s_pending = 0;
    return 1;
}

uint32_t vibration_last_tick_ms(void) {
    return s_trigger_ms;
}
