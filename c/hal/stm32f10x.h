/*
 * Minimal type definitions for system_stm32f10x.c.
 *
 * This is NOT the full STM32F10x CMSIS header. It provides only the register
 * structures and constants that system_stm32f10x.c references:
 *   - RCC  (Reset & Clock Control)
 *   - FLASH (Flash Access Control)
 *   - Core register types (SCB)
 *
 * Once we need more peripherals, replace this stub with the real CMSIS headers
 * from the STM32F10x Standard Peripheral Library.
 */

#ifndef __STM32F10X_H
#define __STM32F10X_H

#include <stdint.h>

/* ── Core defines ── */
#define __IO    volatile
#define __O     volatile
#define __I     volatile const

/* HSE crystal frequency (Hz) — Keil project default = 12 MHz */
#if !defined(HSE_VALUE)
#define HSE_VALUE ((uint32_t)12000000)
#endif

/* HSI internal RC frequency */
#define HSI_VALUE ((uint32_t)8000000)

/* ── Base addresses ── */
#define FLASH_BASE            ((uint32_t)0x08000000)
#define SRAM_BASE             ((uint32_t)0x20000000)
#define PERIPH_BASE           ((uint32_t)0x40000000)
#define APB1PERIPH_BASE       PERIPH_BASE
#define APB2PERIPH_BASE       (PERIPH_BASE + 0x10000)
#define AHBPERIPH_BASE        (PERIPH_BASE + 0x20000)

/* ── RCC registers ── */
#define RCC_BASE              (AHBPERIPH_BASE + 0x1000)
#define RCC                   ((RCC_TypeDef *) RCC_BASE)

/* ── FLASH registers ── */
#define FLASH_R_BASE          (AHBPERIPH_BASE + 0x2000)
#define FLASH                 ((FLASH_TypeDef *) FLASH_R_BASE)

/* ── Register structures ── */
typedef struct {
    __IO uint32_t CR;
    __IO uint32_t CFGR;
    __IO uint32_t CIR;
    __IO uint32_t APB2RSTR;
    __IO uint32_t APB1RSTR;
    __IO uint32_t AHBENR;
    __IO uint32_t APB2ENR;
    __IO uint32_t APB1ENR;
    __IO uint32_t BDCR;
    __IO uint32_t CSR;
} RCC_TypeDef;

typedef struct {
    __IO uint32_t ACR;
} FLASH_TypeDef;

/* ── RCC CR bits ── */
#define RCC_CR_HSION          ((uint32_t)0x00000001)
#define RCC_CR_HSIRDY         ((uint32_t)0x00000002)
#define RCC_CR_HSEON          ((uint32_t)0x00010000)
#define RCC_CR_HSERDY         ((uint32_t)0x00020000)
#define RCC_CR_PLLON          ((uint32_t)0x01000000)
#define RCC_CR_PLLRDY         ((uint32_t)0x02000000)
#define RCC_CR_CSSON          ((uint32_t)0x00080000)

/* ── RCC CFGR bits ── */
#define RCC_CFGR_SW           ((uint32_t)0x00000003)
#define RCC_CFGR_SW_HSI       ((uint32_t)0x00000000)
#define RCC_CFGR_SW_HSE       ((uint32_t)0x00000001)
#define RCC_CFGR_SW_PLL       ((uint32_t)0x00000002)
#define RCC_CFGR_SWS          ((uint32_t)0x0000000C)
#define RCC_CFGR_SWS_PLL      ((uint32_t)0x00000008)
#define RCC_CFGR_HPRE         ((uint32_t)0x000000F0)
#define RCC_CFGR_HPRE_DIV1    ((uint32_t)0x00000000)
#define RCC_CFGR_PPRE1        ((uint32_t)0x00000700)
#define RCC_CFGR_PPRE1_DIV2   ((uint32_t)0x00000400)
#define RCC_CFGR_PPRE2        ((uint32_t)0x00003800)
#define RCC_CFGR_PPRE2_DIV1   ((uint32_t)0x00000000)
#define RCC_CFGR_PLLSRC       ((uint32_t)0x00010000)
#define RCC_CFGR_PLLXTPRE     ((uint32_t)0x00020000)
#define RCC_CFGR_PLLMULL      ((uint32_t)0x003C0000)
#define RCC_CFGR_PLLMULL9     ((uint32_t)0x001C0000)
#define RCC_CFGR_PLLSRC_HSE   ((uint32_t)0x00010000)
#define RCC_CFGR_USBPRE       ((uint32_t)0x00400000)

/* ── FLASH ACR bits ── */
#define FLASH_ACR_LATENCY     ((uint32_t)0x00000003)
#define FLASH_ACR_LATENCY_0   ((uint32_t)0x00000000)
#define FLASH_ACR_LATENCY_1   ((uint32_t)0x00000001)
#define FLASH_ACR_LATENCY_2   ((uint32_t)0x00000002)
#define FLASH_ACR_PRFTBE      ((uint32_t)0x00000010)

/* ── General constants ── */
#define RESET                 ((uint32_t)0x00000000)
#define SET                   ((uint32_t)0x00000001)
#define HSE_STARTUP_TIMEOUT   ((uint16_t)0x0500)  /* ~5 ms with default SysTick */
#define VECT_TAB_OFFSET       ((uint32_t)0x00)     /* Vector Table base offset */

/* ── System Control Block (Cortex-M3 core registers) ── */
#define SCB_BASE              ((uint32_t)0xE000ED00)
#define SCB                   ((SCB_TypeDef *) SCB_BASE)

typedef struct {
    __I  uint32_t CPUID;
    __IO uint32_t ICSR;
    __IO uint32_t VTOR;
    __IO uint32_t AIRCR;
    __IO uint32_t SCR;
    __IO uint32_t CCR;
    __IO uint32_t SHPR[3];
    __IO uint32_t SHCSR;
    __IO uint32_t CFSR;
    __IO uint32_t HFSR;
    __IO uint32_t DFSR;
    __IO uint32_t MMFAR;
    __IO uint32_t BFAR;
    __IO uint32_t AFSR;
} SCB_TypeDef;

/* ── SystemCoreClock variable ── */
extern uint32_t SystemCoreClock;

#endif /* __STM32F10X_H */
