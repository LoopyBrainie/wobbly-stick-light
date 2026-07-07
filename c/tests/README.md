# c/tests/ — POV 底层 5 Phase 验证夹具

> **本目录不参与生产 build** (`build.zig` 未引用 `c/tests/`)。仅作回归验证夹具
> (regression fixture) —— 未来若 POV 集成出现"屏幕不亮"类问题,可按本文档 5
> 分钟重跑 5 Phase,立即排除 SPI1 / TIM7 / EXTI3 / DMA / pin-mux 底层变量。

---

## 0. 设计意图与不做之事

### 做

- **覆盖 SPI1 master loopback**(Phase A/B1/B2)
- **覆盖 TIM7 高频 ISR 节奏**(Phase C)
- **覆盖 EXTI3 PC3 上升沿**(Phase D,验证归入 `c/drivers/vibration.c`,非此目录)

### 不做

- 不验证 LED 驱动芯片的实际协议(TLC5940/类似器件的时序,留给 POV 集成后阶段)
- 不替代单测/集成测 —— 测不了应用层逻辑(主循环、字模扫描、状态机)
- 不模拟振动波形 —— Phase D 物理接线由人工完成

---

## 1. 接入 build.zig(5 分钟重现)

### 步骤

1. **`build.zig`**:在 `addCSourceFiles` 列表里加两行:

   ```zig
   exe.root_module.addCSourceFile(.{ .file = b.path("c/tests/test_spi.c"),  .flags = cflags });
   exe.root_module.addCSourceFile(.{ .file = b.path("c/tests/test_tim7.c"), .flags = cflags });
   ```

   同步把 `"-I", "c/tests"` 加进 `cflags`,让 `test_spi.c`/`test_tim7.c` 找到 `board.h`。

2. **`src/main.zig`**:在 `board_init()` 与 `led_pov_init()` 之间,按 Phase 顺序依次调用:

   ```zig
   // Phase A:led_pov_init() 内部已包含 CRL pin mux,无需单独测试入口
   // Phase B1
   test_spi_loopback_blocking();
   // Phase B2
   test_spi_loopback_dma();
   // Phase C
   test_tim7_start();
   // Phase D —— 在振动初始化(vibration_init())已就位后,人工按 6 ↔ GND 触发
   ```

   `main.zig` 顶层 `extern fn` 需加:

   ```zig
   extern fn test_spi_loopback_blocking() callconv(.c) void;
   extern fn test_spi_loopback_dma()     callconv(.c) void;
   extern fn test_tim7_start()           callconv(.c) void;
   ```

3. **`zig build`** —— 编译;**`probe-rs run`** 烧录。

4. 按 § 2 各 Phase 验证手段读 SRAM/寄存器,记录是否通过。

### 退出验证模式

- 还原 `build.zig` 注释 / 移除 `addCSourceFile`
- 还原 `src/main.zig` 至 Phase 0 heartbeat 形态
- `c/tests/` 下文件保留(本次 commit 不删除,见 § 5)

---

## 2. 各 Phase 验证条件与预期结果

下表汇总所有 Phase 的硬件、软件、预期观测点。详细步骤见 § 3。

| Phase | 路径 | 硬件 | 测试入口 | 预期观测地址 | 预期值 |
|:-----:|------|------|----------|---------------|--------|
| A | SPI1 PA5/PA6/PA7 pin mux | 无 | `led_pov_init()` 副作用 | `0x40010800` (GPIOA->CRL) | 高 16 位 = `0xB3B3` |
| B1 | Blocking SPI loopback | 1 杜邦线:PA7 ↔ PA6 | `test_spi_loopback_blocking()` | `0x20000034` (g_spi_test_rx[0..2]) | `[0x55, 0xAA, 0xF0]` |
| B1 | 同上 | 同上 | 同上 | `0x20000030` (g_spi_test_phase) | `3` |
| B2 | DMA-driven loopback | 同上 | `test_spi_loopback_dma()` | `0x2000003C` (g_spi_dma_done) | `1` |
| B2 | 同上 | 同上 | 同上 | `0x20000037` (g_spi_dma_rx[0..2]) | `[0x55, 0xAA, 0xF0]` |
| C | TIM7 100 µs + PB0 toggle | 示波器探 PB0(可选) | `test_tim7_start()` | `0x20000014` (g_isr_count_tim7) | 跑 5 秒涨 ~50000 |
| C | 同上 | LED 半亮 | 同上 | PB0 GPIO | 5 kHz 方波 |
| D | EXTI3 PC3 上升沿 | 1 杜邦线:PC3(Pin 6) ↔ GND(Pin 2) | `vibration_init()` + 人工碰松 | `0x20000018` (g_isr_count_exti3) | 碰松前后差 ≥ 1 |

