/**
 * @file    led_pov.c
 * @brief   摇摇棒 POV 显示驱动 —— TIM7 + SPI1 初始化 + LEDSHOW 解码
 *
 * == 状态机 ==
 *   STOP  → init() 配置完成，TIM7 已运行但 NVIC 未使能
 *   IDLE  → start() 后，NVIC 使能，等待 tick
 *   START → tick() 每 250 us 推进 cat 0..5；cat==5 时切换下一列（共 40 列）
 *
 * == ISR 路径 ==
 *   TIM7_IRQHandler (it.c) → led_pov_tick()
 *       → LED_Loop1(s_col)    把当前 col 的 3 行字模刷进 g_LED_Show_RAM[24]
 *       → LEDSHOW(0, s_cat)   把 RAM 中当前 cat 的 4 segment 编码成 SPI 2 字节
 *       → cat/col 推进
 *
 * == 字模字节 ↔ LED 像素通道（frozen bit-domain formula） ==
 *   b = (byte >> 6) & 0x03;   // [7:6] Blue
 *   g = (byte >> 3) & 0x07;   // [5:3] Green
 *   r =  byte       & 0x07;   // [2:0] Red
 *   常量：POV_COLOR_BLUE=0x80, POV_COLOR_GREEN=0x08,
 *         POV_COLOR_RED=0x01, POV_COLOR_YELLOW=0x09
 *
 * == 移植来源 ==
 *   car2025_final/Core/Src/led_show.c
 *     - LEDSHOW()        : led_show.c:60   字节分解后通过 g_LED_MAP 串行化
 *     - LED_Loop1()      : led_show.c:133  8 bit 字模 → RAM 8 字节
 *     - 帧缓冲/扫描表    : led_show.c:41-58
 *   注意：新需求 row=0/1/2 = 蓝/绿/红（原 car2025 是 蓝/红/黄），
 *   通过 POV_ROW_COLOR 查表解决，绝不硬编码 0x80/0x01/0x09
 */
#include "board.h"
#include "led_pov.h"
#include "font_pov.h"

/* === 内部状态 ===
 *   s_font 默认指向 FONT_LKM（=L 蓝 K 绿 M 红），让 POV 上电即显示字模，
 *   顺便保证 FONT_LKM 在 .rodata 中被引用而不被 LTO GC。
 *   Zig 侧若需切换字模（如 LOOP 5 的菜单），调 led_pov_set_pattern() 覆盖。 */
static volatile led_pov_state_t s_state = LED_POV_STOP;
static volatile uint8_t          s_cat   = 0;
static volatile uint8_t          s_col   = 0;
static volatile const uint8_t   (*s_font)[POV_COL_NUM] = FONT_LKM;

/* === 异步过零围栏（Requirement J）===
 * Zig 侧 vibration_consume_clear() 触发后置 1；TIM7 ISR 在 tick 入口消费。
 * Zig 通过 extern 声明访问本符号（src/c_bridge.zig）—— 不在 led_pov.h 中导出。
 */
volatile uint8_t g_LED_key_down = 0;

/* === 6 段扫描 cat 选择序列（移植自 led_show.c:50） === */
static const uint8_t g_LED_CAT_RAM[POV_CAT_NUM] = {
    0xFB, 0xF7, 0xEF, 0xDF, 0xBF, 0x7F
};

/* === 硬件走线映射（移植自 led_show.c:55） === */
static const uint8_t g_LED_MAP[2][6] = {
    {  0, 10,  7,  4,  1,  2 },
    {  3,  6,  9, 11,  8,  5 }
};

/* === 帧缓冲（24 字节 = 4 cat × 4 byte × 3 RGB nibble = 72 LED 像素）
 *    ISR 写入故非 const                                          === */
static uint8_t g_LED_Show_RAM[24];

/* === 字模行 → 颜色通道映射（L=蓝 K=绿 M=红，定义在 board_init.c） === */
extern const uint8_t POV_ROW_COLOR[POV_ROW_NUM];

