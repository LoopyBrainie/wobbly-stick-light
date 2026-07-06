/**
 * @file    stm32f10x.h
 * @brief   兼容 shim：让 RTE 的 system_stm32f10x.c 不修改即可工作
 *
 * 1. 转发到官方 CMSIS 头
 * 2. 补全 HAL 风格宏 (HSI_VALUE/HSE_VALUE/RESET/__I/__O/__IO) + AHBPrescTable volatile
 * 3. 声明 RTE system 文件导出的符号 (SystemInit / SystemCoreClock / SystemCoreClockUpdate)
 *
 * 业务代码 (board.h / drivers 下的 .c) 应直接 include stm32f103xe.h。
 */
#ifndef WOBBLY_LEGACY_STM32F10X_H
#define WOBBLY_LEGACY_STM32F10X_H

#include "stm32f103xe.h"   /* 官方 CMSIS 设备头 */

/* ==== HAL 数值宏 ==== */
#ifndef HSI_VALUE
#define HSI_VALUE    ((uint32_t)8000000U)
#endif
#ifndef HSE_VALUE
#define HSE_VALUE    ((uint32_t)8000000U)
#endif
#ifndef HSE_STARTUP_TIMEOUT
#define HSE_STARTUP_TIMEOUT  ((uint16_t)0x0500U)
#endif
#ifndef RESET
#define RESET  0U
#endif
#ifndef SET
#define SET    1U
#endif

/* ==== HAL 访问限定符（兜底：若 core_cm3.h 未提供） ==== */
#ifndef __I
#define __I     volatile const
#endif
#ifndef __O
#define __O     volatile
#endif
#ifndef __IO
#define __IO    volatile
#endif

/* ==== HAL 位名 → CMSIS 位名 映射（F103 mainline 没有 PREDIV1 / PLL2） ==== */
#define RCC_CFGR_PLLSRC_HSE                 RCC_CFGR_PLLSRC
#define RCC_CFGR_PLLSRC_HSI                 0U
#define RCC_CFGR_PLLSRC_PREDIV1             0U
#define RCC_CFGR_PLLXTPRE_HSE_Div2          RCC_CFGR_PLLXTPRE
#define RCC_CFGR_PLLXTPRE_PREDIV1           0U
#define RCC_CFGR_PLLXTPRE_PREDIV1_Div2      RCC_CFGR_PLLXTPRE
#define RCC_CR_PLL2ON                       0U
#define RCC_CR_PLL2RDY                      0U

/* ==== system_stm32f10x.c 期望 AHBPrescTable / APBPrescTable 是 volatile const ==== */
extern volatile const uint8_t AHBPrescTable[16U];
extern volatile const uint8_t APBPrescTable[8U];

/* ==== RTE system 文件导出的符号 ==== */
extern uint32_t SystemCoreClock;
void SystemInit(void);
void SystemCoreClockUpdate(void);

#endif /* WOBBLY_LEGACY_STM32F10X_H */