> **注意**:Phase D 的夹具在 `c/drivers/vibration.c`,不在 `c/tests/`。详见 § 3.4。

---

## 3. 各 Phase 详细步骤

### 3.1 Phase A —— SPI1 pin mux

#### 目的

确认 `led_pov_init()` 把 PA5/PA6/PA7 配成正确 alternate-function / push-pull 模式。
不验证,SPI1 即使 SPE=1 也不会在引脚上输出任何波形。

#### 硬件

无需任何接线,纯寄存器观察。

#### 软件

调用 `led_pov_init()`,内部已含 Phase A 步骤(原 `c/drivers/led_pov.c` 第 1a 段)。

#### 观测

```sh
probe-rs read --chip STM32F103RC b32 0x40010800 2
```

**预期** 高 16 位 = `0xB3B3`(低 16 位 = PA0-PA3,默认 `0x4444` 或自定义)。
完整 32 位值域:`0xB3B3xxxx`(典型 `0xB3B34444`)。

#### 位序陷阱(必读)

CRL 高 16 bit 内部排列:**PA7 在最高 nibble,PA4 在最低 nibble**。口语直觉"PA4→PA7 顺次"
会写出 `0xBBB3`,**错的**。正确读法:

```
bit 31-28 = PA7 = 0xB   (MOSI, AF PP)
bit 27-24 = PA6 = 0x3   (CS,   GP PP)
bit 23-20 = PA5 = 0xB   (SCK,  AF PP)
bit 19-16 = PA4 = 0x3   (unused, GP PP)
拼接       = 0xB3B3
```

#### 失败模式

| 实测 | 排查 |
|------|------|
| 高 16 位 = `0x4444` 或 `0xBBBB` | `led_pov_init()` 步骤 1a 没生效 → 检查 `c/drivers/led_pov.c` 第 1a 段 GPIOA->CRL 写 |
| `probe-rs read` 报 multi-transfer 失败 | 加 `--chip STM32F103RC`,或换 gdb |

---

### 3.2 Phase B1 —— Blocking SPI loopback

#### 目的

确认 SPI1 peripheral + PA5/PA7 pin mux 真的能驱动波形,且能被 PA6(临时回退的 MISO)收到。
Phase A 的强间接证据。

#### 硬件

**1 根杜邦线:** PA7 (MOSI) ↔ PA6 (本测试期间临时回退为 floating input)。

板上丝印位置:PA7 在 `D11` (Arduino 兼容),PA6 在 `D12`。MCU 引脚编号:
- PA7 = 引脚 30 (LQFP64)
- PA6 = 引脚 31

> **不要在生产路径下手工短接 PA7 ↔ PA6**。本测试由 `test_spi.c` 内部自动
> 把 PA6 临时回退为 floating input (CNF=01, MODE=00),跑完恢复为 GP push-pull。
> 所有临时反转逻辑内聚在 `test_spi.c`,`led_pov.c` 生产代码保持纯净。

#### 软件

调用 `test_spi_loopback_blocking()`。函数内部:

1. 调 `led_pov_init()` —— Phase A pin mux 生效
2. PA6 CRL[27:24] 写 `0x4` (CNF=01 input floating, MODE=00 input)
3. 等 ≥ 1 ms (SysTick 锚点,真轮询 volatile)
4. 循环 3 次:发 `0x55`, `0xAA`, `0xF0`,每次发完读 SPI1->DR 回环
5. PA6 CRL[27:24] 恢复 `0x3` (CNF=00 GP PP, MODE=11 50MHz)

#### 观测

**Symbol-based**(gdb 内):

```gdb
print g_spi_test_rx[0]
print g_spi_test_rx[1]
print g_spi_test_rx[2]
print g_spi_test_phase
```

