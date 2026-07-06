/**
 * @file    led_pov.c
 * @brief   摇摇棒 POV 显示驱动 —— TIM7 + SPI1 寄存器初始化 + 极短 ISR 钩子
 *
 * == 状态机 ==
 *   STOP  → init() 配置完成，TIM7 已运行但 NVIC 未使能
 *   IDLE  → start() 后，NVIC 使能，等待 tick
 *   START → tick() 每 250 us 推进一帧 1/240
 *
 * == ISR 路径 ==
 *   TIM7_IRQHandler (it.c) → led_pov_tick() → 推 3 字节 SPI（占位 cat 扫描）
 */
#include "board.h"
#include "led_pov.h"

/* === 内部状态 === */
static volatile led_pov_state_t s_state     = LED_POV_STOP;
static volatile uint8_t          s_cat       = 0;
static volatile uint8_t          s_col       = 0;
static volatile const uint8_t   (*s_font)[POV_COL_NUM] = (const uint8_t (*)[POV_COL_NUM])0;

/* === 6 段扫描的 cat 选择序列（移植自 car2025_final/Core/Src/led_show.c:42） === */
static const uint8_t s_cat_pat[POV_CAT_NUM] = { 0xFB, 0xF7, 0xEF, 0xDF, 0xBF, 0x7F };

/* === 字模映射表（用户需求 L=蓝 K=绿 M=红） === */
extern const uint8_t POV_ROW_COLOR[POV_ROW_NUM];   /* 定义在 board_init.c */

/* === 单字节 SPI 阻塞发送（内部 helper：仅寄存器读/写） === */
static inline void spi1_send_byte(uint8_t b) {
    while ((SPI1->SR & SPI_SR_TXE) == 0) { /* spin */ }
    *((__IO uint8_t *)&SPI1->DR) = b;
    while ((SPI1->SR & SPI_SR_RXNE) == 0) { /* spin */ }
    (void)SPI1->DR;
    while ((SPI1->SR & SPI_SR_BSY) != 0) { /* spin */ }
}

/* === SPI1 推 3 字节（buf[0]/buf[1] data, buf[2] cat select） === */
static inline void spi1_send_3bytes(const uint8_t buf[3]) {
    POV_CS_PORT->BSRR = (uint32_t)POV_CS_PIN << 16;  /* BR6 = bit22, 拉低 */
    for (uint8_t i = 0; i < 3; i++) {
        spi1_send_byte(buf[i]);
    }
    POV_CS_PORT->BSRR = POV_CS_PIN;                   /* BS6 = bit6,  拉高 */
}

/* === 公开 API === */
void led_pov_init(void) {
    /* 1) SPI1 复位后再配置（保险） */
    RCC->APB2RSTR |= RCC_APB2RSTR_SPI1RST;
    RCC->APB2RSTR &= ~RCC_APB2RSTR_SPI1RST;

    /* 2) SPI1 CR1：主模式、软件 NSS、BR=001 (APB2/4 = 18 MHz)、MSB 先、空闲低、第 1 边沿采样 */
    SPI1->CR1 = SPI_CR1_MSTR | SPI_CR1_SSI | SPI_CR1_SSM |
                (0x1u << SPI_CR1_BR_Pos);
    /* 3) SPI1 CR2：默认（全 DMA/中断关） */
    SPI1->CR2 = 0;
    /* 4) 最后才置 SPE = 1 */
    SPI1->CR1 |= SPI_CR1_SPE;

    /* 5) TIM7 时基：72 MHz / (3599+1) = 20 kHz; ARR=4 → 5 分频 → 4 kHz → 250 us 周期 */
    POV_TIM_CLK_EN();
    POV_TIM->PSC  = POV_TIM_PRESCALER;   /* 3599 */
    POV_TIM->ARR  = POV_TIM_AUTORELOAD;  /* 4 */
    POV_TIM->CNT  = 0U;
    POV_TIM->EGR  = TIM_EGR_UG;          /* 装载 PSC/ARR（必须在 CR1=CEN 之前触发 UE） */
    POV_TIM->DIER = TIM_DIER_UIE;        /* 开 update 中断 */
    POV_TIM->CR1  = TIM_CR1_CEN;         /* 启动计数（此时 NVIC 还未使能） */

    /* 6) NVIC: IP[55] = 13<<4; ISER[1] |= bit(55-32)=23 */
    NVIC->IP[POV_TIM_IRQn]      = 13U << 4U;
    NVIC->ISER[POV_TIM_IRQn >> 5] = (1U << (POV_TIM_IRQn & 0x1Fu));

    s_state = LED_POV_IDLE;
    s_cat   = 0;
    s_col   = 0;
}

void led_pov_start(void) {
    NVIC->ISER[POV_TIM_IRQn >> 5] = (1U << (POV_TIM_IRQn & 0x1Fu));
    s_state = LED_POV_START;
}

void led_pov_stop(void) {
    NVIC->ICER[POV_TIM_IRQn >> 5] = (1U << (POV_TIM_IRQn & 0x1Fu));
    s_state = LED_POV_STOP;
}

void led_pov_set_pattern(const uint8_t font[POV_ROW_NUM][POV_COL_NUM]) {
    s_font = font;
}

void led_pov_on_vibration(void) {
    s_cat = 0;
    s_col = 0;
}

led_pov_state_t led_pov_get_state(void) {
    return (led_pov_state_t)s_state;
}

const uint8_t *led_pov_get_pattern(void) {
    return (const uint8_t *)s_font;
}

/* === ISR 钩子：每 250 us 由 TIM7 中断调用一次（必须极短） === */
void led_pov_tick(void) {
    if (s_state != LED_POV_START) return;

    /* 简化版：每 tick 推 1 字节（仅 cat select），不读字模
     * 完整 LEDSHOW 解码在 Phase 5 从 car2025_final/Core/Src/led_show.c 移植 */
    uint8_t buf[3] = { 0x00, 0x00, s_cat_pat[s_cat] };
    spi1_send_3bytes(buf);

    if (++s_cat >= POV_CAT_NUM) {
        s_cat = 0;
        if (++s_col >= POV_COL_NUM) {
            s_col = 0;
        }
    }
}
