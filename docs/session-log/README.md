# 会话记录 — 2026-07-06

> 摇摇棒固件项目（wobbly-stick-light）首日全栈开发链路打通记录
>
> 记录本次对话中**无法被后期代码/git 自动还原**的事实：硬件连接、工具链选择、踩坑点、调试技巧。

---

## 1. 硬件环境（实测）

| 项目 | 规格 | 备注 |
|------|------|------|
| MCU | STM32F103RCT6 | Cortex-M3, 72MHz, 256KB Flash, 48KB SRAM |
| 调试器 | BUPT CMSIS-DAP v2025 | USB VID:PID `0483:52a4`, probe-rs 开箱即用无需驱动 |
| 串行接口 | SWD | probe-rs 自动检测 |
| Keil 包 | `Keil.STM32F1xx_DFP.2.3.0` | RTE 已配置但本流程未使用 Keil 编译 |

---

## 2. 工具链（实测，非默认推荐）

**完全使用 Zig 内置工具链，零额外安装。**

| 工具 | 来源 | 用途 |
|------|------|------|
| `zig cc` (Clang) | Zig 0.16.0 内置 | C/ASM 交叉编译 |
| `lld` | Zig 0.16.0 内置 | 链接 |
| `probe-rs` 0.31.0 | 全局安装 | 烧录 + 调试 |
| CMSIS-DAP | 物理调试器 | SWD 协议 |

**不需要**：ARM GNU Toolchain（arm-none-eabi-gcc）、Segger J-Link、OpenOCD。

---

## 3. 项目目录结构（最终态）

```
wobbly-stick-light/
├── build.zig                  ← Cortex-M3 交叉编译配置（Zig 0.16 Module API）
├── build.zig.zon              ← Zig 包清单
├── src/
│   ├── main.zig               ← 固件入口，PB0 LED 翻转 + heartbeat
│   └── root.zig               ← 板级常量（暂时未使用）
├── c/
│   ├── startup/
│   │   └── startup_stm32f10x_hd.s   ← GNU AS 启动（向量表 + Reset_Handler）
│   ├── hal/
│   │   ├── stm32f10x.h              ← 最小寄存器存根（自写，无外部依赖）
│   │   └── system_stm32f10x.c       ← 时钟初始化（从 RTE 复制）
│   ├── ld/
│   │   └── stm32f103rct6.ld         ← 手写链接脚本
│   └── drivers/                     ← 空，待填充
├── RTE/                       ← Keil 教程工程（保留为参考）
├── docs/
│   └── session-log/           ← 本次会话记录
├── .claude/settings.local.json
├── CLAUDE.md
├── .gitignore
└── (uvprojx)                  ← Keil 工程入口
```

---

## 4. 关键编译参数

```
target: thumb-freestanding-eabi
cpu_model: cortex_m3
optimize: ReleaseSmall      ← 必须，Debug 会让 Flash 溢出 58KB
zig cc flags: -mcpu=cortex-m3 -mthumb -DSTM32F10X_HD -DUSE_STDPERIPH_DRIVER
```

**编译命令**：
```sh
zig build -Doptimize=ReleaseSmall
```

**烧录命令**：
```sh
probe-rs run zig-out/bin/wobbly-stick-light --chip STM32F103RC
```

---

## 5. 关键踩坑点（已被解决，未来需知）

### 5.1 Zig 0.16 API 迁移

**问题**：`exe.addAssemblyFile()` 在 Zig 0.16 已移至 `exe.root_module.addAssemblyFile()`。
**教训**：所有嵌入式教程的 `exe.addAssemblyFile()` 示例已过时。

### 5.2 Debug 模式 Flash 溢出

**现象**：`zig build` 默认 Debug 模式，链接时报 `.text will not fit in FLASH: overflowed by 58112 bytes`。
**解决**：必须用 `zig build -Doptimize=ReleaseSmall`。Debug 模式带完整 panic 栈回溯，256KB Flash 装不下。

### 5.3 ARMCC 汇编 → GNU AS 语法

**关键差异**：

| Keil ARMCC | GNU AS |
|------------|--------|
| `AREA STACK, NOINIT` | `.section .stack, "aw"` |
| `SPACE 0x400` | `.space 0x400` |
| `DCD __initial_sp` | `.word _estack` |
| `IMPORT __main` | `.extern main` |
| `EXPORT Reset_Handler [WEAK]` | `.weak Reset_Handler` + `.type` |
| `B .` (死循环) | `b .` |
| `PROC ... ENDP` | `.thumb_func` + `.size` |

**重大陷阱**：Keil 用 `__main`（C 库初始化桩），GNU 直接调 `main()`。我们的 startup.s 用 `bl main`。

### 5.4 链接脚本段顺序

**实测**（不是理论）：

```
.data   offset=0x20000 size=4    ← 占 0x20000000-0x20000003
.bss    offset=0x20004 size=4    ← .bss 实际从 0x20000004 开始
.stack  offset=0x20004 size=1024 ← NOLOAD，与 .bss 同地址
.heap   offset=0x20004 size=512
```

**结论**：定义 `export var heartbeat: u32 = 0`（.bss 段），其运行时地址是 `0x20000004`，**不是** 0x20000000。

### 5.5 `RESET` / `SET` / `SCB` 宏缺失

**问题**：从 Keil 复制的 `system_stm32f10x.c` 引用了 RESET、SET、HSE_STARTUP_TIMEOUT、SCB->VTOR 等。
**解决**：在自写的 `c/hal/stm32f10x.h` 里补：
```c
#define RESET 0
#define SET 1
#define HSE_STARTUP_TIMEOUT ((uint16_t)0x0500)
#define VECT_TAB_OFFSET 0x00
typedef struct { ... } SCB_TypeDef;  // Cortex-M3 System Control Block
#define SCB ((SCB_TypeDef *)0xE000ED00)
```

---

## 6. MCU 验证方法（已实测有效）

