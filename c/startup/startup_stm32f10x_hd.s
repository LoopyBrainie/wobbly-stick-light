@ file    startup_stm32f10x_hd.s  (GNU AS 风格, 模仿 RTE ARM AS 行为)
@ brief   摇摇棒 startup
@
@ == Reset_Handler 流程 ==
@  1. SystemInit() —— c/hal/system_stm32f10x.c 提供 (RTE 1094 行版)
@     设置 HSE 8MHz + PLL ×9 → 72MHz, AHB/APB prescalers, Flash latency
@  2. .data 复制 (flash → SRAM)
@  3. .bss 清零
@  4. main() 入口
@
@ 注意: RTE 的 .s 调 __main (Keil C 库入口), 我们没有 Keil 库所以 .s 自己 .data/.bss
@       然后直接 bl main

  .syntax unified
  .thumb

@ ==== 中断向量表 ====
@ section 名必须匹配 ld 脚本 KEEP(*(.vector_table))，否则向量表被丢/合并错位
  .section .vector_table, "a", %progbits
  .global g_pfnVectors
  .type   g_pfnVectors, %object
  .size   g_pfnVectors, . - g_pfnVectors

g_pfnVectors:
  .word  _estack                   @ 0x00 初始 SP = SRAM 顶
  .word  Reset_Handler             @ 0x04 Reset
  .word  NMI_Handler
  .word  HardFault_Handler
  .word  MemManage_Handler
  .word  BusFault_Handler
  .word  UsageFault_Handler
  .word  0
  .word  0
  .word  0
  .word  0
  .word  SVC_Handler
  .word  DebugMon_Handler
  .word  0
  .word  PendSV_Handler
  .word  SysTick_Handler

  @ 设备特定中断
  .word  WWDG_IRQHandler
  .word  PVD_IRQHandler
  .word  TAMPER_IRQHandler
  .word  RTC_IRQHandler
  .word  FLASH_IRQHandler
  .word  RCC_IRQHandler
  .word  EXTI0_IRQHandler
  .word  EXTI1_IRQHandler
  .word  EXTI2_IRQHandler
  .word  EXTI3_IRQHandler          @ 摇摇棒振动
  .word  EXTI4_IRQHandler
  .word  DMA1_Channel1_IRQHandler
  .word  DMA1_Channel2_IRQHandler
  .word  DMA1_Channel3_IRQHandler
  .word  DMA1_Channel4_IRQHandler
  .word  DMA1_Channel5_IRQHandler
  .word  DMA1_Channel6_IRQHandler
  .word  DMA1_Channel7_IRQHandler
  .word  ADC1_2_IRQHandler
  .word  USB_HP_CAN1_TX_IRQHandler
  .word  USB_LP_CAN1_RX0_IRQHandler
  .word  CAN1_RX1_IRQHandler
  .word  CAN1_SCE_IRQHandler
  .word  EXTI9_5_IRQHandler
  .word  TIM1_BRK_IRQHandler
  .word  TIM1_UP_IRQHandler
  .word  TIM1_TRG_COM_IRQHandler
  .word  TIM1_CC_IRQHandler
  .word  TIM2_IRQHandler
  .word  TIM3_IRQHandler
  .word  TIM4_IRQHandler
  .word  I2C1_EV_IRQHandler
  .word  I2C1_ER_IRQHandler
  .word  I2C2_EV_IRQHandler
  .word  I2C2_ER_IRQHandler
  .word  SPI1_IRQHandler
  .word  SPI2_IRQHandler
  .word  USART1_IRQHandler
  .word  USART2_IRQHandler
  .word  USART3_IRQHandler
  .word  EXTI15_10_IRQHandler
  .word  RTCAlarm_IRQHandler
  .word  USBWakeUp_IRQHandler
  .word  TIM8_BRK_IRQHandler
  .word  TIM8_UP_IRQHandler
  .word  TIM8_TRG_COM_IRQHandler
  .word  TIM8_CC_IRQHandler
  .word  ADC3_IRQHandler
  .word  FSMC_IRQHandler
  .word  SDIO_IRQHandler
  .word  TIM5_IRQHandler
  .word  SPI3_IRQHandler
  .word  UART4_IRQHandler
  .word  UART5_IRQHandler
  .word  TIM6_IRQHandler
  .word  TIM7_IRQHandler            @ 摇摇棒 POV 刷新
  .word  DMA2_Channel1_IRQHandler
  .word  DMA2_Channel2_IRQHandler
  .word  DMA2_Channel3_IRQHandler
  .word  DMA2_Channel4_5_IRQHandler

  .size  g_pfnVectors, . - g_pfnVectors

@ ==== Reset_Handler ====
  .section .text.Reset_Handler, "ax", %progbits
  .weak    Reset_Handler
  .type    Reset_Handler, %function

Reset_Handler:
  @ 1) SystemInit
  bl       SystemInit

  @ 2) .data 复制
  ldr      r0, =_sdata
  ldr      r1, =_edata
  ldr      r2, =_sidata
  movs     r3, #0
  b        LoopCopyDataInit

