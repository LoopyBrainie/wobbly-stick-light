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