**心跳计数器方法**：
```zig
export var heartbeat: u32 = 0;  // 在 .bss，地址 0x20000004
// main 循环中：heartbeat += 1;
```

**读取**：
```sh
probe-rs read b32 0x20000004 1 --chip STM32F103RC
```

**预期结果**：连续 5 次采样值各不相同。

实测值：
```
0x0003ea6e
0x0003ea50
0x0003e9eb
0x0004139e
0x0003ea18
```

确认 MCU 确实在跑用户代码。

---

## 7. Git 历史（3 个 commit）

```
f08ed3d feat: SRAM heartbeat for MCU liveness verification
2541566 feat: LED blink on PB0 via direct register access
a3a908f chore: initial project scaffold — Zig + C mixed compilation for STM32F103RC
```

---

## 8. Zig 0.16 嵌入式模板代码片段（关键片段）

### 8.1 MMIO 寄存器声明

```zig
const RCC_BASE    = 0x40021000;
const RCC_APB2ENR = @as(*volatile u32, @ptrFromInt(RCC_BASE + 0x18));

const GPIOB_BASE = 0x40010C00;
const GPIOB_CRL  = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x00));
const GPIOB_BSRR = @as(*volatile u32, @ptrFromInt(GPIOB_BASE + 0x10));
```

**注意**：`@ptrFromInt` 是 Zig 0.16 写法，`@intToPtr` 已弃用。

### 8.2 主循环结构

```zig
export fn main() callconv(.c) noreturn {
    // 1. 启用外设时钟
    RCC_APB2ENR.* |= 1 << 3;
    _ = RCC_APB2ENR.*;  // pipeline flush

    // 2. 配置 GPIO
    GPIOB_CRL.* &= ~@as(u32, 0xF << (0 * 4));
    GPIOB_CRL.* |= 0x3 << (0 * 4);

    // 3. 无限循环
    while (true) {
        GPIOB_BSRR.* = @as(u32, 1 << 0);       // set PB0
        GPIOB_BSRR.* = @as(u32, 1 << 16);     // reset PB0
    }
}
```

### 8.3 build.zig 关键配置

```zig
const target = b.resolveTargetQuery(.{
    .cpu_arch = .thumb,
    .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m3 },
    .os_tag = .freestanding,
    .abi = .eabi,
});

exe.root_module.addAssemblyFile(b.path("c/startup/startup_stm32f10x_hd.s"));
exe.root_module.addCSourceFile(.{
    .file = b.path("c/hal/system_stm32f10x.c"),
    .flags = &.{
        "-mcpu=cortex-m3",
        "-mthumb",
        "-DSTM32F10X_HD",
        "-DUSE_STDPERIPH_DRIVER",
        "-I", "c/hal",
    },
});
exe.setLinkerScript(b.path("c/ld/stm32f103rct6.ld"));
```

---

## 9. 已知 TODO（未完成）

- [ ] SysTick 中断实现 1ms 精确计时（替换 delay 循环）
- [ ] 移除 heartbeat delay 后，LED 翻转过快不可见，需加回精确延时
- [ ] MPU6050 I2C 驱动
- [ ] 摇摇棒 POV 图像渲染逻辑
- [ ] `src/root.zig` 当前未被使用，需重新整合板级常量
- [ ] `c/drivers/` 目录待填充

---

## 10. 经验总结（一句话）

**Zig 0.16 自带完整的 ARM Cortex-M 交叉编译工具链，加上 probe-rs 0.31 + CMSIS-DAP，可以完全替代 Keil + ARMCC + OpenOCD 的传统嵌入式工作流，但需要：(1) ReleaseSmall 优化；(2) Zig 0.16 Module API（不是 Compile API）；(3) 手写最小 CMSIS 头文件存根；(4) Keil ARMCC 汇编语法转 GNU AS。**

---

## 11. Session 2（2026-07-06 evening）：驱动 + ISR 打通（修复 Lockup）

> 本节记录 Lockup 修复的关键事实——代码 git diff 看不到根因，必须有这份记录。

### 11.1 Lockup 现象与根因

**现象**（用户实测）：旧固件烧录后 PB0 LED 常亮但无肉眼闪烁；用示波器看 PB0 信号平均频率 3.6 MHz，正占空比 63%——说明 main 没跑到 toggle 循环，PB0 是默认上拉态的某条杂散路径被点亮。

**根因**（两次叠加）：
1. **`c/startup/startup_stm32f10x_hd.s` 用 `.section .isr_vector`，但 `c/ld/stm32f103rct6.ld` 用 `KEEP(*(.vector_table))`**——段名不匹配，链接器把向量表丢/合并错位。flash origin 0x08000000 处实际是代码而非向量。reset 时 `MSP = 0xF241B082`（ARM 指令字节）、`PC = 0xF2C40000`（也是指令），CPU 跳进随机代码而非 `Reset_Handler`。

2. **链接器报 58 个 undefined IRQ handler 符号**（如 `WWDG_IRQHandler`、`TIM7_IRQHandler`）。.s 只定义了 9 个系统 handler（NMI/HardFault/MemManage/BusFault/UsageFault/SVC/DebugMon/PendSV/SysTick），60 个设备 IRQ 全缺失。

**早期误判**：第一次构建时 `.text` 段起始字节是 `0xF241B082` 而非期望的 `_estack = 0x20010000`——把 ELF 文件头当成了向量表。正确做法：用 ELF section header 找到 `.text` 真实文件偏移（0x10000）再读。

### 11.2 修复策略

