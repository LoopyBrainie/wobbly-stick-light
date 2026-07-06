@ /*
@  ******************************************************************************
@  * startup_stm32f10x_hd.s — GNU AS syntax
@  *
@  * Converted from Keil ARMCC syntax for use with zig cc (clang + lld).
@  *
@  * STM32F10x High Density Devices vector table.
@  *   - Sets initial SP from _estack (defined in linker script)
@  *   - Reset_Handler → SystemInit() → main()
@  *   - All exception/interrupt handlers are [WEAK] defaults
@  ******************************************************************************
@  */

    .syntax unified
    .cpu    cortex-m3
    .thumb

@ ── Vector table (placed at flash origin by linker script) ──
    .section .vector_table, "a", %progbits
    .global __Vectors
    .type   __Vectors, %object

__Vectors:
    .word _estack                    @ 0x00: Initial stack pointer
    .word Reset_Handler              @ 0x04: Reset
    .word NMI_Handler                @ 0x08: NMI
    .word HardFault_Handler          @ 0x0C: Hard Fault
    .word MemManage_Handler          @ 0x10: MPU Fault
    .word BusFault_Handler           @ 0x14: Bus Fault
    .word UsageFault_Handler         @ 0x18: Usage Fault
    .word 0                          @ 0x1C: Reserved
    .word 0                          @ 0x20: Reserved
    .word 0                          @ 0x24: Reserved
    .word 0                          @ 0x28: Reserved
    .word SVC_Handler                @ 0x2C: SVCall
    .word DebugMon_Handler           @ 0x30: Debug Monitor
    .word 0                          @ 0x34: Reserved
    .word PendSV_Handler             @ 0x38: PendSV
    .word SysTick_Handler            @ 0x3C: SysTick

    @ External interrupts
    .word WWDG_IRQHandler            @ 0x40
    .word PVD_IRQHandler             @ 0x44
    .word TAMPER_IRQHandler          @ 0x48
    .word RTC_IRQHandler             @ 0x4C
    .word FLASH_IRQHandler           @ 0x50
    .word RCC_IRQHandler             @ 0x54
    .word EXTI0_IRQHandler           @ 0x58
    .word EXTI1_IRQHandler           @ 0x5C
    .word EXTI2_IRQHandler           @ 0x60
    .word EXTI3_IRQHandler           @ 0x64
    .word EXTI4_IRQHandler           @ 0x68
    .word DMA1_Channel1_IRQHandler   @ 0x6C
    .word DMA1_Channel2_IRQHandler   @ 0x70
    .word DMA1_Channel3_IRQHandler   @ 0x74
    .word DMA1_Channel4_IRQHandler   @ 0x78
    .word DMA1_Channel5_IRQHandler   @ 0x7C
    .word DMA1_Channel6_IRQHandler   @ 0x80
    .word DMA1_Channel7_IRQHandler   @ 0x84
    .word ADC1_2_IRQHandler          @ 0x88
    .word USB_HP_CAN1_TX_IRQHandler  @ 0x8C
    .word USB_LP_CAN1_RX0_IRQHandler @ 0x90
    .word CAN1_RX1_IRQHandler        @ 0x94
    .word CAN1_SCE_IRQHandler        @ 0x98
    .word EXTI9_5_IRQHandler         @ 0x9C
    .word TIM1_BRK_IRQHandler        @ 0xA0
    .word TIM1_UP_IRQHandler         @ 0xA4
    .word TIM1_TRG_COM_IRQHandler    @ 0xA8
    .word TIM1_CC_IRQHandler         @ 0xAC
    .word TIM2_IRQHandler            @ 0xB0
    .word TIM3_IRQHandler            @ 0xB4
    .word TIM4_IRQHandler            @ 0xB8
    .word I2C1_EV_IRQHandler         @ 0xBC
    .word I2C1_ER_IRQHandler         @ 0xC0
    .word I2C2_EV_IRQHandler         @ 0xC4
    .word I2C2_ER_IRQHandler         @ 0xC8
    .word SPI1_IRQHandler            @ 0xCC
    .word SPI2_IRQHandler            @ 0xD0
    .word USART1_IRQHandler          @ 0xD4
    .word USART2_IRQHandler          @ 0xD8
    .word USART3_IRQHandler          @ 0xDC
    .word EXTI15_10_IRQHandler       @ 0xE0
    .word RTCAlarm_IRQHandler        @ 0xE4
    .word USBWakeUp_IRQHandler       @ 0xE8
    .word TIM8_BRK_IRQHandler        @ 0xEC
    .word TIM8_UP_IRQHandler         @ 0xF0
    .word TIM8_TRG_COM_IRQHandler    @ 0xF4
    .word TIM8_CC_IRQHandler         @ 0xF8
    .word ADC3_IRQHandler            @ 0xFC
    .word FSMC_IRQHandler            @ 0x100
    .word SDIO_IRQHandler            @ 0x104
    .word TIM5_IRQHandler            @ 0x108
    .word SPI3_IRQHandler            @ 0x10C
    .word UART4_IRQHandler           @ 0x110
    .word UART5_IRQHandler           @ 0x114
    .word TIM6_IRQHandler            @ 0x118
    .word TIM7_IRQHandler            @ 0x11C
    .word DMA2_Channel1_IRQHandler   @ 0x120
    .word DMA2_Channel2_IRQHandler   @ 0x124
    .word DMA2_Channel3_IRQHandler   @ 0x128
    .word DMA2_Channel4_5_IRQHandler @ 0x12C

    .size __Vectors, . - __Vectors