**Address-based**(probe-rs CLI):

```sh
probe-rs read --chip STM32F103RC b32 0x20000034 1   # rx[0..2] + padding
probe-rs read --chip STM32F103RC b32 0x20000030 1   # phase
```

**预期**

- `g_spi_test_rx[0]` = `0x55`
- `g_spi_test_rx[1]` = `0xAA`
- `g_spi_test_rx[2]` = `0xF0`
- `g_spi_test_phase` = `3`

#### 失败模式

| 实测 | 排查 |
|------|------|
| rx 全 `0xFF` | SCK 没驱动 → Phase A 的 PA5 字段不是 `0xB`,查 `0x40010800` 高 16 位 |
| rx 全 `0x00` | 杜邦线没接 / PA6 CRL 临时回退没生效 / SPI1 CR1 配置错(检查 `SPI1->CR1` 应含 BR_2 \| MSTR \| SSI \| SSM \| SPE) |
| rx 字节乱序/乱值 | SPI 时序问题 → 改 `SPI_CR1_CPHA` 位(本测试默认 CPHA=0,CPOL=0) |
| rx = tx 但 phase ≠ 3 | 函数没跑到最后 → 检查 `local_spi1_send_byte` BSY 自旋 |

---

### 3.3 Phase B2 —— DMA-driven loopback

#### 目的

确认 POV 生产路径完整 —— SPI1 + DMA1 ch3 TX + DMA1 ch2 RX + DMA1_Channel2
NVIC 中断 + ISR 强符号覆盖 weak 默认 handler。任何一环失败都会"推帧失败"。

#### 硬件

同 Phase B1(PA7 ↔ PA6 杜邦线)。注意:`test_spi_loopback_dma()` 函数起手
**重复** PA6 临时回退,跑完还原。

#### 软件

调用 `test_spi_loopback_dma()`。函数内部:

1. PA6 CRL 临时回退为 floating input
2. 使能 DMA1 时钟 (`RCC->AHBENR |= RCC_AHBENR_DMA1EN`)
3. 配 DMA1_Channel3 (TX):CCR = DIR | MINC | TCIE,CPAR = &SPI1->DR,CMAR = g_spi_test_tx,CNDTR = 3
4. 配 DMA1_Channel2 (RX):CCR = MINC | TCIE,CPAR = &SPI1->DR,CMAR = g_spi_dma_rx,CNDTR = 3
5. SPI1->CR2 开 TXDMAEN + RXDMAEN
6. NVIC enable DMA1_Channel2_IRQn,优先级 11
7. 同时 EN 双 DMA channel
8. busy-poll `g_spi_dma_done`(真轮询 volatile,合法)
9. PA6 CRL 恢复为 GP push-pull

`DMA1_Channel2_IRQHandler`(强符号)清 TCIF2,置 `g_spi_dma_done = 1`。

#### 观测

**Symbol-based**:

```gdb
print g_spi_dma_done
print g_spi_dma_rx[0]
print g_spi_dma_rx[1]
print g_spi_dma_rx[2]
```

**Address-based**:

```sh
probe-rs read --chip STM32F103RC b32 0x2000003C 1   # done
probe-rs read --chip STM32F103RC b32 0x20000034 1   # rx[0..2] (与 B1 同址)
```

> **地址 0x20000037 不是 4 字节对齐**。`probe-rs read b32 0x20000037 1` 会报
> "not aligned to 4 bytes"。改读 `0x20000034`(整体 4 字节读,后 3 字节就是 rx[0..2])。

**预期**

- `g_spi_dma_done` = `1`
- `g_spi_dma_rx[0]` = `0x55`
- `g_spi_dma_rx[1]` = `0xAA`
- `g_spi_dma_rx[2]` = `0xF0`
- `g_isr_count_systick`(`0x2000000C`)持续涨(系统未 lockup)

#### 失败模式