| 步骤 | 修改 | 文件 |
|------|------|------|
| 1 | `.section .isr_vector` → `.section .vector_table` | `c/startup/startup_stm32f10x_hd.s` |
| 2 | 60 个设备 IRQ 加 `.weak X_IRQHandler` + `.thumb_set X_IRQHandler, Default_Handler` 弱别名指向单条 `b .` 死循环 | 同上 |
| 3 | 自写 HAL→CMSIS shim 替换最小存根头（`c/hal/stm32f10x.h`）——转发到官方 `stm32f103xe.h`，补 HAL 风格宏（`HSI_VALUE`/`HSE_VALUE`/`RESET`/`__I`/`__O`/`__IO`），声明 `AHBPrescTable` 为 `volatile const` | `c/hal/stm32f10x.h`（新增 shim），`c/hal/stm32f1xx.h`，`c/hal/system_stm32f1xx.h`（转发 shim） |
| 4 | 用 RTE 的 1094 行 `system_stm32f10x.c`（F103RC 专用 `SetSysClockTo72()`）替换简化版 | `c/hal/system_stm32f10x.c` |
| 5 | 写 10 步 HAL 等价初始化序列：`NVIC priority group(4) → Flash prefetch → HSE 8MHz + wait HSERDY → Flash latency=2 → PLL HSE×9 → 总线分频(HPRE/1, PPRE1/2, PPRE2/1) → 切 SYSCLK=PLL → SystemCoreClockUpdate → 外设时钟(IOPA/IOPB/IOPC/AFIO/SPI1/TIM7) → SysTick 1ms tick` | `c/drivers/board_init.c`（全新） |
| 6 | 提供 TIM7_IRQHandler / EXTI3_IRQHandler 强定义覆盖 weak 默认 | `c/drivers/it.c` |
| 7 | LED POV / 振动 / 字模占位驱动 | `c/drivers/led_pov.c`, `vibration.c`, `font_pov.c` |
| 8 | 在 `main.zig` 加 `phase` / `phase2` 全局变量标记进度（halt 后 probe-rs 可读） | `src/main.zig` |
| 9 | BSRR 翻 PB0 LED 验证时钟 + main 路径 | `src/main.zig` |

### 11.3 调试方法（不可从代码看出来）

**1. phase 标记法**（关键技巧，未来调试继续沿用）：
```zig
export var phase: u32 = 0xAAAAAAAA;  // init 值
phase = 0x11111111;                  // 进入 main
phase = 0x22222222;                  // PB0 init OK
phase = 0x33333333;                  // board_init 返回
```
halt 后读 `probe-rs read b32 0x20000008 1` 即可知道 main 走到哪。

**2. 寄存器读回验证时钟**：
```sh
probe-rs read b32 --chip STM32F103RC --protocol swd 0x40021000 8
```
期望：`CR=0x03035b83`（HSEON+HSERDY+PLLON+PLLRDY 全置位），`CFGR=0x001d040a`（SWS=PLL, PLLMULL=9, HPRE/1, PPRE1/2, PPRE2/1）。

**3. 故障寄存器读回**：
```sh
probe-rs read b32 --chip STM32F103RC --protocol swd 0xE000ED28 2  # CFSR + HFSR
```
Lockup 修复验证：`CFSR=0`、`HFSR=0`。

**4. 调试陷阱**：probe-rs 默认走 JTAG，但 STM32 通常只接 SWD。**必须加 `--protocol swd`**，否则报 `JTAG DR scan chain is empty`。

**5. session 清理**：上一次 `probe-rs run` 退出后，下一次 `download` 可能 fail（`Only 2/4 transfers were executed`），需先 `probe-rs reset` 再 download。

### 11.4 空循环延时反模式（CLAUDE.md 已记）

**现象**：Zig 的 `while (i < 1000000) : (i += 1) {}` 在 `-Os` 下被编译器删除（`i` 无副作用，整段无效果）。即使不删，延时长度也依赖时钟频率和指令周期数，不是 portable。

**已记入约束**（`CLAUDE.md` 嵌入式编码规范 + memory `embedded-no-empty-delay-loops.md`）：
- 主代码必须用 SysTick（已在 `board_init()` 开启，72 MHz/1000 Hz）或 TIMx 定时器做延时。
- 即使临时 debug 也必须用 `asm volatile("nop")` 作副作用锚点。
- **禁止**用 `_ = SysTick_VAL.*` 这种"为了防优化而读 volatile 寄存器"的方式——会模糊"我在读 SysTick"的意图，让 review 时难以判断目的。`asm volatile("nop")` 意图清晰且 portable。
- 提交前必须把 debug 代码替换为定时器方案。

**实测可工作写法**（替代方案 1，已被采纳）：`_ = SysTick_VAL.*` 确实能让 LED toggle（PB0 ODR 在 0x10 与 0x11 间交替），但因违反规范，下一步将替换为正经 SysTick ms sleep。

### 11.5 离岸 git 策略（实测流程）

```bash
# 1. 复位 main 到旧节点（如果之前 FF 合并过）
git checkout main
git reset --hard f08ed3d

# 2. dev 直接 --no-ff 合并到 main（不要走 release）
git merge --no-ff dev -m "merge dev → main: <里程碑描述>"
# 优势：main 上有显式 merge commit 节点，提高该里程碑可见性
# 适用场景：非正式版本，仅作"开发过程中的稳定里程碑"展示

# 3. dev 仍保持线性，HEAD 不动，继续在 dev 上工作
git checkout dev
```

**重要**：按规范 `main 仅接受 release 合并`，但用户明确允许"非正式里程碑"走 dev → main 直合并。本节是该操作的记录。

### 11.6 SRAM 实际地址更正

旧 README §6 写 "`export var heartbeat: u32 = 0` 在 .bss，地址 0x20000004"。实际本 session 验证：

| 全局变量 | 实际运行时地址 | 来源 |
|---------|---------------|------|
| `_sidata` (LOADADDR) | flash offset 0x20000 | linker section header |
| `.data` 起始 (POV_ROW_COLOR 等) | 0x20000000 | .data 在 .bss 之前 |
| `phase2` (init 0xBBBBBBBB) | 0x20000004 | Zig 声明顺序倒置? |
| `phase` (init 0xAAAAAAAA) | 0x20000008 | Zig `export var` 进 .data |

