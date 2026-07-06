# wobbly-stick-light — 摇摇棒固件

## 嵌入式编码规范（铁律）

- **延时禁止用空循环** `while (i < N) : (i += 1) {}`。
  - 在 `-Os`/`-O2` 下编译器可证 `i` 无副作用，整段循环被删；即便不被删，延时长度也依赖时钟频率和指令周期数。
  - **必须用 SysTick (1 ms tick) 或 TIMx 定时器**。SysTick 已在 `board_init()` 开启（72 MHz / 1000 Hz），业务循环可直接 `volatile` 读 `SysTick->VAL` 做 ms 级 sleep。
  - 仅允许的例外：临时 debug 代码也必须用 `asm volatile("nop")` 作副作用锚点，**禁止**用 `_ = SysTick_VAL.*` 这种"为了防优化而读 volatile 寄存器"的方式——会模糊"我在读 SysTick"的意图。`asm volatile("nop")` 意图清晰且 portable。提交前必须替换为定时器方案。

## 构建

```sh
zig build                    # 编译 Zig + C → .elf
zig build -Doptimize=ReleaseSmall  # 优化版本
llvm-objdump -d zig-out/bin/wobbly-stick-light.elf | head -50  # 检查反汇编
```

## 烧录

```sh
probe-rs run zig-out/bin/wobbly-stick-light.elf --chip STM32F103RC
```

## 架构

| 层 | 语言 | 文件 |
|----|------|------|
| 业务逻辑 | Zig | `src/main.zig` |
| 控制算法 | Zig | `src/control/` |
| 类型桥接 | Zig | `src/c_bridge.zig` |
| 板级驱动 | C | `c/drivers/` |
| 芯片 HAL | C | `c/hal/` |
| 启动/中断 | ASM | `c/startup/startup_stm32f10x_hd.s` |

## 开发流程

1. Keil 验证外设驱动 → 2. 迁移文件到 Zig 项目 → 3. `zig build` 编译 → 4. probe-rs 烧录

## 工具链

全部由 Zig 内置：`zig cc` (Clang) 编译 C/ASM，`lld` 链接，无需 ARM GNU Toolchain。

## Reference：`car2025_final/` 文件树与功能说明

> STM32CubeMX 工程，针对 STM32F103RC。`Core/` 是用户教程代码，`Drivers/` 是 ST 官方 HAL/CMSIS 库（标准库，无需逐文件说明）。
> 整体是一台"循迹避障智能车"——IMU/磁力计/超声/编码器/红外多传感融合，PWM 驱动两路电机 + 舵机，菜单 + UART 命令行 + OLED 显示。

### 工程元文件
```
car2025_final/
├── car2025_final.ioc          # STM32CubeMX 配置源文件（pin/clock/外设定义）
├── .mxproject                  # CubeMX 工具链工程
├── MDK-ARM/                    # Keil uVision5 工程文件 + startup_stm32f103xe.s
├── Drivers/                    # ST 官方 HAL + CMSIS（标准库，跳过）
└── Core/
```

### 应用入口 & 系统初始化
```
Core/Src/main.c                # main()、HAL_Init、SystemClock_Config (HSE 72MHz PLL×9)
Core/Src/stm32f1xx_it.c        # 所有中断服务：DMA/UART/TIM/EXTI/ADC，含 UART IDLE 处理
Core/Src/stm32f1xx_hal_msp.c   # HAL MSP 钩子（时钟/引脚复用初始化）
Core/Inc/main.h                # 引脚别名 (LED_*/BTN*/ECHO_*/TRIG_*/BEEP_*)
Core/Inc/stm32f1xx_it.h        # 中断处理函数声明
Core/Inc/stm32f1xx_hal_conf.h  # HAL 模块开关（ADC/SPI/TIM/UART/DMA/GPIO/RCC）
```