| 实测 | 排查 |
|------|------|
| `done` 一直 `0` | 查 `0x40020008` DMA ISR 看 TCIF2,查 `0x4002001C` DMA1_Channel2 CCR 看 EN,查 `0x40020030` DMA1_Channel3 CCR 看 EN |
| `done = 1` 但 rx 全 `0` | RX DMA 方向错 (DIR 位应该 = 0 for periph→memory),或 SPI1 CR2 RXDMAEN 未开 |
| `done = 1` 但 rx 全 `0xFF` | 同 Phase B1 SCK 未驱动,Phase A 失败 |
| `done = 1` 但 rx 乱序 | DMA priority/size 错(本测试 8-bit,MSB first;SPI1 CR1 LSBFIRST=0) |

---

### 3.4 Phase C —— TIM7 100 µs + PB0 toggle

#### 目的

验证 TIM7 ISR 在激进周期 100 µs 下能稳定翻转 GPIO(供示波器观测 5 kHz 方波)。
100 µs 都撑得住,生产路径 250 µs 自然也撑得住。

#### 硬件

- **PB0** 接板上 LED(板上原 Phase 0 验证过)
- **可选**:示波器探 PB0,验证 5 kHz ± 5% 方波、占空比 ~50%
- **不需要** PA8 接线 —— PA8 是蜂鸣器,默认 TIM1_CH1,故意不动

#### 软件

调用 `test_tim7_start()`。函数内部:

1. TIM7->CR1 清 CEN(停)
2. PSC = 71, ARR = 99, CNT = 0(100 µs 周期,10 kHz update)
3. EGR = TIM_EGR_UG(立即装载 PSC/ARR)
4. NVIC enable TIM7 中断(原本 led_pov_init 已设,但确认一次)
5. TIM7->CR1 置 CEN

`TIM7_IRQHandler`(强符号覆盖 `c/drivers/it.c` 的 weak 默认)在每次 update interrupt:

- 清 UIF (TIM7->SR = ~TIM_SR_UIF)
- g_isr_count_tim7++
- 翻转 PB0(GPIOB->BSRR bit 0 / bit 16)

#### 观测

**Symbol-based**:

```gdb
print g_isr_count_tim7
```

**Address-based**:

```sh
probe-rs read --chip STM32F103RC b32 0x20000014 1
```

**预期**

- 跑 5 秒,`g_isr_count_tim7` 涨 ~50000 (10 kHz × 5 s = 50000)
- PB0 LED 半亮(肉眼积分,占空比 50%)
- 蜂鸣器 **沉默**(没碰 PA8)
- 示波器(可选):5 kHz ± 5% 方波

#### 失败模式

| 实测 | 排查 |
|------|------|
| 计数不增 | TIM7 时钟未开,查 `0x4002101C` RCC APB1ENR 看 bit 5 (TIM7EN) |
| 计数涨但 LED 不闪 | PB0 GPIO 没配成 output,查 `0x40010C00` GPIOB->CRL bit [3:0] = `0x3` |
| 蜂鸣器发声 | 不可能 —— 本测试故意不动 PA8。若仍发声,检查 PA8 没被车板 firmware 误启用 |
| 频率偏差 > 5% | 时钟不准,查 `0x40021000` RCC->CR 看 HSE 是否稳定(应 HSE=8 MHz × 9 PLL = 72 MHz) |

#### 生产路径不兼容说明

`test_tim7.c` 提供 `TIM7_IRQHandler` 强符号,**必须**先在 `c/drivers/it.c`
把同名函数标为 `__attribute__((weak))` 才能覆盖。生产 build 已把 weak 属性移除,
接入测试时临时加回,跑完恢复。

---

### 3.5 Phase D —— EXTI3 PC3 上升沿(夹具在 `c/drivers/vibration.c`)

#### 目的

验证 PC3 → EXTI3 → NVIC 整条振动信号链通。

#### 硬件

**1 根杜邦线:** Pin 6 (PC3/VIBE_SIG) ↔ Pin 2 (GND)
(板丝印在排针上)。`board.h` 注释"Pin 7 (TIM7_TICK)"是内部资源,物理不存在。

> 板上 PC3 默认无外部上拉。`vibration_init()` 必须配内部上拉(已在生产路径修过)。

#### 软件

`vibration_init()`(`c/drivers/vibration.c`):