/* === 单字节 SPI 阻塞发送（内部 helper：仅寄存器读/写） === */
static inline void spi1_send_byte(uint8_t b) {
    while ((SPI1->SR & SPI_SR_TXE)   == 0) { /* spin */ }
    *((__IO uint8_t *)&SPI1->DR) = b;
    while ((SPI1->SR & SPI_SR_RXNE)  == 0) { /* spin */ }
    (void)SPI1->DR;
    while ((SPI1->SR & SPI_SR_BSY)   != 0) { /* spin */ }
}

/* === SPI1 推 3 字节（buf[0]/buf[1] data, buf[2] cat select） === */
static inline void spi1_send_3bytes(const uint8_t buf[3]) {
    POV_CS_PORT->BSRR = (uint32_t)POV_CS_PIN << 16;  /* BR6 = bit22，拉低 */
    for (uint8_t i = 0; i < 3; i++) {
        spi1_send_byte(buf[i]);
    }
    POV_CS_PORT->BSRR = POV_CS_PIN;                   /* BS6 = bit6， 拉高 */
}

/* === LEDSHOW：把当前 cat 对应的 4 个 RAM 字节 → SPI 2 字节 ===
 *
 * 字节分解（frozen bit-domain formula — Boundary E 不可修改）：
 *   b = (byte >> 6) & 0x03;   // [7:6] Blue
 *   g = (byte >> 3) & 0x07;   // [5:3] Green
 *   r =  byte       & 0x07;   // [2:0] Red
 *
 * 输入：g_LED_Show_RAM 中 cat_addr*4 起的 4 字节，每字节 8 bit =
 *       4 LED × (B2+G3+R3) 通道强度，low 3 bit = R / [5:3] = G / high 2 bit = B
 * 输出：buf[0]/buf[1] = LED P/N 端 12-bit 序列，g_LED_MAP 完成数据线交叉
 *       buf[2] = 当前 cat 选择字节（6 段扫描序列）
 */
static void LEDSHOW(uint8_t mode, uint8_t cat_addr) {
    uint8_t ram_addr;
    uint8_t i, j, tmp;
    uint8_t ram_data[12];
    uint8_t buf[3];

    buf[2] = g_LED_CAT_RAM[cat_addr];
    if (mode == 0) {
        ram_addr = (uint8_t)(cat_addr * 4);
        for (i = 0; i < 4; i++) {
            tmp = g_LED_Show_RAM[ram_addr + i];
            for (j = 0; j < 3; j++) {
                ram_data[i * 3 + j] = (uint8_t)(tmp & 0x07);
                tmp = (uint8_t)(tmp >> 3);
            }
        }
        for (i = 0; i < 2; i++) {
            buf[i] = 0;
            for (j = 0; j < 6; j++) {
                buf[i] = (uint8_t)(buf[i] >> 1);
                if (ram_data[g_LED_MAP[i][j]]) {
                    buf[i] = (uint8_t)(buf[i] | 0x80);
                }
            }
        }
    } else {
        buf[0] = 0;
        buf[1] = 0;
    }

    spi1_send_3bytes(buf);
}

/* === LED_Loop1：把当前 col 的 3 行字模写进 g_LED_Show_RAM[24] ===
 *
 * 每行 1 字节字模按位展开成 8 个 RAM 字节：
 *   bit 0 → RAM[i+0]   LED pixel #0
 *   bit 1 → RAM[i+1]   LED pixel #1
 *   ...
 *   bit 7 → RAM[i+7]   LED pixel #7
 * 每个 RAM 字节 = POV_ROW_COLOR[row]（= 0x80/0x08/0x01，bit-domain 编码）或 0x00
 * LEDSHOW 反向聚合时：b = (byte >> 6) & 0x03，把 0x80 切成 B=2/R=0/G=0
 */
static void LED_Loop1(uint8_t index) {
    for (uint8_t row = 0; row < POV_ROW_NUM; row++) {
        uint8_t tmp = s_font[row][index];
        const uint8_t color = POV_ROW_COLOR[row];
        const uint8_t base  = (uint8_t)(row * 8);
        for (uint8_t i = 0; i < 8; i++) {
            g_LED_Show_RAM[base + i] = (tmp & 0x01) ? color : POV_COLOR_OFF;
            tmp = (uint8_t)(tmp >> 1);
        }
    }
}

