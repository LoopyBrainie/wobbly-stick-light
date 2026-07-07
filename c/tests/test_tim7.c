/**
 * @file    test_tim7.c
 * @brief   Phase C —— TIM7 100 µs 周期 + PB0 (LED, 不是 PA8/蜂鸣器) 在 ISR 中 toggle
 *
 * == 目的 ==
 *   验证 TIM7 ISR 在 **激进周期 100 µs** 下能稳定翻转 GPIO 同步给示波器
 *   观测 5 kHz 方波。
 *
 * == 为何用 PB0 而非 PA8 ==
 *   STM32F103 默认把 PA8 复用为 TIM1_CH1,板上的蜂鸣器 (BEEP) 物理走这条线
 *   (car2025_final 的 music.c 就是用 TIM1_CH1 出蜂鸣器 PWM)。直接 GPIO toggle
 *   PA8 哪怕不启用 TIM1,也会因为蜂鸣器被驱动发声。
 *
 *   改用 PB0 的好处:
 *     - PB0 已接 LED,main.zig 里已经配成 GP push-pull 50MHz
 *     - 蜂鸣器不挂在这根线 → 安静
 *     - 视觉:LED 不再常亮,转 5 kHz 闪(肉眼积分呈现"半亮")
 *     - 示波器:PB0 测点常用,layout 好找
 *
 * == 为什么能覆盖 it.c 的 TIM7_IRQHandler ==
 *   it.c 把 TIM7_IRQHandler 标为 __attribute__((weak)),链接器允许强符号(test_tim7.c)
 *   覆盖。生产路径不受影响(没有 test_tim7.c 时链接器仍选 weak 那份)。
 */
#include "board.h"

/* === ISR hit 计数 === */
extern volatile uint32_t g_isr_count_tim7;

/* ============================================================ *
 * Phase C —— 强符号覆盖 it.c 的 weak TIM7_IRQHandler
 * ============================================================ */

/**
 * @brief  TIM7 ISR (100µs update): 翻转 PB0 (LED, 不是蜂鸣器!)
 *
 *   时序计算:
 *     PSC = 71  → /72  →  1 MHz counter clock (假设 72 MHz 时基)
 *     ARR = 99  → 100 计数值(0..99) → 100 µs 周期 → 10 kHz 更新率
 *     ISR 翻转 PB0 → 10 kHz transition rate → 5 kHz 方波(占空比 ~50%)
 */
void TIM7_IRQHandler(void) {
    if ((TIM7->SR & TIM_SR_UIF) != 0) {
        TIM7->SR = ~TIM_SR_UIF;          /* 写 0 清 UIF (CMSIS 行为) */
        g_isr_count_tim7++;

        /* PB0 toggle (不是 PA8! PA8 驱动蜂鸣器) */
        if (GPIOB->ODR & (1u << 0)) {
            GPIOB->BSRR = (1u << 16);    /* BR0 = 1u << (0+16) = bit 16 */
        } else {
            GPIOB->BSRR = (1u << 0);     /* BS0 = bit 0 */
        }
    }
}

/* ============================================================ *
 * Phase C 入口 —— test_tim7_start()
 * ============================================================ */

/**
 * @brief  把 TIM7 重新配置为 100µs 周期,启动 TIM7 ISR
 *
 * @pre    必须先调用过 board_init()(使能 GPIOB 时钟)和 led_pov_init()(使能 TIM7 时钟 + NVIC)。
 *
 * @note   **不动任何 GPIO** —— PB0 已在 main.zig 配成 GP push-pull 50MHz,
 *         PA8 故意保留为复位态(避免触发蜂鸣器 BEEP)。
 */
void test_tim7_start(void) {
    /* 1) 停 TIM7,然后改时基 */
    TIM7->CR1 &= ~TIM_CR1_CEN;

    /* 2) 100 µs 周期: PSC = 71 (72 MHz / 72 = 1 MHz counter clock),
     *                  ARR = 99 (100 cycles to overflow) */
    TIM7->PSC = 71U;
    TIM7->ARR = 99U;
    TIM7->CNT = 0U;
    TIM7->EGR = TIM_EGR_UG;     /* 装载 PSC/ARR,必须在 CR1=CEN 之前触发 UE */

    /* 3) 恢复 NVIC(原本 led_pov_init 已设) */
    NVIC->ISER[POV_TIM_IRQn >> 5] = (1U << (POV_TIM_IRQn & 0x1Fu));

    /* 4) 启动 TIM7:CEN=1 */
    TIM7->CR1 |= TIM_CR1_CEN;

    /* 注:故意不动 PB0 (main.zig 已配) 与 PA8 (避免蜂鸣器) */
}
