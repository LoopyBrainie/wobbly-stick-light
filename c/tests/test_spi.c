/**
 * @file    test_spi.c
 * @brief   Phase B —— SPI1 loopback 验证
 *
 * == 硬件接线 ==
 *   1 根杜邦线: PA7 (MOSI)  ↔  PA6 (本测试夹具期间临时回退为 MISO 浮动输入)
 *
 * == 临时反转约定 ==
 *   本项目 PA6 在生产路径上是软件 CS(led_pov.c BSRR bit-bang 控制),不是 MISO。
 *   Phase B 的测试夹具生命周期内(test_spi_loopback_blocking / _dma)将 PA6
 *   临时回退到 floating input (CNF=01, MODE=00) 充当 SPI1_MISO,函数结束还原为
 *   GP push-pull 50MHz (CNF=00, MODE=11)。**所有临时反转逻辑全在本文件**,
 *   led_pov.c 生产代码保持纯净。
 *
 * == 已知缺陷 / 限制 ==
 *   - Phase B 验证是 **静态观察** SPI1 的发收能力,不验证 LED 驱动芯片的实际协议。
 *     LED 驱动芯片(从器件)有 TI/STM 专有时序要求(TLC5940/类似),这里只测主模式。
 *   - Phase B2 的 `while (g_spi_dma_done == 0)` 是真轮询 ISR 改写的 volatile,
 *     非 CLAUDE.md 禁用的"空循环优化屏障"。
 */
#include "board.h"
#include "led_pov.h"

/* === SysTick 1ms 计数 (来自 it.c 的全局,g_systick_ms 单调递增) === */
extern volatile uint32_t g_systick_ms;

/* ============================================================ *
 * Phase B1 — Blocking polled loopback
 * ============================================================ */

/* B1 步骤标记 + 结果寄存器 (probe-rs read 可观察) */
volatile uint32_t g_spi_test_phase     = 0;          /* 0=init, 1=tx, 2=rx, 3=match */
volatile uint8_t  g_spi_test_tx[3]     = { 0x55, 0xAA, 0xF0 };
volatile uint8_t  g_spi_test_rx[3]     = { 0 };

/**
 * @brief  SPI1 单字节阻塞发送(本地副本,因 led_pov.c::spi1_send_byte 是 static inline)
 */
static inline void local_spi1_send_byte(uint8_t b) {
    while ((SPI1->SR & SPI_SR_TXE) == 0) { /* spin */ }
    *((__IO uint8_t *)&SPI1->DR) = b;
    while ((SPI1->SR & SPI_SR_RXNE) == 0) { /* spin */ }
    (void)SPI1->DR;
    while ((SPI1->SR & SPI_SR_BSY) != 0) { /* spin */ }
}

/**
 * @brief  B1: blocking polled loopback,验证 SPI1 peripheral + pin mux 通
 * @return 无;结果在 g_spi_test_phase + g_spi_test_rx[]
 */
void test_spi_loopback_blocking(void) {
    g_spi_test_phase = 0;
    led_pov_init();       /* Phase A pin mux 这里生效 */

    /* === 测试夹具生命周期:把 PA6 临时回退为 floating input 当 MISO === */
    GPIOA->CRL = (GPIOA->CRL & ~(0xFu << 24)) | (0x4u << 24);

    /* 短等待 (≥1 ms)—— 让 pin mux 同步稳定,SysTick 1ms tick 已工作。
     * 这是**真轮询 volatile**,读 g_systick_ms 的值作了 < 比较,合法。 */
    uint32_t t0 = g_systick_ms;
    while ((g_systick_ms - t0) < 1U) { /* 见上面 */ }

    for (uint8_t i = 0; i < 3; i++) {
        g_spi_test_phase = 1;
        local_spi1_send_byte(g_spi_test_tx[i]);    /* poll-driven,returns when BSY=0 */
        g_spi_test_phase = 2;
        g_spi_test_rx[i] = (uint8_t)SPI1->DR;      /* 读最近一字节的回环 RX */
    }
    g_spi_test_phase = 3;

    /* === 测试夹具结束:把 PA6 还原为 CS push-pull === */
    GPIOA->CRL = (GPIOA->CRL & ~(0xFu << 24)) | (0x3u << 24);
}

