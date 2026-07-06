/**
 * @file    vibration.h
 * @brief   振动 / 霍尔触发信号捕获 —— 带软消抖
 *
 * 移植自 car2025_final/Core/Src/common.c::HAL_GPIO_EXTI_Callback 中 PC3 的处理：
 *   - 原代码: EXTI3 上升沿直接置 g_LED_key_down = 1，无消抖
 *   - 本驱动: 增加 5 ms 软消抖窗口，避免机械弹簧开关抖动导致画面卡死在第一列
 *
 * == 信号链 ==
 *   PC3 上升沿 → EXTI3_IRQHandler → HAL_GPIO_EXTI_IRQHandler
 *     → HAL_GPIO_EXTI_Callback（重写自 stm32f1xx_it.c）→ vibration_exti_isr()
 *       ├─ 记录 SysTick 时间戳
 *       └─ 设 g_vibration_pending = 1
 *
 *   主循环调用 vibration_consume()
 *     └─ 若 pending 且距上次触发 ≥ VIBE_DEBOUNCE_MS → 返回 1 并清 pending
 *
 * == 何时上报触发 ==
 *   上层（led_pov.c）应在收到 vibration_consume() == 1 后调用
 *   led_pov_on_vibration() 进行过零复位
 */
#ifndef WOBBLY_VIBRATION_H
#define WOBBLY_VIBRATION_H

#include <stdint.h>
#include "board.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 软消抖窗口：5 ms 内重复触发只算一次 */
#define VIBE_DEBOUNCE_MS       5U

/* === 实现前置条件 === */
/*
 * vibration_exti_isr() 和 vibration_last_tick_ms() 依赖 HAL_GetTick() 返回毫秒。
 * 必须保证 c/hal/system_stm32f10x.c 的 SysTick 已配置为 1 ms 周期：
 *   SysTick_Config(BOARD_HCLK_HZ / 1000U);   // 72000-1
 *
 * 若 SysTick 周期不是 1 ms，需在 .c 实现里把 HAL_GetTick() 替换为自定义时间源，
 * 或在此头文件改 VIBE_DEBOUNCE_MS 的单位。
 */

/**
 * @brief  初始化：使能 GPIOC/AFIO 时钟、配置 PC3 为 EXTI 上升沿输入、NVIC
 * @note   必须在 board_init() 之后、SysTick 启动之后调用
 */
void vibration_init(void);

/**
 * @brief  EXTI3 ISR 钩子（在 stm32f1xx_it.c 的 HAL_GPIO_EXTI_Callback 里调用）
 * @note   本函数仅记录 SysTick 时间戳 + 置 pending，逻辑极短
 */
void vibration_exti_isr(void);

/**
 * @brief  主循环调用：若自上次消费以来发生过有效触发则返回 1
 * @retval 1   有新触发
 * @retval 0   无新触发（或被消抖过滤）
 *
 * == 副作用 ==
 *   - 消费成功后清 pending
 *   - 同时调用 led_pov_on_vibration() 完成过零复位
 */
uint8_t vibration_consume(void);

/**
 * @brief  获取自上次触发以来的毫秒数（用于调试 / 高级逻辑）
 */
uint32_t vibration_last_tick_ms(void);

#ifdef __cplusplus
}
#endif

#endif /* WOBBLY_VIBRATION_H */