1. 使能 GPIOC 时钟
2. PC3 CRL[15:12] 写 `0x8` (CNF=10 input-pull, MODE=00)
3. PC3 ODR bit 3 = 1 (内部上拉)
4. AFIO_EXTICR1 = 0x00002000 (PC3 → EXTI3)
5. EXTI_RTSR bit 3 = 1 (上升沿)
6. EXTI_IMR bit 3 = 1 (中断使能)
7. NVIC enable EXTI3_IRQn

`EXTI3_IRQHandler`(`c/drivers/it.c`):

- 清 EXTI->PR bit 3
- g_isr_count_exti3++
- 调 `vibration_exti_isr()`

#### 操作序列(关键)

1. 杜邦线悬空,记录 `g_isr_count_exti3` = X (典型 `0`)
2. 碰 Pin 2 (GND) ~100 ms ← **短接 = 下降沿**,EXTI3 不响应
3. 松开 ← **释放 = 内部上拉拉回高 = 上升沿**,EXTI3 触发 ISR
4. 等 ~300 ms(过 5 ms 软消抖,见 `vibration_consume()`)
5. 再读 `g_isr_count_exti3`,期望 ≥ X + 1

**为什么"松开"才是关键**:EXTI3 配置 RTSR=1, FTSR=0,只响应上升沿。

#### 观测

```sh
probe-rs read --chip STM32F103RC b32 0x20000018 1   # 碰松前后各一次
```

**预期** 差值 ≥ 1(典型 1 ~ 9,见下)。

#### 机械弹跳现象(非 bug)

实测单次"碰-松"操作,`g_isr_count_exti3` 可能跳 4 ~ 9 次而非 1 次。原因:
STM32 内置 Schmitt trigger 在金属触点接触电阻跳变时,把一次物理动作识别为
多次独立边沿。**这是真实硬件常态,不是 bug**。`vibration_consume()` 的 5 ms
软消抖会把 raw N 个 ISR 合并成 ~1 个有效振动事件。

#### 失败模式

| 实测 | 排查 |
|------|------|
| 计数从不增 | AFIO_EXTICR1 (`0x40010400`) 读是否 = `0x00002000`;EXTI_RTSR (`0x40010408`) bit 3 = 1;EXTI_IMR (`0x40010400` 后半) bit 3 = 1;NVIC ISER bit 9 = 1 |
| 计数增但差值总是 N > 9 | 杜邦线触点不良 / 板震动干扰,加 100 nF 去耦电容到 PC3-GND |
| 碰松时 PC3 电平不归高 | 内部上拉未配,查 GPIOC->CRL bit [15:12] = `0x8`,GPIOC->ODR bit 3 = 1 |

---

## 4. 调试速查表

### 4.1 gdb 链路(推荐用于 SRAM 读)

```sh
# Terminal A
probe-rs gdb --chip STM32F103RC zig-out/bin/wobbly-stick-light

# Terminal B
arm-none-eabi-gdb zig-out/bin/wobbly-stick-light
(gdb) target remote localhost:1337
(gdb) monitor reset halt
(gdb) load
(gdb) continue
# halt (Ctrl-C) 后:
(gdb) print g_spi_test_rx[0]
(gdb) print g_spi_test_phase
(gdb) print g_isr_count_tim7
```

### 4.2 probe-rs CLI(用于 peripheral 寄存器)

probe-rs gdbserver **默认不含 peripheral 区**(0x40000000-0x5FFFFFFF)。
读 GPIOA->CRL 等寄存器必须用 probe-rs CLI:

```sh
probe-rs read --chip STM32F103RC b32 0x40010800 2   # GPIOA CRL
probe-rs read --chip STM32F103RC b32 0x40001400 1   # TIM7 CR1
probe-rs read --chip STM32F103RC b32 0x40010400 1   # AFIO_EXTICR1
probe-rs read --chip STM32F103RC b32 0x40010414 1   # EXTI RTSR
probe-rs read --chip STM32F103RC b32 0x40020008 1   # DMA1 ISR
probe-rs read --chip STM32F103RC b32 0x4002001C 1   # DMA1 ch2 CCR
probe-rs read --chip STM32F103RC b32 0x40020030 1   # DMA1 ch3 CCR
```

### 4.3 probe-rs 0.31 已知坑

