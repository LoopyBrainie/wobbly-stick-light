param(
    [string]$ElfPath = "D:\myProject\wobbly-stick-light\zig-out\bin\wobbly-stick-light"
)

$ErrorActionPreference = "Stop"
$bytes = [System.IO.File]::ReadAllBytes($ElfPath)

function Read-CString($off) {
    $sb = New-Object System.Text.StringBuilder
    while ($off -lt $bytes.Length -and $bytes[$off] -ne 0) {
        [void]$sb.Append([char]$bytes[$off])
        $off++
    }
    return $sb.ToString()
}

function Hex($v) { return "0x" + $v.ToString("X8") }

# Parse ELF32 program headers
$e_phoff = [BitConverter]::ToUInt32($bytes, 28)
$e_phentsize = [BitConverter]::ToUInt16($bytes, 42)
$e_phnum = [BitConverter]::ToUInt16($bytes, 44)

Write-Host "===== Program Headers ====="
$load_segs = @()
for ($i = 0; $i -lt $e_phnum; $i++) {
    $off = $e_phoff + ($i * $e_phentsize)
    $p_type = [BitConverter]::ToUInt32($bytes, $off)
    $p_offset = [BitConverter]::ToUInt32($bytes, $off + 4)
    $p_vaddr = [BitConverter]::ToUInt32($bytes, $off + 8)
    $p_paddr = [BitConverter]::ToUInt32($bytes, $off + 12)
    $p_filesz = [BitConverter]::ToUInt32($bytes, $off + 16)
    $p_memsz = [BitConverter]::ToUInt32($bytes, $off + 20)
    $p_flags = [BitConverter]::ToUInt32($bytes, $off + 24)

    $typeName = switch ($p_type) {
        0 { "NULL" }
        1 { "LOAD" }
        2 { "DYNAMIC" }
        3 { "INTERP" }
        4 { "NOTE" }
        6 { "PHDR" }
        0x6474e550 { "GNU_EH_FRAME" }
        0x6474e551 { "GNU_STACK" }
        0x6474e552 { "GNU_RELRO" }
        default { ("0x" + $p_type.ToString("X")) }
    }

    Write-Host ("  [{0}] type={1} off={2} vaddr={3} filesz={4} memsz={5} flags={6}" -f $i, $typeName, (Hex $p_offset), (Hex $p_vaddr), (Hex $p_filesz), (Hex $p_memsz), (Hex $p_flags))

    if ($p_type -eq 1) {
        $load_segs += [pscustomobject]@{
            Offset = $p_offset; VAddr = $p_vaddr; PAddr = $p_paddr;
            FileSz = $p_filesz; MemSz = $p_memsz; Flags = $p_flags
        }
    }
}

# Section headers
$e_shoff = [BitConverter]::ToUInt32($bytes, 32)
$e_shentsize = [BitConverter]::ToUInt16($bytes, 46)
$e_shnum = [BitConverter]::ToUInt16($bytes, 48)
$e_shstrndx = [BitConverter]::ToUInt16($bytes, 50)
$sections = @()
for ($i = 0; $i -lt $e_shnum; $i++) {
    $off = $e_shoff + ($i * $e_shentsize)
    $sh_name = [BitConverter]::ToUInt32($bytes, $off)
    $sh_type = [BitConverter]::ToUInt32($bytes, $off + 4)
    $sh_offset = [BitConverter]::ToUInt32($bytes, $off + 16)
    $sh_size = [BitConverter]::ToUInt32($bytes, $off + 20)
    $sh_link = [BitConverter]::ToUInt32($bytes, $off + 24)
    $sh_entsize = [BitConverter]::ToUInt32($bytes, $off + 36)
    $sections += [pscustomobject]@{
        Index = $i; Type = $sh_type; Offset = $sh_offset; Size = $sh_size;
        Link = $sh_link; Entsize = $sh_entsize; NameIdx = $sh_name
    }
}
$shstrtab_sec = $sections[$e_shstrndx]
$shstrtab_off = $shstrtab_sec.Offset
foreach ($s in $sections) {
    $s | Add-Member -NotePropertyName Name -NotePropertyValue (Read-CString ($shstrtab_off + $s.NameIdx)) -Force
}

# File offset -> virtual address
function OffsetToVAddr($off) {
    foreach ($seg in $load_segs) {
        if ($off -ge $seg.Offset -and $off -lt ($seg.Offset + $seg.FileSz)) {
            return ($seg.VAddr + ($off - $seg.Offset))
        }
    }
    return $null
}

# Read .vector_table
$vt = $sections | Where-Object { $_.Name -eq ".vector_table" } | Select-Object -First 1
Write-Host ""
Write-Host "===== Vector Table (.vector_table) ====="
Write-Host ("  File offset: " + (Hex $vt.Offset) + " size: " + (Hex $vt.Size))
$vt_base_vaddr = OffsetToVAddr($vt.Offset)
Write-Host ("  Virtual base: " + (Hex $vt_base_vaddr))

