/**
 * @file    system_stm32f1xx.h
 * @brief   转发 shim：stm32f103xe.h 会 #include "system_stm32f1xx.h"
 *          我们使用 RTE 的 system_stm32f10x.c/.h（HAL 风格）
 *          实际声明都在 c/hal/stm32f10x.h shim 里
 */
#ifndef WOBBLY_SYSTEM_STM32F1XX_H
#define WOBBLY_SYSTEM_STM32F1XX_H

#include "stm32f10x.h"   /* shim 包含所有声明（SystemCoreClock / AHBPrescTable / ...） */

#endif
