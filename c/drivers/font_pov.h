/**
 * @file    font_pov.h
 * @brief   摇摇棒字模数据 —— 3 行 × 48 列
 *
 * == 数据布局 ==
 *   font[row][col] 中：
 *     - row = 0 → 该像素点为蓝色（L 字母的列在该行有非零值）
 *     - row = 1 → 绿色（K 字母）
 *     - row = 2 → 红色（M 字母）
 *     - col 0..47 共 48 列
 *
 *   每字节取值（由 led_pov.c 的 LEDSHOW() 解码）：
 *     POV_COLOR_OFF    = 0x00 → 全灭
 *     POV_COLOR_BLUE   = 0x80 → 该列 8 个 LED 全亮蓝色
 *     POV_COLOR_GREEN  = 0x08 → 该列 8 个 LED 全亮绿色
 *     POV_COLOR_RED    = 0x01 → 该列 8 个 LED 全亮红色
 *     POV_COLOR_YELLOW = 0x09 → 黄（绿+红）
 *
 * == 本次任务要求 ==
 *   - 单面 72 颗 LED（6 cat × 12 LED/段）
 *   - 显示内容包含 "LKM" 三个字母
 *   - 颜色: L=蓝 K=绿 M=红
 *   - 字模尺寸: 48 列（与 car2025_final 一致）
 *
 * == 字模设计建议 ==
 *   48 列划分给 L/K/M 三个字母，每个字母 16 列：
 *     L: col  0..15
 *     K: col 16..31
 *     M: col 32..47
 *   列内 8 bit 横向位图（每个 bit 对应该 LED 灯条上的 1 颗 LED），
 *   列与列沿棍身纵向分布 —— 摆动时 8 bit 在视觉上呈现为"高度信息"。
 *
 * == TODO ==
 *   实际字模（bit data）需要按上述 16×8 像素手绘 L/K/M 三字母的点阵后填入。
 *   当前仅声明 extern，字模数据文件 font_pov.c 暂留空，等用户提供字体来源
 *   （手画 / 字模生成工具 / 从其他字体转换）后再生成数据。
 */
#ifndef WOBBLY_FONT_POV_H
#define WOBBLY_FONT_POV_H

#include <stdint.h>
#include "board.h"

#ifdef __cplusplus
extern "C" {
#endif

/* === 主字模：LKM（L=蓝 K=绿 M=红） === */
extern const uint8_t FONT_LKM[POV_ROW_NUM][POV_COL_NUM];

/* === 备用字模：纯色彩虹渐变（蓝→绿→红 横向扫描） === */
extern const uint8_t FONT_RAINBOW[POV_ROW_NUM][POV_COL_NUM];

/* === 备用字模：纯红单色填充（便于校准 LED 颜色识别） === */
extern const uint8_t FONT_ALL_RED[POV_ROW_NUM][POV_COL_NUM];

#ifdef __cplusplus
}
#endif

#endif /* WOBBLY_FONT_POV_H */