$entries = @()
for ($i = 0; $i -lt ($vt.Size / 4); $i++) {
    $entry = [BitConverter]::ToUInt32($bytes, $vt.Offset + ($i * 4))
    $vaddr = $vt_base_vaddr + ($i * 4)
    $entries += [pscustomobject]@{
        Idx = $i; VAddr = $vaddr; Target = $entry
    }
}

Write-Host ""
Write-Host "--- System Exceptions (0..15) ---"
$sysExcNames = @(
    "Initial_SP", "Reset_Handler", "NMI_Handler", "HardFault_Handler",
    "MemManage_Handler", "BusFault_Handler", "UsageFault_Handler",
    "Reserved_7", "Reserved_8", "Reserved_9", "Reserved_10", "SVCall_Handler",
    "DebugMon_Handler", "Reserved_13", "PendSV_Handler", "SysTick_Handler"
)
for ($i = 0; $i -lt 16 -and $i -lt $entries.Count; $i++) {
    $e = $entries[$i]
    $nm = if ($i -lt $sysExcNames.Count) { $sysExcNames[$i] } else { "SysExc_$i" }
    Write-Host ("  [{0,2}] {1,-22} @ {2} -> {3}" -f $i, $nm, (Hex $e.VAddr), (Hex $e.Target))
}

Write-Host ""
Write-Host "--- IRQs (16..) ---"
$irqNames = @{
    0="WWDG"; 1="PVD"; 2="TAMPER"; 3="RTC"; 4="FLASH"; 5="RCC"; 6="EXTI0"; 7="EXTI1";
    8="EXTI2"; 9="EXTI3"; 10="EXTI4"; 11="DMA1_Channel1"; 12="DMA1_Channel2";
    13="DMA1_Channel3"; 14="DMA1_Channel4"; 15="DMA1_Channel5"; 16="DMA1_Channel6";
    17="DMA1_Channel7"; 18="ADC1_2"; 19="USB_HP_CAN1_TX"; 20="USB_LP_CAN1_RX0";
    21="CAN1_RX1"; 22="CAN1_SCE"; 23="EXTI9_5"; 24="TIM1_BRK"; 25="TIM1_UP";
    26="TIM1_TRG_COM"; 27="TIM1_CC"; 28="TIM2"; 29="TIM3"; 30="TIM4";
    31="I2C1_EV"; 32="I2C1_ER"; 33="I2C2_EV"; 34="I2C2_ER"; 35="SPI1";
    36="SPI2"; 37="USART1"; 38="USART2"; 39="USART3"; 40="EXTI15_10";
    41="RTCAlarm"; 42="USBWakeup"; 43="TIM8_BRK"; 44="TIM8_UP"; 45="TIM8_TRG_COM";
    46="TIM8_CC"; 47="ADC3"; 48="FSMC"; 49="SDIO"; 50="TIM5";
    51="SPI3"; 52="UART4"; 53="UART5"; 54="TIM6"; 55="TIM7";
    56="DMA2_Channel1"; 57="DMA2_Channel2"; 58="DMA2_Channel3"; 59="DMA2_Channel4_5"
}
for ($i = 16; $i -lt $entries.Count; $i++) {
    $irq = $i - 16
    $e = $entries[$i]
    $nm = if ($irqNames.ContainsKey($irq)) { $irqNames[$irq] } else { ("IRQ_" + $irq) }
    Write-Host ("  [{0,2}] {1,-22} @ {2} -> {3}" -f $i, $nm, (Hex $e.VAddr), (Hex $e.Target))
}

Write-Host ""
Write-Host "===== Section Runtime Addresses ====="
foreach ($s in $sections) {
    if ($s.Name -in @(".text", ".data", ".bss", ".vector_table", ".stack", ".heap", ".ARM.exidx")) {
        $va = OffsetToVAddr($s.Offset)
        Write-Host ("  {0,-16} vaddr={1} size={2}" -f $s.Name, (Hex $va), (Hex $s.Size))
    }
}

Write-Host ""
Write-Host "===== Summary of key addresses ====="
Write-Host ("Reset_Handler:    " + (Hex $entries[1].Target))
Write-Host ("SysTick_Handler:  " + (Hex $entries[15].Target))
Write-Host ("TIM7_IRQHandler:  " + (Hex $entries[16+55].Target))
Write-Host ("EXTI3_IRQHandler: " + (Hex $entries[16+9].Target))

# Entry point
$e_entry = [BitConverter]::ToUInt32($bytes, 24)
Write-Host ("e_entry:          " + (Hex $e_entry))