**纠正**：`.data` 在 .bss 之前，且 Zig 可能倒置全局声明顺序。**实际定位必须用 `probe-rs read` 反查**，不能从代码推算。

### 11.7 后续路径（仅裸 STM32 + 杜邦线即可验证）

| 路径 | 验证目标 | 所需硬件 |
|------|---------|----------|
| SPI1 master loopback | PA5(MOSI)→PA6(MISO) 单线回环，发 0x55 收 0x55 | 1 根杜邦线 |
| TIM7 base tick | PA8 翻转，5 kHz 方波 = TIM7 OK | 示波器 |
| EXTI3 触发 | PC3 用杜邦线拉低/拉高模拟振动 | 1 根杜邦线 |

**为什么先验证这 3 条**：POV 推帧 = TIM7 ISR → led_pov_tick → SPI1 DMA → LED 芯片。任一底层不通，POV 现象都一样（屏幕不亮），无法定位。预先跑通这 3 条路径，未来 POV 失败时可立刻排除。

### 11.8 用户反馈语录（设计报告引用）

- "和 HAL 对偶"——行为等价于 HAL 但不依赖 HAL 抽象层，可从 HAL 代码提取正确的初始化序列与寄存器值用裸寄存器重写
- "RTE 文件比 car2025_final reference 更具备参考性"——RTE 是 Keil 为 F103RC 自动生成（含 SetSysClockTo72）
- "空循环延时是反模式"——必须 SysTick/TIMx
- "临时 debug 也应该使用 asm volatile(\"nop\")，不要用 _ = SysTick_VAL.* 模糊意图"
- "这不是正式发布版本，仅作开发过程中的稳定里程碑且具备重要意义，需在 main 上合并一次提高可见性"——离岸策略的灵活运用

---

## 12. Session 3（2026-07-07 morning）：POV 5 Phase 底层验证全通过

> 本节记录在 dev 分支上完成的"POV 推帧链路 5 个底层路径验证"。session-log 之所以重要：每个 Phase 的引脚 mux、wire 接线、ISR 行为都不能从代码还原，必须留文字。

### 12.1 5 Phase 全景

| Phase | 验证目标 | 关键路径 | 验证手段 | 最终结论 |
|-------|---------|----------|----------|---------|
| A | SPI1 PA5/PA6/PA7 pin mux | led_pov_init() 写 GPIOA->CRL | probe-rs read b32 0x40010800 | 0xB3B34444 |
| B1 | Blocking SPI loopback | test_spi_loopback_blocking() | read b32 0x20000030 | rx=[0x55,0xAA,0xF0] |
| B2 | DMA1 ch3+ch2 SPI loopback | test_spi_loopback_dma() | 同上 | rx+done=1 |
| C | TIM7 100µs + LED toggle | test_tim7_start() | 视觉 + read 0x20000014 | LED 半亮 + 计数 120k |
| D | EXTI3 PC3 上升沿 ISR | vibration_init() | read 0x20000018 | 计数 0→4→9 |

### 12.2 项目非标准 SPI1 引脚映射（关键陷阱，设计报告必引）

c/drivers/board.h:52-59 定义的引脚，不是 STM32 标准 SPI1 全双工：

- PA4 = NSS/CS（未用，配置防浮空）
- PA5 = SCK → AF push-pull 50MHz
- PA6 = 手动 CS（BSRR bit-bang）→ GP push-pull 50MHz，不复用 MISO
- PA7 = MOSI → AF push-pull 50MHz

LED 驱动是单向写入（SPI 主 → 从），无回传路径，因此不需要配 MISO。后果：led_pov_init() 内 CRL 写只需配 PA5（SCK）+ PA6（CS GP PP）+ PA7（MOSI）。SRAM 无 buffer 接收回读。

### 12.3 真 bug 修复 1：Phase A pin mux

症状：led_pov_init() 配置了 SPI1 CR1（master, BR, SSI/SSM, SPE），从未配置 GPIOA->CRL。PA5/PA6/PA7 留复位态 = floating input，SPI1 peripheral 即使 SPE=1 也不会驱动引脚（STM32F1 文档：peripheral 输出需 GPIO AF PP mode）。

修复：步骤 1a 插在 SPI 复位后、CR1 配置前：

```
GPIOA->CRL = (GPIOA->CRL & ~0xFFFF0000u)
           | (0x3u << 16)   /* PA4 — GP PP 50MHz (unused)             */
           | (0xBu << 20)   /* PA5 — SCK, AF PP 50MHz                */
           | (0x3u << 24)   /* PA6 — CS, GP PP 50MHz (project-specific) */
           | (0xBu << 28);  /* PA7 — MOSI, AF PP 50MHz              */
POV_CS_PORT->BSRR = POV_CS_PIN;   /* CS idle high */
```

位序陷阱（用户当场指出，代码审查关键时刻）：CRL 高 16 bit 内部排列为 PA7 在最高 nibble，PA4 在最低 nibble。最初我按"PA4→PA7 顺次拼接"写 0xBBB3，错了。正确读法：bit 31-28 = PA7 = 0xB；bit 27-24 = PA6 = 0x3；bit 23-20 = PA5 = 0xB；bit 19-16 = PA4 = 0x3；拼接 = 0xB3B3。

### 12.4 真 bug 修复 2：Phase D PC3 内部上拉

问题：vibration_init() 配 AFIO_EXTICR + RTSR + IMR + NVIC，但没配 PC3 输入上拉。板上无外部上拉电阻时 PC3 浮空，杜邦线无法稳定触发 EXTI3。

修复：步骤 0 插在 AFIO EXTICR 前：

```
VIBE_GPIO_CLK_EN();
GPIOC->CRL = (GPIOC->CRL & ~(0xFu << 12)) | (0x8u << 12);   /* CNF=10 input-pull, MODE=00 */
GPIOC->ODR |= (1u << 3);                                     /* ODR=1 → 上拉（ODR=0 是下拉）*/
```

### 12.5 Phase C pin 换 PA8 → PB0（蜂鸣器问题）

