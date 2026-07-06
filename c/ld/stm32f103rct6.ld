/* ────────────────────────────────────────────────────────────
 * Linker script for STM32F103RCT6 (Cortex-M3)
 *
 * Memory layout:
 *   Flash: 256 KB @ 0x08000000  (rx)
 *   SRAM:   48 KB @ 0x20000000  (rwx)
 *
 * Output: ELF for bare-metal (no OS, no runtime loader)
 * ─────────────────────────────────────────────────────────── */

MEMORY
{
    FLASH  (rx) : ORIGIN = 0x08000000, LENGTH = 256K
    SRAM   (rwx): ORIGIN = 0x20000000, LENGTH = 48K
}

ENTRY(Reset_Handler)

SECTIONS
{
    /* ── Vector table (must be at flash origin) ── */
    .vector_table : ALIGN(4)
    {
        KEEP(*(.vector_table))
    } > FLASH

    /* ── Code + read-only data ── */
    .text : ALIGN(4)
    {
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > FLASH

    /* ── Pre-initialized data ── */
    .data : ALIGN(4)
    {
        _sidata = LOADADDR(.data);
        _sdata = .;
        *(.data)
        *(.data.*)
        . = ALIGN(4);
        _edata = .;
    } > SRAM AT > FLASH

    /* ── Zero-initialized data ── */
    .bss : ALIGN(4)
    {
        _sbss = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > SRAM

    /* ── Stack (grows down from end of SRAM) ── */
    .stack (NOLOAD) : ALIGN(8)
    {
        _sstack = .;
        . = . + 0x400;              /* 1 KB stack */
        . = ALIGN(8);
        _estack = .;
    } > SRAM

    /* ── Heap (optional, remainder of SRAM) ── */
    .heap (NOLOAD) : ALIGN(8)
    {
        _sheap = .;
        . = . + 0x200;              /* 512 B heap */
        . = ALIGN(8);
        _eheap = .;
    } > SRAM

    /* ── Debugging symbols ── */
    _end = .;
}
