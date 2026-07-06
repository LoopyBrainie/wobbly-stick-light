const std = @import("std");

pub fn build(b: *std.Build) void {
    // ── Target: Cortex-M3, thumb, bare-metal ──
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m3 },
        .os_tag = .freestanding,
        .abi = .eabi,
    });

    // 固件无 Debug 价值（没 gdb，ELF 仅供 probe-rs 烧录），直接 ReleaseSmall 避免 58KB 溢出
    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    // ── Shared C flags: 全部 6 个 C 源用同一组 cflags ──
    const cflags: []const []const u8 = &.{
        "-mcpu=cortex-m3",
        "-mthumb",
        "-Os",
        "-ffreestanding",
        "-fno-common",
        "-DSTM32F103xE",        // 触发 stm32f1xx.h 包含 stm32f103xe.h
        "-I", "c/hal",          // stm32f103xe.h / stm32f1xx.h / shim
        "-I", "c/hal/cmsis",    // core_cm3.h / cmsis_compiler.h / cmsis_armclang.h
        "-I", "c/drivers",      // board.h / led_pov.h / vibration.h / font_pov.h
        // 不传 -DHSE_VALUE=8000000: system_stm32f10x.c 内部已设
    };

    // ── Firmware executable ──
    const exe = b.addExecutable(.{
        .name = "wobbly-stick-light",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = false,        // 保留 .symtab/.strab 让 probe-rs gdb 能 print g_systick_ms
        }),
    });

    // ── Assembly: RTE startup (vector table + Reset_Handler → SystemInit → __main) ──
    // 使用 RTE 提供的 STM32F103RC 专用 .s (1094 行, 配 358 行 .s)
    exe.root_module.addAssemblyFile(b.path("c/startup/startup_stm32f10x_hd.s"));

    // ── C 源: RTE system (F103RC, 1094 行, SetSysClockTo72) + 5 驱动 ──
    exe.root_module.addCSourceFile(.{ .file = b.path("c/hal/system_stm32f10x.c"),  .flags = cflags });
    exe.root_module.addCSourceFile(.{ .file = b.path("c/drivers/board_init.c"),   .flags = cflags });
    exe.root_module.addCSourceFile(.{ .file = b.path("c/drivers/it.c"),           .flags = cflags });
    exe.root_module.addCSourceFile(.{ .file = b.path("c/drivers/led_pov.c"),      .flags = cflags });
    exe.root_module.addCSourceFile(.{ .file = b.path("c/drivers/vibration.c"),    .flags = cflags });
    exe.root_module.addCSourceFile(.{ .file = b.path("c/drivers/font_pov.c"),     .flags = cflags });

    // ── Linker script ──
    exe.setLinkerScript(b.path("c/ld/stm32f103rct6.ld"));

    // ── Entry: 由 .s 的 Reset_Handler 接手，不要让 zig 找 _start ──
    exe.entry = .disabled;

    // ── Install the firmware .elf ──
    b.installArtifact(exe);
}
