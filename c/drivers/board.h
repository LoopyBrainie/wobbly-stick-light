/**
 * @file    board.h
 * @brief   摇摇棒板级引脚/时钟/总线映射 —— 8-pin 接口与 MCU 资源的唯一配置点
 *
 * 派生自 car2025_final 的 `Core/Inc/main.h`，已剔除所有与摇摇棒无关的引脚
 * （电机、超声波、OLED、磁力计等）。任何新增的板级资源都必须先在本文件
 * 集中定义，再由各驱动引用，禁止分散到各 .c 里。
 *
 * === 8-pin 接口映射（参考 car2025_final） ===
 *
 *   Pin1  VCC_3V3   → 板子供电
 *   Pin2  GND       → 电源地
 *   Pin3  SPI1_SCK  → POV_SCK       (PA5)
 *   Pin4  SPI1_MOSI → POV_MOSI      (PA7)
 *   Pin5  POV_CS    → 手动片选      (PA6, 复用原 IR_LOCK)
 *   Pin6  VIBE_SIG  → 霍尔/振动触发 (PC3, EXTI3 上升沿)
 *   Pin7  TIM7_TICK → 刷新定时器    (内部资源, 不出到接口)
 *   Pin8  NRST      → 复位（保留给 MCU 内部）
 *
 * == 不可修改的硬件常量 ==
 *   - HCLK = 72 MHz（来自 car2025_final SystemClock_Config: HSE 8 MHz × PLL×9）
 *   - TIM7 时钟源 = APB1 × 2 = 72 MHz
 *   - TIM7 配置: prescaler=3599, autoreload=4 → 4 kHz 刷新中断
 *
 * == 头文件依赖 ==
 *   业务代码直接用官方 CMSIS 头（stm32f103xe.h）—— 所有 GPIO_TypeDef、
 *   TIM_TypeDef、SPI_TypeDef、IRQn 枚举、寄存器位掩码都来自这里。
 *   HAL 宏（__HAL_RCC_*_CLK_ENABLE / GPIO_PIN_* / EXTI_Line*）**已废弃**，
 *   本文件用等价的寄存器位掩码代替。
 */
#ifndef WOBBLY_BOARD_H
#define WOBBLY_BOARD_H

#include <stdint.h>
#include "stm32f103xe.h"   /* 官方 CMSIS 设备头，含所有外设 typedef + 基地址 + 位掩码 + IRQn */

