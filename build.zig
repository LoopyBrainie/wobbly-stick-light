const std = @import("std");

pub fn build(b: *std.Build) void {
    // ── Target: Cortex-M3, thumb, bare-metal ──
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m3 },
        .os_tag = .freestanding,
        .abi = .eabi,
    });

    const optimize = b.standardOptimizeOption(.{});

    // ── Firmware executable ──
    const exe = b.addExecutable(.{
        .name = "wobbly-stick-light",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // ── Assembly: startup (vector table + Reset_Handler) ──
    // In Zig 0.16, addAssemblyFile is on Module, not Compile.
    exe.root_module.addAssemblyFile(b.path("c/startup/startup_stm32f10x_hd.s"));

    // ── C: system clock init ──
    // In Zig 0.16, addCSourceFile is on Module, not Compile.
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

    // ── Linker script ──
    exe.setLinkerScript(b.path("c/ld/stm32f103rct6.ld"));

    // ── Install the firmware .elf ──
    b.installArtifact(exe);
}