用户反馈："烧录后听到蜂鸣器"。

根因：STM32F103 默认 PA8 复用为 TIM1_CH1。car2025_final/Core/Src/music.c 就是用 TIM1_CH1 出蜂鸣器 PWM。board_init.c:POV_CS 注释也确认 "PA6 复用原 IR_LOCK" 暗示板上很多管脚有内部重新走线。直接 GPIO 翻转 PA8 会让蜂鸣器发声，即使没启用 TIM1。

解决方案：改翻 PB0（LED，已知非 BEEP）。改动：GPIOA->BSRR ^= (1<<8) → GPIOB->BSRR ^= (1<<0)。同时不动 PA8 GPIO 配置，让 PA8 保留复位态输入（降低无意驱动蜂鸣器概率）。

为什么选 PB0：板上接 LED（原 Phase 0 验证过），不接蜂鸣器；5 kHz 翻转 LED 肉眼呈现"半亮"（占空比 50% 积分），同时作视觉验证；不需要新加 GPIO 配置（main.zig 已配）。

### 12.6 Phase D 物理操作规范（未来回归测试参考）

接线：杜邦线一端 Pin 6（PC3/VIBE_SIG），另一端 Pin 2（GND）。Pin 7（TIM7_TICK）是内部资源，board.h:18 注释"不出到接口"，物理上不存在。

正确序列：

1. 杜邦线悬空，不碰任何金属 ← g_isr_count_exti3 基线读 = X（典型 0）
2. 碰 Pin 2（GND）~100ms ← 短接 = 下降沿，EXTI3 不响应
3. 松开 ← 释放 = 内部上拉拉回高 = 上升沿，EXTI3 触发 ISR
4. 等 ~300ms（过 5ms 软消抖）
5. 再读 g_isr_count_exti3 ← 期望 >= X + 1

为什么是"松开"才是关键：EXTI3 配置 RTSR=1, FTSR=0，只响应上升沿。短接 = 下降沿（无反应）；松开 = 上升沿（触发）。

机械弹跳现象（实测）：用户单次碰-松操作，g_isr_count_exti3 从 0 跳到 4（不是 1）。STM32 内置 Schmitt trigger 在金属触点接触电阻跳变时多次解释为独立边沿。这是真实硬件的常态，不是 bug。5ms 软消抖（vibration_consume()）会把 raw N 个 ISR 合并成 ~1 个有效振动事件。

### 12.7 probe-rs 0.31 CMSIS-DAP multi-transfer bug + 工作流切换

症状：probe-rs read --chip STM32F103RC b32 <addr> <count> 在某些场景报 "Failed to read component information at 0xe0001000"（自动探测芯片失败）以及 "CMSIS_DAP: Only 1/2 transfers were executed, but no error was reported"。

根因：BUPT CMSIS-DAP v2025 探测器固件对 DAP multi-transfer 命令支持不全。probe-rs read 自动探测阶段读 ROM table 用了 multi-transfer。

解决方案：

1. 加 --chip STM32F103RC 跳过自动探测（必须）
2. 单次 read 用 probe-rs CLI（可行，用于 peripheral 寄存器如 0x40010800）
3. 改用 gdb 链路：probe-rs gdb --chip STM32F103RC + arm-none-eabi-gdb + target remote localhost:1337 + gdb remote protocol 走单 transfer per memory read

gdb 限制：probe-rs gdbserver 默认内存 map 不含 peripheral 区域（0x40000000-0x5FFFFFFF）。gdb x/wx 0x40010800 报 "Cannot access memory"。peripheral 寄存器必须走 probe-rs CLI 或加 firmware 端 debug mirror。

### 12.8 关键 SRAM 地址实测（probe-rs / gdb 可读）

| 变量 | 地址 | 含义 | 期望值（Phase 全过） |
|------|------|------|---------------------|
| phase（Zig） | 0x20000000 | main 进度 | 0x16161616 |
| g_systick_ms | 0x2000000C | SysTick 1ms tick | 持续涨 |
| g_isr_count_tim7 | 0x20000014 | TIM7 ISR 命中 | 跑 5 秒涨 ~50000 |
| g_isr_count_exti3 | 0x20000018 | EXTI3 ISR 命中 | 操作前后增 ≥ 1 |
| s_state | 0x2000001C | led_pov 状态机 | 0x1 |
| s_cat | 0x20000020 | POV cat 索引 | 0 |
| s_pending | 0x20000028 | 振动事件消抖后标志 | 0 |
| s_trigger_ms | 0x2000002C | 最近触发时间戳 | 0 |
| g_spi_test_phase | 0x20000030 | B1 步骤 | 0x3 |
| g_spi_test_rx[0..2] | 0x20000034 | B1 接收字节 | 0x55, 0xAA, 0xF0 |
| g_spi_dma_rx[0..2] | 0x20000037 | B2 接收字节 | 0x55, 0xAA, 0xF0 |
| g_spi_dma_done | 0x2000003C | B2 完成标志 | 0x1 |
| GPIOA->CRL | 0x40010800 | pin mux 寄存器 | 0xB3B34444 |
| TIM7->CR1 | 0x40001400 | TIM7 控制 | 0x1（CEN） |

g_spi_test_tx 在 .data（初始化值 0x55 0xAA 0xF0），地址 0x20000004。g_spi_test_rx / g_spi_dma_rx / g_spi_dma_done 都在 .bss。

### 12.9 验证夹具临时代码 → c/tests/

新增文件：

- c/drivers/test_spi.c — Phase B1（blocking）+ Phase B2（DMA）+ DMA1_Channel2_IRQHandler 强符号
- c/drivers/test_tim7.c — Phase C：TIM7_IRQHandler 强符号覆盖 it.c 的 weak 版本 + test_tim7_start()

关键设计（用户选的 Option 1，临时回退 PA6 为 MISO）：PA6 在 B 测试期间临时回退到 0x4 floating input，跑完恢复到 0x3 GP push-pull。所有临时反转逻辑全在 test_spi.c，led_pov.c 生产代码保持纯净。