#ifdef __cplusplus
extern "C" {
#endif

/* === MCU 时钟（与 SystemClock_Config 同步） === */
#define BOARD_HCLK_HZ          72000000UL
#define BOARD_PCLK1_HZ         36000000UL   /* APB1 = HCLK / 2 */
#define BOARD_TIM7_CLK_HZ      72000000UL   /* APB1 prescaler != 1 → ×2 给定时器 */

/* === 时钟使能（直接展开，替代 HAL __HAL_RCC_*_CLK_ENABLE 宏） === */
#define POV_SPI_CLK_EN()       do { RCC->APB2ENR |= RCC_APB2ENR_SPI1EN;  (void)RCC->APB2ENR; } while (0)
#define POV_SPI_GPIO_CLK_EN()  do { RCC->APB2ENR |= RCC_APB2ENR_IOPAEN;  (void)RCC->APB2ENR; } while (0)
#define VIBE_GPIO_CLK_EN()     do { RCC->APB2ENR |= RCC_APB2ENR_IOPCEN | RCC_APB2ENR_AFIOEN; (void)RCC->APB2ENR; } while (0)
#define POV_TIM_CLK_EN()       do { RCC->APB1ENR |= RCC_APB1ENR_TIM7EN;  (void)RCC->APB1ENR; } while (0)

/* === SPI1 总线（POV 显示专用） === */
#define POV_SPI                SPI1
#define POV_SCK_PORT           GPIOA
#define POV_SCK_PIN            (1U << 5)     /* PA5 —  CMSIS 无 GPIO_Pin_X，用字面量 */
#define POV_MOSI_PORT          GPIOA
#define POV_MOSI_PIN           (1U << 7)     /* PA7 */
#define POV_CS_PORT            GPIOA         /* 复用 car2025_final 的 IR_LOCK = PA6 */
#define POV_CS_PIN             (1U << 6)     /* PA6 */

/* === 振动 / 霍尔触发（PC3, EXTI3 上升沿） === */
#define VIBE_PORT              GPIOC
#define VIBE_PIN               (1U << 3)
#define VIBE_EXTI_IRQn         EXTI3_IRQn    /* 来自 stm32f103xe.h: 9 */
#define VIBE_EXTI_LINE         (1U << 3)     /* CMSIS 不提供 EXTI_Line* 宏，用位掩码 */

/* === POV 刷新定时器 TIM7 === */
#define POV_TIM                TIM7
#define POV_TIM_IRQn           TIM7_IRQn     /* 来自 stm32f103xe.h: 55 */
#define POV_TIM_PRESCALER      3599U         /* 72 MHz / 3600 = 20 kHz */
#define POV_TIM_AUTORELOAD     4U            /* 20 kHz / 5 = 4 kHz → 250 us 周期（与 car2025 reference 对齐 + 冲程去抖）*/
#define POV_TIM_TICK_HZ        4000U
#define POV_TIM_TICK_US        250U

/* === 显示帧几何常量（与 car2025_final 一致） === */
#define POV_COL_NUM            40U           /* 一帧的列数 (Boundary C invariant) */
#define POV_ROW_NUM            3U            /* 三行字模：蓝 / 绿 / 红 */
#define POV_CAT_NUM            6U            /* 6 段扫描 cat 选择 */
#define POV_INTERRUPTS_PER_FRAME (POV_COL_NUM * POV_CAT_NUM)   /* 240 中断/帧 */
#define POV_FRAME_PERIOD_MS    ((uint32_t)(POV_INTERRUPTS_PER_FRAME * POV_TIM_TICK_US) / 1000U)  /* 60 ms */

/* === 像素颜色编码（8 bits = 蓝2 + 绿3 + 红3） ===
 * 关键：POV_COLOR_* 必须 **满通道**（B=3, G=7, R=7）才能在 LEDSHOW 中
 * 让一个 cat 的 4 颗 LED 同时点亮。若只用 B=2 / G=1 / R=1（0x80 / 0x08 / 0x01）
 * 只能让 1-2 颗/cat 亮——font byte=0xFF 的"垂直满列"看上去变成顶部 4 颗
 * 稀疏点亮而非完整 8 颗垂直条，眼睛看到的"全亮"其实是稀疏高亮被融合。
 *   例：POV_COLOR_BLUE=0xC0 → B=3 → cat 内 4 颗全蓝
 *       POV_COLOR_GREEN=0x38 → G=7 → cat 内 4 颗全绿
 *       POV_COLOR_RED=0x07 → R=7 → cat 内 4 颗全红
 *       POV_COLOR_YELLOW=0x3F → G+R=满 → cat 内 4 颗全黄
 * LEDSHOWN 中 buf/bit-domain 解码：
 *   b = (byte >> 6) & 0x03  → 0=空 / 1=第0颗 / 2=第0,1颗 / 3=4颗全亮
 *   g = (byte >> 3) & 0x07  → 同理 0..7 对应 0..4 颗
 *   r =  byte        & 0x07  → 同理 0..7 对应 0..4 颗
 */
#define POV_COLOR_BLUE         0xC0U         /* B = 0x03 = 4 颗全亮 */
#define POV_COLOR_GREEN        0x38U         /* G = 0x07 = 4 颗全亮 */
#define POV_COLOR_RED          0x07U         /* R = 0x07 = 4 颗全亮 */
#define POV_COLOR_YELLOW       0x3FU         /* G+R = 4 颗全亮 */
#define POV_COLOR_OFF          0x00U

#ifdef __cplusplus
}
#endif

#endif /* WOBBLY_BOARD_H */