- **CMSIS-DAP multi-transfer bug**:BUPT v2025 探测器固件对 DAP multi-transfer
  支持不全,某些 `probe-rs read --count N > 1` 报 "Only 1/2 transfers executed"。
  - 解 1:加 `--chip STM32F103RC` 跳过自动探测
  - 解 2:拆成多次 single read
  - 解 3:换 gdb 链路(gdb remote protocol 走单 transfer per memory read)

- **gdb peripheral 不可读**:probe-rs gdbserver 默认 memory map 不含 0x40000000 区。
  读 peripheral 必须走 probe-rs CLI。

- **gdb 对齐报错**:`x/wx 0x20000037` 报 "not aligned to 4 bytes"。
  改读 `0x20000034`,或用符号读 (`print g_spi_dma_rx[0]`)。

### 4.4 已知 SRAM 地址表(LOOP 4 实测 — 2026-07-07)

> **LOOP 4 变更**:
> 1. `c/drivers/led_pov.c` `s_font` 默认初始化由 NULL 改为 `FONT_LKM`,
>    把 `s_font` 从 .bss 移到 .data，并保证 FONT_LKM 不被 LTO GC。
> 2. `c/drivers/font_pov.c` FONT_LKM/FONT_RAINBOW/FONT_ALL_RED 各 120 B
>    实字模数据填入（见 § 4.5）。
> 3. 整体 .data + .bss 段因 s_font 占据 4 B、g_LED_Show_RAM 占 24 B、
>    g_LED_key_down/s_col 各 1 B 而后移；原 .data/bss 测试符号
>    `g_spi_test_tx/g_spi_test_phase/g_spi_test_rx/g_spi_dma_rx/g_spi_dma_done`
>    已随 c/tests/ 移出 production build 而消失。
> 详细漂移见"LOOP 1 → LOOP 4 漂移表"。

| 变量 | 类型 | 地址 | 大小 | 验证 Phase |
|------|------|------|------|------------|
| `SystemCoreClock` | .data | `0x20000000` | 4 | 系统时钟（HAL） |
| `s_font` (=FONT_LKM) | .data | `0x20000004` | 4 | 默认字模指针 |
| `g_systick_ms` | .bss | `0x20000008` | 4 | 系统存活 |
| `g_isr_count_systick` | .bss | `0x2000000C` | 4 | 系统存活 |
| `g_isr_count_tim7` | .bss | `0x20000010` | 4 | C |
| `g_isr_count_exti3` | .bss | `0x20000014` | 4 | D |
| `g_LED_key_down` | .bss | `0x20000018` | 1 | 过零围栏标志（LOOP 3） |
| `g_LED_Show_RAM[24]` | .bss | `0x20000019` | 24 | led_pov 帧缓冲（LOOP 2） |
| `s_state` | .bss | `0x20000034` | 4 | led_pov 状态机 |
| `s_cat` | .bss | `0x20000038` | 1 | led_pov cat 索引 |
| `s_col` | .bss | `0x20000039` | 1 | led_pov 列索引（LOOP 3） |
| `s_pending` | .bss | `0x2000003C` | 4 | 振动事件标志 |
| `s_trigger_ms` | .bss | `0x20000040` | 4 | 最近触发时间戳 |

#### 字模常量在 Flash 的地址（LOOP 4 新可见 — 因 s_font 引用 FONT_LKM 而保住）

| 符号 | 地址 | 大小 | 备注 |
|------|------|------|------|
| `FONT_LKM`    | `0x0800093B` | 120 (0x78) | L=蓝 K=绿 M=红 |
| `FONT_RAINBOW`| `0x080009B3` | 120 (0x78) | 蓝→绿→红横向渐变 |
| `FONT_ALL_RED`| `0x08000A2B` | 120 (0x78) | 纯红填充（颜色校准） |
| `POV_ROW_COLOR[3]` | `0x08000AA3` | 3 | 行→通道查表（板级实现） |

#### LOOP 1 → LOOP 4 漂移表