/* === 公开 API === */
void led_pov_init(void) {
    /* 1) SPI1 复位后再配置（保险） */
    RCC->APB2RSTR |= RCC_APB2RSTR_SPI1RST;
    RCC->APB2RSTR &= ~RCC_APB2RSTR_SPI1RST;

    /* 1a) GPIOA->CRL pin mux，让 SPI1 真正驱动 PA5/PA7
     *      本项目 SPI1 引脚映射（board.h:52-59，非标准 SPI1 全双工）：
     *        PA5 = SCK  → AF push-pull  0xB
     *        PA6 = CS   → GP push-pull  0x3 ← 软件片选，不是 MISO
     *        PA7 = MOSI → AF push-pull  0xB
     *        PA4 = 备用 → GP push-pull  0x3
     *      GPIOA->CRL[31:16] 每 4 bit 字段编码：(CNF[3:2] | MODE[1:0])
     */
    GPIOA->CRL = (GPIOA->CRL & ~0xFFFF0000u)
               | (0x3u << 16)   /* PA4 — GP push-pull 50MHz */
               | (0xBu << 20)   /* PA5 — SCK, AF push-pull 50MHz */
               | (0x3u << 24)   /* PA6 — CS, GP push-pull 50MHz */
               | (0xBu << 28);  /* PA7 — MOSI, AF push-pull 50MHz */
    POV_CS_PORT->BSRR = POV_CS_PIN;   /* CS idle high */

    /* 2) SPI1 CR1：主模式、软件 NSS、BR=001 (APB2/4 = 18 MHz)、MSB 先、空闲低、第 1 边沿 */
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
    NVIC->IP[POV_TIM_IRQn]        = 13U << 4U;
    NVIC->ISER[POV_TIM_IRQn >> 5] = (1U << (POV_TIM_IRQn & 0x1Fu));

    /* 7) 清空帧缓冲（避免上电初始态显示残影） */
    for (uint8_t i = 0; i < 24; i++) {
        g_LED_Show_RAM[i] = POV_COLOR_OFF;
    }

    s_state = LED_POV_IDLE;
    s_cat   = 0;
    s_col   = 0;
}

void led_pov_start(void) {
    NVIC->ISER[POV_TIM_IRQn >> 5] = (1U << (POV_TIM_IRQn & 0x1Fu));
    s_state = LED_POV_START;
}

void led_pov_stop(void) {
    /* 清空帧缓冲 + 推一帧空白 LEDSHOW(1, 0)：
     *   否则 595 输出寄存器保留最后一次 LEDSHOW 的数据，停机后仍有几颗 LED
     *   常亮（这是用户报告的"停下后残留几颗灯"的根因）。 */
    for (uint8_t i = 0; i < 24; i++) {
        g_LED_Show_RAM[i] = POV_COLOR_OFF;
    }
    LEDSHOW(1, 0);

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

/* === DEBUG ONLY (Diagnostic 4) ===
 *   绕过 FSM / ISR / 振动触发，直接在 foreground 写满 0x80 + 推 LEDSHOW(0,0)。
 *   验证 SPI + 595 链路本身能不能工作。 */
void led_pov_force_blue(void) {
    for (uint8_t i = 0; i < 24; i++) {
        g_LED_Show_RAM[i] = 0x80;
    }
    LEDSHOW(0, 0);
}

led_pov_state_t led_pov_get_state(void) {
    return (led_pov_state_t)s_state;
}

const uint8_t *led_pov_get_pattern(void) {
    return (const uint8_t *)s_font;
}

/* === ISR 钩子：每 250 us 由 TIM7 中断调用一次（必须极短） === */
void led_pov_tick(void) {
    /* 异步围栏检查：必须在 s_state 守门之前消费过零请求，
     * 否则 IDLE/STOP 状态下挂起的过零会延迟到下次 start */
    if (g_LED_key_down) {
        s_col = 0;
        s_cat = 0;
        g_LED_key_down = 0;
    }

    if (s_state != LED_POV_START) return;

    LED_Loop1(s_col);          /* 把当前 col 的字模刷进 RAM */
    LEDSHOW(0, s_cat);          /* 推当前 cat 的 3 字节 SPI */

    if (++s_cat >= POV_CAT_NUM) {
        s_cat = 0;
        if (++s_col >= POV_COL_NUM) {
            s_col = 0;
        }
    }
}
