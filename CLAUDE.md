# wobbly-stick-light — 摇摇棒固件

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