| 变量 | LOOP 1 | LOOP 4 | drift | 备注 |
|------|--------|--------|-------|------|
| `phase` | `0x20000000` | `0x20000008` | +8 | + SystemCoreClock(4) + s_font(4) |
| `g_systick_ms` | `0x2000000C` | `0x2000000C` | 0 | g_spi_test_tx[3] 移除恰抵销 s_font(4) |
| `g_isr_count_systick` | `0x20000010` | `0x20000010` | 0 | 同上 |
| `g_isr_count_tim7` | `0x20000014` | `0x20000014` | 0 | 同上 |
| `g_isr_count_exti3` | `0x20000018` | `0x20000018` | 0 | 同上 |
| `g_LED_Show_RAM` | (无) | `0x2000001C` | NEW (24B) | LOOP 2 新增 |
| `s_state` | `0x2000001C` | `0x20000034` | +24 | = + g_LED_Show_RAM(24) |
| `s_cat` | `0x20000020` | `0x20000038` | +24 | 同上 |
| `s_col` | (无) | `0x20000039` | NEW (1B) | LOOP 3 新增 |
| `g_LED_key_down` | (无) | `0x2000003A` | NEW (1B) | LOOP 3 新增 |
| `s_font` | (无) | `0x20000004` | NEW (4B .data) | LOOP 4 默认指向 FONT_LKM |
| `s_pending` | `0x20000028` | `0x2000003C` | +20 | = +g_LED_Show_RAM(24) -g_spi_test_phase(4) |
| `s_trigger_ms` | `0x2000002C` | `0x20000040` | +20 | 同上 |

### 4.5 LOOP 4 字模数据形状（手绘 L/K/M）

每个字模 = `uint8_t[POV_ROW_NUM=3][POV_COL_NUM=40]`，每字节 1 列 8 颗 LED 的位图
（bit i = 该列第 i 颗 LED 是否点亮本行通道颜色）。

| 字模 | 行 (颜色) | 字节 | 数据模式（手绘 ASCII） |
|------|-----------|------|----------------------|
| **L** (row 0 = 蓝) | cols 0..14 = `0xFF`, col 15 = `0x01`, cols 16..39 = `0x00` | 竖+底 | `█ █ █ █ █ █ █ █` |
| **K** (row 1 = 绿) | cols 16..23 = `0xFF`, col 24 = `0x0F`, col 25 = `0x07`, col 26 = `0x03`, col 27 = `0x01`, col 28 = `0x80`, col 29 = `0xC0`, col 30 = `0xE0`, col 31 = `0xF0` | 竖+双斜 | `█ ╲ ╱<` |
| **M** (row 2 = 红) | cols 32 = `0xFF`, col 33 = `0xC3`, col 34 = `0xE7`, col 35 = `0xFF`, col 36 = `0xFF`, col 37 = `0xE7`, col 38 = `0xC3`, col 39 = `0xFF` | 双竖+V | `█ ╱ ╲ ╱ ╲ █` |

字体尺寸限制：M 仅 8 列（POV_COL_NUM=40, 留给 M 的只有 32..39 = 8 列），其他
cols 在 M 行恒为 0x00。L/K 各占 16 列，余 8 列（M 占）也保持 0x00。

---

## 5. 为什么用"改名到 c/tests/"而不是"删除"

本次 commit 选择保留测试夹具。原因:

1. **回归验证成本**:POV 集成时一旦"屏幕不亮",5 分钟可重跑这 5 个 Phase 排除底层
2. **历史证据**:Phase A 真 bug(GPIOA->CRL 漏配)、Phase D 真 bug(PC3 上拉漏配)
   的修复证据仍在代码里,删了就没法对照
3. **设计文档引用**:`docs/session-log/README.md` § 12 大量引用 `test_spi.c` /
   `test_tim7.c` 的实现细节,删除会让历史 commit 与设计报告脱钩

代价:

- `build.zig` 多 2 行注释(说明本目录的 status)
- `src/main.zig` Phase 0 已是最终形态(无 test 函数调用)

---

## 6. 相关文档

- `docs/session-log/README.md` § 12 —— 本次 5 Phase 验证的完整会话记录
- `docs/session-log/README.md` § 12.7 —— probe-rs 0.31 CMSIS-DAP bug 工作流
- `docs/session-log/README.md` § 12.8 —— 完整 SRAM 地址表
- `docs/session-log/README.md` § 12.10 —— volatile 真轮询 vs 优化屏障辨析
- `~/.claude/plans/stm32-pov-led-pov-tick-sequential-nygaard.md` —— 5 Phase 验证原始计划