/* ============================================================ *
 * Phase B2 — DMA-driven loopback (POV 实际生产路径)
 * ============================================================ */

/* B2 状态寄存器 */
volatile uint8_t  g_spi_dma_rx[3]  = { 0 };
volatile uint32_t g_spi_dma_done   = 0;

/**
 * DMA1_Channel2 (SPI1_RX) 中断: copy complete → 置 g_spi_dma_done
 *
 * 强符号覆盖 startup.s 中 weak 默认 handler (Default_Handler)。
 */
void DMA1_Channel2_IRQHandler(void) {
    /* Note: 这里不调用 led_pov.c 的任何函数,免得污染生产路径 */
    if (DMA1->ISR & DMA_ISR_TCIF2) {
        DMA1->IFCR = DMA_IFCR_CTCIF2;   /* 写 1 清 TCIF2 */
        g_spi_dma_done = 1;
    }
}

/**
 * @brief  B2: DMA loopback, 验证 SPI1 + DMA1 ch3 TX + ch2 RX + NVIC 整链路
 * @return 无; 等待 done busy-poll
 */
void test_spi_loopback_dma(void) {
    g_spi_dma_done = 0;

    /* 0) 测试夹具:PA6 临时回退为 floating input 当 MISO */
    GPIOA->CRL = (GPIOA->CRL & ~(0xFu << 24)) | (0x4u << 24);

    /* 1) DMA1 时钟使能 (AHB) */
    RCC->AHBENR |= RCC_AHBENR_DMA1EN;
    (void)RCC->AHBENR;

    /* 2) DMA1_Channel3 (SPI1_TX):memory → peripheral, 8 bit, MINC enable */
    DMA1_Channel3->CCR  = 0;
    DMA1_Channel3->CCR  = DMA_CCR_DIR      /* read from memory (memory → periph) */
                        | DMA_CCR_MINC     /* memory pointer increment */
                        | DMA_CCR_TCIE;    /* transfer-complete IRQ enable */
    DMA1_Channel3->CPAR  = (uint32_t)&SPI1->DR;
    DMA1_Channel3->CMAR  = (uint32_t)g_spi_test_tx;
    DMA1_Channel3->CNDTR = 3;

    /* 3) DMA1_Channel2 (SPI1_RX):peripheral → memory, 8 bit, MINC enable */
    DMA1_Channel2->CCR  = 0;
    DMA1_Channel2->CCR  = DMA_CCR_MINC | DMA_CCR_TCIE;  /* DIR=0 = read from periph */
    DMA1_Channel2->CPAR  = (uint32_t)&SPI1->DR;
    DMA1_Channel2->CMAR  = (uint32_t)g_spi_dma_rx;
    DMA1_Channel2->CNDTR = 3;

    /* 4) SPI1 CR2: 开 TX/RX DMA 请求 (注意:必须先于 DMA channel EN) */
    SPI1->CR2 = SPI_CR2_TXDMAEN | SPI_CR2_RXDMAEN;

    /* 5) NVIC: DMA1_Channel2 IRQ (RX 完整代表整次传输完成) */
    NVIC->ISER[DMA1_Channel2_IRQn >> 5] = (1U << (DMA1_Channel2_IRQn & 0x1Fu));
    NVIC->IP[DMA1_Channel2_IRQn] = 11U << 4U;

    /* 6) 启动 DMA 双通道 */
    DMA1_Channel2->CCR |= DMA_CCR_EN;
    DMA1_Channel3->CCR |= DMA_CCR_EN;

    /* 7) 等 done —— 真轮询 ISR 改写的 volatile, 合法 */
    while (g_spi_dma_done == 0) { /* spin */ }

    /* 8) 测试夹具结束:还原 PA6 为 CS push-pull */
    GPIOA->CRL = (GPIOA->CRL & ~(0xFu << 24)) | (0x3u << 24);
}
