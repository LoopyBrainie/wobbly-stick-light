/**
 * @file    board_init.c
 * @brief   摇摇棒板级初始化 —— 等价于 car2025_final 的 HAL_Init() + SystemClock_Config()
 *
 * == 初始化顺序（与 HAL 完全一致）==
 *  1. NVIC priority group = 4 preemption + 0 sub (HAL_NVIC_SetPriorityGrouping(4))
 *  2. Flash prefetch enable (HAL_Init 内 __HAL_FLASH_PREFETCH_BUFFER_ENABLE)
 *  3. HSE 8MHz 起振，等 HSERDY
 *  4. Flash latency = 2 (48-72 MHz 需要 2 wait states) — 必须在切 PLL SYSCLK 之前
 *  5. PLL 配置：HSE 源 ×9 → 72 MHz
 *  6. PLL on, 等 PLLRDY
 *  7. AHB prescaler = 1; APB1 prescaler = 2; APB2 prescaler = 1
 *  8. 切换 SYSCLK = PLL，等 SWS = PLL
 *  9. 更新 SystemCoreClock
 * 10. 使能 GPIOA/B/C/AFIO/SPI1/TIM7 时钟
 * 11. SysTick 1ms tick (enable)
 */
#include "board.h"
#include <stdint.h>

/* HAL_NVIC_SetPriorityGrouping(NVIC_PRIORITYGROUP_4) 简化版 */
static inline void hal_set_priority_grouping(uint32_t pri_group) {
    uint32_t reg = SCB->AIRCR;
    reg = (reg & ~0xFFFF0700U) | (0x05FA0000U | ((pri_group & 7U) << 8U));
    SCB->AIRCR = reg;
    __DSB();
}

void board_init(void) {
    /* ===== 1. NVIC priority group ===== */
    hal_set_priority_grouping(0);  /* 0 = 4 preemption, 0 sub */

    /* ===== 2. Flash prefetch enable ===== */
    FLASH->ACR |= FLASH_ACR_PRFTBE;

    /* ===== 3. HSE 8 MHz 起振 ===== */
    RCC->CR |= RCC_CR_HSEON;
    while ((RCC->CR & RCC_CR_HSERDY) == 0U) { /* spin until HSE ready */ }

    /* ===== 4. Flash latency = 2 wait states (before switching to 72 MHz) ===== */
    FLASH->ACR |= FLASH_ACR_LATENCY_2;
    /* 必须等 latency 生效 (per RM0008 §3.4) */
    while ((FLASH->ACR & FLASH_ACR_LATENCY) == 0U) { /* spin */ }

    /* ===== 5. PLL 配置: HSE 源, ×9 ===== */
    /* HAL: CFGR &= ~(PLLSRC|PLLXTPRE|PLLMULL); CFGR |= PLLSRC|PLLMULL9; */
    RCC->CFGR &= ~(RCC_CFGR_PLLSRC | RCC_CFGR_PLLXTPRE | RCC_CFGR_PLLMULL);
    RCC->CFGR |=  RCC_CFGR_PLLSRC | RCC_CFGR_PLLMULL9;

    /* ===== 6. 启动 PLL ===== */
    RCC->CR |= RCC_CR_PLLON;
    while ((RCC->CR & RCC_CR_PLLRDY) == 0U) { /* spin */ }

    /* ===== 7. 总线分频 ===== */
    RCC->CFGR &= ~(RCC_CFGR_HPRE);
    RCC->CFGR |=  RCC_CFGR_HPRE_DIV1;
    RCC->CFGR &= ~(RCC_CFGR_PPRE1);
    RCC->CFGR |=  RCC_CFGR_PPRE1_DIV2;
    RCC->CFGR &= ~(RCC_CFGR_PPRE2);
    RCC->CFGR |=  RCC_CFGR_PPRE2_DIV1;

    /* ===== 8. 切换 SYSCLK = PLL ===== */
    RCC->CFGR &= ~RCC_CFGR_SW;
    RCC->CFGR |=  RCC_CFGR_SW_PLL;
    while ((RCC->CFGR & RCC_CFGR_SWS) != RCC_CFGR_SWS_PLL) { /* spin */ }

    /* ===== 9. 更新 SystemCoreClock ===== */
    SystemCoreClockUpdate();

    /* ===== 10. 使能外设时钟 ===== */
    RCC->APB2ENR |= RCC_APB2ENR_IOPAEN | RCC_APB2ENR_IOPBEN |
                    RCC_APB2ENR_IOPCEN | RCC_APB2ENR_AFIOEN |
                    RCC_APB2ENR_SPI1EN;
    (void)RCC->APB2ENR;
    RCC->APB1ENR |= RCC_APB1ENR_TIM7EN;
    (void)RCC->APB1ENR;

    /* ===== 11. SysTick 1ms tick (在 72 MHz 之后) ===== */
    SysTick->LOAD  = (SystemCoreClock / 1000U) - 1U;  /* 72000 - 1 = 71999 */
    SysTick->VAL   = 0U;
    SysTick->CTRL  = SysTick_CTRL_CLKSOURCE_Msk |   /* HCLK (72 MHz), 不是 HCLK/8 */
                     SysTick_CTRL_TICKINT_Msk   |
                     SysTick_CTRL_ENABLE_Msk;
}

/* === 字模 RGB 颜色表 === */
__attribute__((used))
const uint8_t POV_ROW_COLOR[POV_ROW_NUM] = {
    POV_COLOR_BLUE,    /* row 0 = L 蓝 */
    POV_COLOR_GREEN,   /* row 1 = K 绿 */
    POV_COLOR_RED,     /* row 2 = M 红 */
};