CopyDataInit:
  ldr      r4, [r2, r3]
  str      r4, [r0, r3]
  adds     r3, r3, #4

LoopCopyDataInit:
  adds     r4, r0, r3
  cmp      r4, r1
  bcc      CopyDataInit

  @ 3) .bss 清零
  ldr      r2, =_sbss
  ldr      r4, =_ebss
  movs     r3, #0
  b        LoopFillZerobss

FillZerobss:
  str      r3, [r2]
  adds     r2, r2, #4

LoopFillZerobss:
  cmp      r2, r4
  bcc      FillZerobss

  @ 4) 进入 main (Zig 端)
  bl       main

  @ 兜底
  b        .

  .size    Reset_Handler, . - Reset_Handler

@ ==== 默认异常处理 ====
  .section .text.Default_Handler, "ax", %progbits
  .weak    NMI_Handler
  .thumb_func
NMI_Handler:
  b        .
  .size    NMI_Handler, . - NMI_Handler
  .weak    HardFault_Handler
  .thumb_func
HardFault_Handler:
  b        .
  .size    HardFault_Handler, . - HardFault_Handler
  .weak    MemManage_Handler
  .thumb_func
MemManage_Handler:
  b        .
  .size    MemManage_Handler, . - MemManage_Handler
  .weak    BusFault_Handler
  .thumb_func
BusFault_Handler:
  b        .
  .size    BusFault_Handler, . - BusFault_Handler
  .weak    UsageFault_Handler
  .thumb_func
UsageFault_Handler:
  b        .
  .size    UsageFault_Handler, . - UsageFault_Handler
  .weak    SVC_Handler
  .thumb_func
SVC_Handler:
  b        .
  .size    SVC_Handler, . - SVC_Handler
  .weak    DebugMon_Handler
  .thumb_func
DebugMon_Handler:
  b        .
  .size    DebugMon_Handler, . - DebugMon_Handler
  .weak    PendSV_Handler
  .thumb_func
PendSV_Handler:
  b        .
  .size    PendSV_Handler, . - PendSV_Handler
  .weak    SysTick_Handler
  .thumb_func
SysTick_Handler:
  b        .
  .size    SysTick_Handler, . - SysTick_Handler

@ ==== 默认设备 IRQ (weak alias to Default_Handler) ====
@ 60 个 STM32F103RC 设备 IRQ 都通过 .thumb_set 弱别名指向 Default_Handler
@ C/Zig 端覆盖某个 IRQ handler 时，链接器自动选择强符号；未覆盖的停在这里
  .section .text.Default_Handler, "ax", %progbits
  .weak    Default_Handler
  .thumb_func