用户选择"改名而不是删除"（收尾）：

- c/drivers/test_spi.c → c/tests/test_spi.c
- c/drivers/test_tim7.c → c/tests/test_tim7.c
- build.zig 删 2 行 addCSourceFiles
- it.c 移除 __attribute__((weak))
- main.zig 简化回 Phase 0（PB0 LED + board_init + led_pov_init + halt）
- 生产 ELF：724516 → 719732 bytes（节省 4784）

未来重现 5 Phase 验证：把 c/tests/ 下两个文件加回 build.zig 的 addCSourceFiles，把 tests/ 加到 include path，改 main.zig 加调用，5 分钟重跑。

### 12.10 volatile 真轮询 vs 优化屏障辨析（设计报告可引）

CLAUDE.md 铁律禁的是"为防优化而读 volatile 寄存器但不读其值"：

```
// 错：空循环优化屏障 — 模糊意图，被禁
while (SysTick_VAL.* != 0) {}   // 读 volatile 但不用其值
```

允许的真轮询（本项目 Phase B1 验证用）：

```
uint32_t t0 = g_systick_ms;
while ((g_systick_ms - t0) < 1U) { /* 读 volatile，实际作了 < 比较，合法 */ }
```

读 volatile 的值参与条件判断，真在轮询 ISR 改写的计数器。意图清晰（等 1ms），portable。同样，Phase B2 的 while (g_spi_dma_done == 0) 是合法真轮询：DMA ISR 改写 volatile，gdb 提示时它的值用于 == 0 条件判断。

### 12.11 DMA1 中断命名坑（设计报告可引）

CMSIS 命名：STM32F103 DMA channel 控制寄存器位名是 DMA_CCR_EN / DMA_CCR_TCIE / DMA_CCR_DIR / DMA_CCR_MINC（不带 channel 后缀）。最初错误写 DMA_CCR1_EN（猜测的"channel 1"风格命名），编译报 undeclared identifier，纠正。

正确 ISR 命名：DMA1_Channel2_IRQHandler（有 channel 后缀，IRQn 12）。这个在 startup.s 里有 weak 默认 handler，test_spi.c 提供强符号覆盖。链接器对 IRQn vector 名是按 channel 后缀的。

### 12.12 用户反馈语录（本 session，设计报告引用）

- "和 HAL 对偶"——行为等价于 HAL 但不依赖 HAL 抽象层，可从 HAL 代码提取正确的初始化序列与寄存器值用裸寄存器重写
- "我必须用 gdb 这样总是 read fail 根本没法正常调试"——probe-rs CMSIS-DAP bug 出现后，稳定路径是 gdb
- "我觉得有可能是因为我未能理解短接 6、7 的作用导致误解"——主动指出对 Phase D 协议的初始误解
- "现在回到实验验证流程"——结束 gdb 探索，回到 gdb 链路
- "C:两条都做（B 重测 + D）"——选择最严谨的收尾路径
- "可能计数器没有严格按照预期"——对 Phase D g_isr_count_exti3 计数 > 1 表示不解（实为机械弹跳，这是硬件常态）
- "改名而不是删除"——收尾清理选 Option 3
- "总结本次对话在未来可能会对完成设计报告有帮助的内容"——本次 session 的元任务

### 12.13 设计报告相关 - 5 Phase 验证的"闭环证据链"

直接证明：每次 Phase 通过有至少 1 个不可由其他 Phase 推出的硬件寄存器观测。

关键洞察：Phase B 的字节精确匹配（tx = rx = 0x55, 0xAA, 0xF0）是 Phase A 的强间接证据。如果 PA5/PA7 pin mux 失败，SPI 输出无法到物理线，slave（PA6 测试 MISO）无法收到字节匹配。

### 12.14 项目产出（可继续 git commit）

未提交改动清单（dev 分支）：

1. c/drivers/led_pov.c — 新增 led_pov_init() 步骤 1a（Phase A pin mux）
2. c/drivers/vibration.c — 新增 vibration_init() 步骤 0（PC3 上拉）
3. c/tests/test_spi.c — Phase B 验证夹具（从 c/drivers/ 移出）
4. c/tests/test_tim7.c — Phase C 验证夹具（从 c/drivers/ 移出）
5. build.zig — 注释掉 test_*.c addCSourceFiles，留下回归路径说明
6. src/main.zig — 简化成 Phase 0 heartbeat

建议 commit 拆分：

- @ fix: SPI1 pin mux + PC3 pull-up — 提交 1 + 2（真 bug 修复）
- @ refactor: 5 Phase 验证夹具移到 c/tests/，移除 it.c weak — 提交 3 + 4 + 5 + 6
- （可选）@ docs: session-log 记录 5 Phase 验证 — 提交本 README 第 12 节

### 12.15 用户后续可以问的方向

- POV 应用层逻辑实现（从 car2025_final/Core/Src/led_show.c 移植 LEDSHOW()）
- 字模注入（firmware 端提供 PC 工具链把图像转 .h 数组）
- main loop 状态机（读取振动 → 触发 s_pending → 调 led_pov_on_vibration → 调 led_pov_start）
- USART1 + RTT 调试输出（取代 halt + probe-rs read 工作流）

---

## 13. Session 3 补充：GDB Workflow 实测命令集（可复用片段）

### 13.1 probe-rs gdbserver + arm-none-eabi-gdb 完整流程

Terminal A（前台挂着 gdbserver）：

```
probe-rs gdb --chip STM32F103RC zig-out\bin\wobbly-stick-light
```

期望输出：INFO probe_rs::gdb_server: Listening on 0.0.0.0:1337

Terminal B（gdb client）：

```
arm-none-eabi-gdb zig-out\bin\wobbly-stick-light
```

gdb 内命令：