@ ── Reset Handler ──
    .section .text.Reset_Handler, "ax", %progbits
    .global Reset_Handler
    .type   Reset_Handler, %function

Reset_Handler:
    @ Copy .data section from flash to SRAM
    ldr r0, =_sidata
    ldr r1, =_sdata
    ldr r2, =_edata
1:  cmp r1, r2
    bge 2f
    ldr r3, [r0], #4
    str r3, [r1], #4
    b   1b

2:  @ Zero-fill .bss section
    ldr r0, =_sbss
    ldr r1, =_ebss
    mov r2, #0
3:  cmp r0, r1
    bge 4f
    str r2, [r0], #4
    b   3b

4:  @ Call SystemInit (clock tree), then main()
    bl  SystemInit
    bl  main

    @ main() should never return; trap if it does
    b   .

    .size Reset_Handler, . - Reset_Handler

@ ── Default Exception Handlers ──
    .macro  default_handler name
    .section .text.\name, "ax", %progbits
    .thumb_func
    .weak   \name
    .type   \name, %function
\name:
    b   .
    .size   \name, . - \name
    .endm

    default_handler NMI_Handler
    default_handler HardFault_Handler
    default_handler MemManage_Handler
    default_handler BusFault_Handler
    default_handler UsageFault_Handler
    default_handler SVC_Handler
    default_handler DebugMon_Handler
    default_handler PendSV_Handler
    default_handler SysTick_Handler

@ ── Default IRQ Handlers ──
    default_handler WWDG_IRQHandler
    default_handler PVD_IRQHandler
    default_handler TAMPER_IRQHandler
    default_handler RTC_IRQHandler
    default_handler FLASH_IRQHandler
    default_handler RCC_IRQHandler
    default_handler EXTI0_IRQHandler
    default_handler EXTI1_IRQHandler
    default_handler EXTI2_IRQHandler
    default_handler EXTI3_IRQHandler
    default_handler EXTI4_IRQHandler
    default_handler DMA1_Channel1_IRQHandler
    default_handler DMA1_Channel2_IRQHandler
    default_handler DMA1_Channel3_IRQHandler
    default_handler DMA1_Channel4_IRQHandler
    default_handler DMA1_Channel5_IRQHandler
    default_handler DMA1_Channel6_IRQHandler
    default_handler DMA1_Channel7_IRQHandler
    default_handler ADC1_2_IRQHandler
    default_handler USB_HP_CAN1_TX_IRQHandler
    default_handler USB_LP_CAN1_RX0_IRQHandler
    default_handler CAN1_RX1_IRQHandler
    default_handler CAN1_SCE_IRQHandler
    default_handler EXTI9_5_IRQHandler
    default_handler TIM1_BRK_IRQHandler
    default_handler TIM1_UP_IRQHandler
    default_handler TIM1_TRG_COM_IRQHandler
    default_handler TIM1_CC_IRQHandler
    default_handler TIM2_IRQHandler
    default_handler TIM3_IRQHandler
    default_handler TIM4_IRQHandler
    default_handler I2C1_EV_IRQHandler
    default_handler I2C1_ER_IRQHandler
    default_handler I2C2_EV_IRQHandler
    default_handler I2C2_ER_IRQHandler
    default_handler SPI1_IRQHandler
    default_handler SPI2_IRQHandler
    default_handler USART1_IRQHandler
    default_handler USART2_IRQHandler
    default_handler USART3_IRQHandler
    default_handler EXTI15_10_IRQHandler
    default_handler RTCAlarm_IRQHandler
    default_handler USBWakeUp_IRQHandler
    default_handler TIM8_BRK_IRQHandler
    default_handler TIM8_UP_IRQHandler
    default_handler TIM8_TRG_COM_IRQHandler
    default_handler TIM8_CC_IRQHandler
    default_handler ADC3_IRQHandler
    default_handler FSMC_IRQHandler
    default_handler SDIO_IRQHandler
    default_handler TIM5_IRQHandler
    default_handler SPI3_IRQHandler
    default_handler UART4_IRQHandler
    default_handler UART5_IRQHandler
    default_handler TIM6_IRQHandler
    default_handler TIM7_IRQHandler
    default_handler DMA2_Channel1_IRQHandler
    default_handler DMA2_Channel2_IRQHandler
    default_handler DMA2_Channel3_IRQHandler
    default_handler DMA2_Channel4_5_IRQHandler

    .end
