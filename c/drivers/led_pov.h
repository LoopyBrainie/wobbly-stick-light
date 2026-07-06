/**
 * @file    led_pov.h
 * @brief   摇摇棒 POV 显示驱动 —— 状态机 + 刷新节拍 + 字模注入
 *
 * 移植自 car2025_final/Core/Src/led_show.c，封装以下细节为内部 opaque 状态：
 *   - g_LED_Show_RAM[24] 帧缓冲（24 字节 × 3 位/字节 = 72 LED 像素）
 *   - g_LED_CAT_RAM[6]    段选扫描序列
 *   - g_LED_MAP[2][6]     硬件走线映射
 *   - g_ShowData[3][48]   字库（已抽出到 font_pov.h，由 led_pov_set_pattern 注入）
 *
 * == 刷新流程（与 car2025_final 一致） ==
 *   1. TIM7 每 250 us 触发一次 ISR → led_pov_tick()
 *   2. tick 推进 cat 0..5；cat==5 时切换下一列（共 48 列）
 *   3. 每 tick 调用一次 LEDSHOW(cat) 通过 SPI1 推 3 字节
 *   4. 一帧 = 48 列 × 6 cat = 240 tick ≈ 60 ms
 *
 * == 调用契约 ==
 *   - led_pov_init()       : 上电一次，由 SysInit 调用
 *   - led_pov_tick()       : TIM7 ISR 调用（c/startup/stm32f1xx_it.c 内）
 *   - led_pov_on_vibration(): 振动/霍尔触发后由 vibration.c 调用
 *   - led_pov_set_pattern(): 主循环或命令注入字模
 *   - led_pov_start/stop() : 启动 / 暂停刷新（保留 car2025 行为）
 */
#ifndef WOBBLY_LED_POV_H
#define WOBBLY_LED_POV_H

#include <stdint.h>
#include "board.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LED_POV_STOP  = 0,
    LED_POV_IDLE  = 1,
    LED_POV_START = 2,
} led_pov_state_t;

/**
 * @brief  初始化：清空帧缓冲、配置 SPI1 CS 引脚、配置 TIM7、设置默认字模
 * @note   必须先调用 board_init() 完成系统时钟与 GPIO 时钟使能
 */
void led_pov_init(void);

/**
 * @brief  启动 POV 刷新：使能 TIM7 中断，状态机进入 START
 */
void led_pov_start(void);

/**
 * @brief  停止 POV 刷新：关闭 TIM7 中断，状态机回到 STOP
 */
void led_pov_stop(void);

/**
 * @brief  注入字模（指向 font_pov.h 中的 48 × 3 字节数据）
 * @param  font  指向 POV_ROW_NUM × POV_COL_NUM = 3 × 48 字节的二维字模
 *              必须为静态存储（const），否则 tick 中访问会越界
 *
 * == 字模字节到 LED 颜色的映射（由 led_pov.c 内部完成） ==
 *   byte == POV_COLOR_BLUE  → 该列 8 个像素都点亮蓝色通道
 *   byte == POV_COLOR_GREEN → 绿色通道
 *   byte == POV_COLOR_RED   → 红色通道
 *   byte == POV_COLOR_YELLOW→ 红+绿
 *   其他 → 全灭
 *
 * TODO: 移植 led_show.c 的 LEDSHOW() 解码逻辑时，把 LED_Loop1 改成查表方式
 */
void led_pov_set_pattern(const uint8_t font[POV_ROW_NUM][POV_COL_NUM]);

/* === 字模行 → 像素颜色通道映射表（实现者必须实现并使用） === */
/**
 * 把字模的 row 索引映射成 POV_COLOR_* 通道值。
 * 例（用户需求: L=蓝 K=绿 M=红）：
 *   const uint8_t POV_ROW_COLOR[POV_ROW_NUM] = {
 *       POV_COLOR_BLUE, POV_COLOR_GREEN, POV_COLOR_RED
 *   };
 * 实现者务必使用此表查询，绝不可照搬 car2025 的 `0x80/0x01/0x09` 硬编码——
 * car2025 的映射是 row=0/1/2 = 蓝/红/黄，与新需求 row=0/1/2 = 蓝/绿/红 不一致。
 */
extern const uint8_t POV_ROW_COLOR[POV_ROW_NUM];

/**
 * @brief  振动 / 过零复位：把当前列、cat 全部归零，让下一帧从 col=0 开始
 * @note   由 vibration.c 在确认触发后调用；内部仅做标志位 + 重置
 */
void led_pov_on_vibration(void);

/**
 * @brief  TIM7 ISR 钩子：推进一步 cat 切换并发送 3 字节 SPI 帧
 * @note   必须在 TIM7 中断服务程序中调用，禁止在主循环调用
 */
void led_pov_tick(void);

/**
 * @brief  查询当前状态机（调试 / 命令解析用）
 */
led_pov_state_t led_pov_get_state(void);

/**
 * @brief  获取当前注入的字模指针（调试用，可为 NULL）
 */
const uint8_t *led_pov_get_pattern(void);

#ifdef __cplusplus
}
#endif

#endif /* WOBBLY_LED_POV_H */