- target remote localhost:1337（连 gdbserver，默认端口 1337）
- monitor reset halt（chip 拉回 reset_vector）
- load（重刷 ELF）
- continue（全速跑）

firmware halt 后典型读：

- print/x g_spi_test_phase（符号级读，绕开对齐问题）
- print g_spi_test_rx[0..2]（单字节读）
- print g_isr_count_tim7（TIM7 ISR 计数）
- print g_isr_count_exti3（EXTI3 ISR 计数）
- print s_state（led_pov 状态机）
- x/4bx 0x20000020（.bss 区域原始字节，检查是否被 zero）
- x/wx 0x2000001c（s_state as 32-bit word）

Symbol-based reads vs address-based reads：

- 符号读（print g_spi_test_rx[0]）→ 通过编译时表解 → 绕开任何对齐/偏移错
- 地址读（x/wx 0x20000034）→ 直接打地址 → 要自己保证 4 字节对齐（例如 0x20000037 不对齐会报 not aligned to 4 bytes）

### 13.2 替代：GDB 启动后卡在 Phase A/B 时的常见命令

- info registers pc
- x/i $pc（反汇编当前 PC）
- disassemble led_pov_init（验证 led_pov_init 的 CRL 写没被优化掉）
- print/x *(unsigned int*)0x40001400（TIM7->CR1，期望 0x1）
- print/x *(unsigned int*)0x40010400（AFIO_EXTICR1，期望 0x00002000 = PC3 → EXTI3）
- print/x *(unsigned int*)0x40010414（EXTI_RTSR，期望 bit3=1）

调试技巧：利用 phase 变量作 checkpoint。在 main.zig 各 phase 入口写 phase = 0xNNNNNNNN。halt 后 read 0x20000000 看跑到哪。

### 13.3 probe-rs + gdb 常见故障速查

| 现象 | 原因 | 解 |
|------|------|-----|
| probe-rs read 报 Only 1/2 transfers executed | BUPT CMSIS-DAP multi-transfer bug | 加 --chip STM32F103RC，或换 gdb |
| gdb x/wx 0x40010800 报 Cannot access memory | probe-rs gdbserver 默认不含 peripheral 区 | 改 probe-rs CLI 读，或加 firmware debug mirror |
| gdb x/wx 0x20000037 报 not aligned to 4 bytes | 地址未 4 字节对齐 | 改读 0x20000034 或 0x20000038，或用符号读 |
| target remote localhost:1337 报 Connection refused | probe-rs gdbserver 没起 | netstat -ano \| findstr :1337 看 PID |
| arm-none-eabi-gdb 命令找不到 | 不在 PATH | 用户 env 已有，which arm-none-eabi-gdb 确认 |

### 13.4 VS Code + Cortex-Debug（备用，本 session 未走通）

如果用户改用 VS Code 替代纯 gdb：装 marus25.cortex-debug，配置 .vscode/launch.json 用 servertype: probe-rs-debug，F5 启动，Watch 窗口加 0x40010800 看 GPIOA CRL。

---

## 14. Session 4（2026-07-07 afternoon）：POV 字模设计迭代 + car2025 reference 重读

> 关键失误：把 car2025 `g_ShowData[3][48]` **的 3 行错认为 3 帧**——实际 3 行 = 3 个 LED 行（顶/中/底），每行 48 col 扫同一组 col 时刻的不同 LED。整 session 围绕这个语义错位绕弯。
>
> 设计报告必引："以 reference 中间固定部分为参考"——reference **不在 ISR 内轮换 frame**，"交替"是更高层（car2025 菜单）切换 `g_ShowData` 索引；ISR 内每行 col 数据是**完全静态**的。

### 14.1 真 bug 修复 #3：POV_COLOR 常量错位（"全亮" 现象根因）

**症状**：用户观察 POV 图像"全亮"（糊成一团），L/K/M 字母不分明。

**根因（bit-domain 错配）**：bit-domain 解码 `b=(byte>>6)&3, g=(byte>>3)&7, r=byte&7`。旧 `POV_COLOR_BLUE=0x80`：B = `(0x80>>6)&3 = 2` → **只点亮 cat 内 2/4 颗 LED**，不是全部 4 颗。字模 byte = 0xFF（意图"该列 8 颗全亮"）+ `POV_COLOR_BLUE=0x80` → 写入 8 个 RAM 位置全部 = 0x80 → 每 cat 只亮 2 颗 → 顶 8 LED 中只有 4 颗亮（positions 0,1,4,5）。用户看到 4 颗稀疏亮点，被 4 kHz ISR + 视觉融合成"亮带"，但字母形状消失。

**修复**（`c/drivers/board.h`）：B/G/R 通道必须填满。`POV_COLOR_BLUE=0xC0` (B=3,4 颗/cat)、`POV_COLOR_GREEN=0x38` (G=7)、`POV_COLOR_RED=0x07` (R=7)、`POV_COLOR_YELLOW=0x3F` (G+R 满)。

**易错点**：`0xFF`（全 RGB 通道最大）= **白**（4 颗混合色），不是任何单色。要纯蓝必须 `0xC0`。

### 14.2 bit 顺序校正

LED_Loop1 写 RAM 是 `for (i=0; i<8; i++) RAM[i]=(tmp&1)?color:0; tmp>>=1;`，所以 **bit 0 → RAM[0] → 顶部 LED**，bit 7 → 底部 LED（之前一直反着）。L 底横笔应写 `byte = 0x80`（仅 bit 7 = 底部 LED 亮），不是 `0x01`。

### 14.3 car2025 reference 关键重读（纠正之前的误判）

`car2025_final/Core/Src/led_show.c:16-38`：`g_ShowData[3][48]` = `[LED 行][col 扫描时刻]`。Row 0 = 顶 8 LEDs 蓝（含多段字母）、Row 1 = 中 8 LEDs 红（cols 20..26 固定菱形）、Row 2 = 底 8 LEDs 黄（多段字母）。`UserLEDShowProcess` 单调递增 col 0..40，每 6 cats 调 `LED_Loop1(col)` 把当前 col 的 3 行数据写入 24 个 RAM 位置。**ISR 内 g_ShowData 完全静态**，不存在 frame 切换。"上/下轮换字母"由更高层切换 `g_ShowData` 索引实现。