Default_Handler:
  b        .
  .size    Default_Handler, . - Default_Handler

  .weak    WWDG_IRQHandler
  .thumb_set WWDG_IRQHandler, Default_Handler
  .weak    PVD_IRQHandler
  .thumb_set PVD_IRQHandler, Default_Handler
  .weak    TAMPER_IRQHandler
  .thumb_set TAMPER_IRQHandler, Default_Handler
  .weak    RTC_IRQHandler
  .thumb_set RTC_IRQHandler, Default_Handler
  .weak    FLASH_IRQHandler
  .thumb_set FLASH_IRQHandler, Default_Handler
  .weak    RCC_IRQHandler
  .thumb_set RCC_IRQHandler, Default_Handler
  .weak    EXTI0_IRQHandler
  .thumb_set EXTI0_IRQHandler, Default_Handler
  .weak    EXTI1_IRQHandler
  .thumb_set EXTI1_IRQHandler, Default_Handler
  .weak    EXTI2_IRQHandler
  .thumb_set EXTI2_IRQHandler, Default_Handler
  .weak    EXTI3_IRQHandler
  .thumb_set EXTI3_IRQHandler, Default_Handler
  .weak    EXTI4_IRQHandler
  .thumb_set EXTI4_IRQHandler, Default_Handler
  .weak    DMA1_Channel1_IRQHandler
  .thumb_set DMA1_Channel1_IRQHandler, Default_Handler
  .weak    DMA1_Channel2_IRQHandler
  .thumb_set DMA1_Channel2_IRQHandler, Default_Handler
  .weak    DMA1_Channel3_IRQHandler
  .thumb_set DMA1_Channel3_IRQHandler, Default_Handler
  .weak    DMA1_Channel4_IRQHandler
  .thumb_set DMA1_Channel4_IRQHandler, Default_Handler
  .weak    DMA1_Channel5_IRQHandler
  .thumb_set DMA1_Channel5_IRQHandler, Default_Handler
  .weak    DMA1_Channel6_IRQHandler
  .thumb_set DMA1_Channel6_IRQHandler, Default_Handler
  .weak    DMA1_Channel7_IRQHandler
  .thumb_set DMA1_Channel7_IRQHandler, Default_Handler
  .weak    ADC1_2_IRQHandler
  .thumb_set ADC1_2_IRQHandler, Default_Handler
  .weak    USB_HP_CAN1_TX_IRQHandler
  .thumb_set USB_HP_CAN1_TX_IRQHandler, Default_Handler
  .weak    USB_LP_CAN1_RX0_IRQHandler
  .thumb_set USB_LP_CAN1_RX0_IRQHandler, Default_Handler
  .weak    CAN1_RX1_IRQHandler
  .thumb_set CAN1_RX1_IRQHandler, Default_Handler
  .weak    CAN1_SCE_IRQHandler
  .thumb_set CAN1_SCE_IRQHandler, Default_Handler
  .weak    EXTI9_5_IRQHandler
  .thumb_set EXTI9_5_IRQHandler, Default_Handler
  .weak    TIM1_BRK_IRQHandler
  .thumb_set TIM1_BRK_IRQHandler, Default_Handler
  .weak    TIM1_UP_IRQHandler
  .thumb_set TIM1_UP_IRQHandler, Default_Handler
  .weak    TIM1_TRG_COM_IRQHandler
  .thumb_set TIM1_TRG_COM_IRQHandler, Default_Handler
  .weak    TIM1_CC_IRQHandler
  .thumb_set TIM1_CC_IRQHandler, Default_Handler
  .weak    TIM2_IRQHandler
  .thumb_set TIM2_IRQHandler, Default_Handler
  .weak    TIM3_IRQHandler
  .thumb_set TIM3_IRQHandler, Default_Handler
  .weak    TIM4_IRQHandler
  .thumb_set TIM4_IRQHandler, Default_Handler
  .weak    I2C1_EV_IRQHandler
  .thumb_set I2C1_EV_IRQHandler, Default_Handler
  .weak    I2C1_ER_IRQHandler
  .thumb_set I2C1_ER_IRQHandler, Default_Handler
  .weak    I2C2_EV_IRQHandler
  .thumb_set I2C2_EV_IRQHandler, Default_Handler
  .weak    I2C2_ER_IRQHandler
  .thumb_set I2C2_ER_IRQHandler, Default_Handler
  .weak    SPI1_IRQHandler
  .thumb_set SPI1_IRQHandler, Default_Handler
  .weak    SPI2_IRQHandler
  .thumb_set SPI2_IRQHandler, Default_Handler
  .weak    USART1_IRQHandler
  .thumb_set USART1_IRQHandler, Default_Handler
  .weak    USART2_IRQHandler
  .thumb_set USART2_IRQHandler, Default_Handler
  .weak    USART3_IRQHandler
  .thumb_set USART3_IRQHandler, Default_Handler
  .weak    EXTI15_10_IRQHandler
  .thumb_set EXTI15_10_IRQHandler, Default_Handler
  .weak    RTCAlarm_IRQHandler
  .thumb_set RTCAlarm_IRQHandler, Default_Handler
  .weak    USBWakeUp_IRQHandler
  .thumb_set USBWakeUp_IRQHandler, Default_Handler
  .weak    TIM8_BRK_IRQHandler
  .thumb_set TIM8_BRK_IRQHandler, Default_Handler
  .weak    TIM8_UP_IRQHandler
  .thumb_set TIM8_UP_IRQHandler, Default_Handler
  .weak    TIM8_TRG_COM_IRQHandler
  .thumb_set TIM8_TRG_COM_IRQHandler, Default_Handler
  .weak    TIM8_CC_IRQHandler
  .thumb_set TIM8_CC_IRQHandler, Default_Handler
  .weak    ADC3_IRQHandler
  .thumb_set ADC3_IRQHandler, Default_Handler
  .weak    FSMC_IRQHandler
  .thumb_set FSMC_IRQHandler, Default_Handler
  .weak    SDIO_IRQHandler
  .thumb_set SDIO_IRQHandler, Default_Handler
  .weak    TIM5_IRQHandler
  .thumb_set TIM5_IRQHandler, Default_Handler
  .weak    SPI3_IRQHandler
  .thumb_set SPI3_IRQHandler, Default_Handler
  .weak    UART4_IRQHandler
  .thumb_set UART4_IRQHandler, Default_Handler
  .weak    UART5_IRQHandler
  .thumb_set UART5_IRQHandler, Default_Handler
  .weak    TIM6_IRQHandler
  .thumb_set TIM6_IRQHandler, Default_Handler
  .weak    TIM7_IRQHandler
  .thumb_set TIM7_IRQHandler, Default_Handler
  .weak    DMA2_Channel1_IRQHandler
  .thumb_set DMA2_Channel1_IRQHandler, Default_Handler
  .weak    DMA2_Channel2_IRQHandler
  .thumb_set DMA2_Channel2_IRQHandler, Default_Handler
  .weak    DMA2_Channel3_IRQHandler
  .thumb_set DMA2_Channel3_IRQHandler, Default_Handler
  .weak    DMA2_Channel4_5_IRQHandler
  .thumb_set DMA2_Channel4_5_IRQHandler, Default_Handler
