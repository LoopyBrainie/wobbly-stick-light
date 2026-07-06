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