### 业务编排（系统级）
```
Core/Inc/common.h              # 全局枚举：系统模式/通信目标 + 设备唯一 ID 基地址
Core/Src/common.c              # System_Init() + UserTasks() 主循环：调各模块 Process()
Core/Inc/ctrl_menu.h           # 树形菜单结构与回调签名
Core/Src/ctrl_menu.c           # 多级菜单实现，按钮翻页+回车回调 OLED 显示
```

### 外设驱动绑定（CubeMX 自动生成）
```
Core/Inc|src/gpio.c            # 全部 GPIO 初始化 + EXTI 按钮/超声回波中断
Core/Inc|src/dma.c             # DMA1 时钟 + 5 通道 NVIC
Core/Inc|src/adc.c             # ADC1_IN10（红外循迹模拟量），DMA 半字搬运
Core/Inc|src/spi.c             # SPI1（LED 点阵）+ SPI2（IMU QMI8658）主模式
Core/Inc|src/i2c.c             # I2C2@100kHz（OLED + QMC5883 磁力计共用）
Core/Inc|src/tim.c             # TIM1=蜂鸣器PWM / TIM2/4=PWM+编码器 / TIM3/8=编码器
                               # / TIM5=超声us计时 / TIM6=100Hz系统节拍 / TIM7=音乐节拍
Core/Inc|src/usart.c           # USART1=115200 调试口 / USART3=115200 IO 口
```

### 板级 / 应用驱动
```
Core/Inc|src/motor_drive.c     # 双电机+舵机 PWM 控制（DRIVE_MOTO_NUM=2, STEER_MOTO_NUM=2）
Core/Inc|src/speed_encoder.c   # TIM3/TIM8 编码器测速 + 累计平均显示到 OLED
Core/Inc|src/ir_track.c        # 5 路红外循迹 ADC 扫描+白/黑阈值标定+轨道偏差表查
Core/Inc|src/ultrasonicwave.c  # 前后两路 HC-SR04 测距，TIM5 微秒计时+状态机
Core/Inc|src/i2c_gpio.c        # 软件 I2C（bit-bang，备选 HAL 之外的另一种实现）
Core/Inc|src/qmc5883.c         # I2C 三轴磁力计读数 + 角度计算（未接入主流程）
Core/Inc|src/qmi8658.c         # SPI 六轴 IMU（含自检/校准/WoM/TAP/Pedometer/FIFO，可裁剪）
Core/Inc|src/oled_i2c.c        # 128×32 OLED（SSD1306）ASCII 字模显示
Core/Inc|src/led.c             # 四向指示灯 LED_FL/FR/BL/BR 的位操作封装
Core/Inc|src/led_show.c        # SPI 驱动的 LED 点阵动画（g_ShowData 帧表 + 扫描）
Core/Inc|src/music.c           # 蜂鸣器按预存乐谱播放（g_music_tone/g_music_note）
```

### 通信协议层
```
Core/Inc|src/uart_dma.c        # UART DMA + IDLE 接收环形缓冲 + 接收回调分发
Core/Inc|src/user_command.c    # "@cmd|arg&" 格式命令解析（支持 INT/FLOAT/U8/U16 参数）
```

### 关键全局常量与依赖
- `DRIVE_MOTO_NUM=2`, `STEER_MOTO_NUM=2`（`motor_drive.h`）
- `IR_CHANNEL_NUM=5`, `ADC_THRESHOLD=3000`（`ir_track.h`）
- `ULTRAWAVE_NUM=2`, `MAX_DRIVE_PWM=4000`, `MOTO_PWM_FREQ=50Hz`（舵机）
- `SPEED_ENCODER_NUM=2`, `PULSE_PER_CIRCLE=13*4*48`, `WHEEL_SIZE=65mm`（`speed_encoder.h`）
- `g_car_track_flag`, `g_car_ctrl_flag` 等全局驱动业务耦合标记（横跨 `ir_track`/`car_control`）