**对本项目的指导**：3 行 = 3 个 LED 行；3 行 **共享同一组 col 扫描时刻**——col 维度水平扫描 + row 维度彩色分割。**每行在相同 col 段画一个字母**，字母在空间上**纵向堆叠**（L 顶/K 中/M 底），不滚动、不轮换。

### 14.4 设计决策轨迹（用户改口语录）

| 用户原话 | 校正 |
|---------|------|
| "我觉得可能每个字母 8 col 太少，需要更多宽度" | 12 col → 16 col |
| "你可以看 reference 中间那个不变的部分来对齐" | "中间不变" 是 row 1 固定图案，但**不应模仿其 frame 切换**——只学其 col 宽度 + 速度 |
| "我只是想借鉴 reference 心形的**宽度和速度**" | 抛弃"frame 切换"思路；只搬 **8 col 宽 + 60ms 帧 + 4 kHz ISR** 这三个数值 |
| "我们本质还是**让三个字母纵向排列**，**不滚动显示**" | **3 字母同 col 段、上下堆叠**，不跨 col 段 |
| "L 竖笔太粗了 / K 出现幻视 X / M 勉强辨认"（迭代 3 次） | L 竖 5→2 col；K 斜臂 1-LED 厚→2-LED 厚、加 4 col、加 2 col gap；M 加宽到 2 col 双竖 + 8 col V 谷 |
| "K 整体再拉宽一点，可以通过斜笔画断开中间留点空像素" | K 5 col → 7 col，**斜笔画中间插 2 col 黑像素**形成"断笔" |

### 14.5 最终字模设计（design report 重点引）

```c
// c/drivers/font_pov.c FONT_LKM[3][40]，每行有效段 cols 12..27 (16 col 宽)：
// Row 0 蓝 L: 2 col 竖 + 14 col 底横
{ ...,0xFF,0xFF,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,... }
// Row 1 绿 K: 1 col 竖 + 2-LED 厚 2 段(中间 2 col 黑断开) + 角
{ ...,0xFF,0x66,0x00,0x00,0x66,0xC3,0x81,0x00,... }
// Row 2 红 M: 2 col 双竖 + 2 段 V 入 + 8 col V 谷 + 2 段 V 出
{ ...,0xFF,0xFF,0x02,0x04,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x08,0x04,0x02,0xFF,0xFF,... }
```

### 14.6 时序参数（最终态）

| 项 | 值 | 来源 |
|----|-----|------|
| TIM7 prescaler | 3599 | car2025 reference，对齐 |
| TIM7 autoreload | 4 | car2025 reference |
| TIM7 tick | 4 kHz = 250 µs/tick | 72 MHz / 3600 / 5 |
| Cats per col | 6 | 24 LED / 4 LED per cat |
| Col period | 1.5 ms = 6 × 250µs | 推导 |
| Cols per frame | 40 | Boundary C 不变量 |
| Frame period | 60 ms | 推导 |
| Frame rate | 16.7 fps | 推导 |
| 1 m/s 挥动时 1 col 物理宽 | 1.5 mm | V × Δt |
| 1 m/s 挥动时 16 col 字母宽 | 24 mm | 推导 |

### 14.7 用户反馈语录（design report 强引）

- "reference 是在上面和下面轮流显示字母，中间是不轮换的图案" —— 误读了 reference 的"轮换"机制
- "我只是让你借鉴显示心形的**宽度和速度**" —— 修正：只搬数字，不搬 frame 切换语义
- "我们本质还是让三个字母**纵向排列**，**不滚动显示**" —— 3 字母同 col 段上下堆叠
- "K 容易出现幻视 X 和全部粘成一竖" —— 1-LED 厚斜臂 → 幻视 X；cols 太少 → 粘连
- "L 竖笔画太宽了" —— L 竖 5 col → 收窄到 2 col
- "K 整体再拉宽一点，**可以通过斜笔画断开中间留点空像素**" —— K 7 col，斜笔画中间插 2 col 黑断笔

### 14.8 POV_COLOR 满通道公式（design report 可直接引）

```
byte = (R<<0) | (G<<3) | (B<<6)
  R =  byte        & 0x07  (3 bits → 0..4 LEDs/cat)
  G = (byte >> 3)  & 0x07  (3 bits)
  B = (byte >> 6)  & 0x03  (2 bits → 0..4 LEDs/cat)
```

每通道值 N 表示"cat 内第几个 LED 起开始亮"。POV_COLOR 必须 = max 通道值才能 byte=0xFF 整列 8 LED 满亮：
- `POV_COLOR_BLUE = 0xC0` (B=3 → 8 LED 全蓝)
- `POV_COLOR_GREEN = 0x38` (G=7)
- `POV_COLOR_RED = 0x07` (R=7)
- `POV_COLOR_YELLOW = 0x3F` (G+R=max)

### 14.9 经验教训（设计报告可引）

1. 用户/linter 回滚代码改动时，未必会一起回滚我追加的 session-log 内容；如果 git stash 处理链断裂（drop dangling commit），文档记录也会丢失
2. 每次 stash 操作必须确认 dangling commit 是否需要保留，否则先用 `git fsck --no-reflogs` 查无可恢复内容再 drop
3. 用户提到的"the revert"具体指什么文件，需要逐个确认——本 session 我错误地假设 font_pov.c/board.h/led_pov.c 的回滚隐含了 session-log README 的回滚

### 14.10 还需要补的事

- 相机抓拍验证（用户没硬件）
- L 底横笔"延伸"视觉缺陷：当前 `0x80` 仅接 1-LED 厚度，可能需要改 `0x81`（底 + 顶 2 LED）让底横笔"可看见"

---

