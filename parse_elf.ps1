param(
    [string]$ElfPath = "D:\myProject\wobbly-stick-light\zig-out\bin\wobbly-stick-light"
)

$ErrorActionPreference = "Stop"

# Symbol names to look up
$wanted = @(
    "Reset_Handler", "SysTick_Handler", "TIM7_IRQHandler", "EXTI3_IRQHandler",
    "SystemInit", "board_init", "led_pov_init", "led_pov_tick",
    "vibration_init", "vibration_exti_isr", "vibration_consume",
    "led_pov_set_pattern", "led_pov_start", "main",
    "g_systick_ms", "g_isr_count_systick", "g_isr_count_tim7", "g_isr_count_exti3",
    "s_trigger_ms", "s_pending", "heartbeat", "FONT_LKM"
)

# Read file as bytes
$bytes = [System.IO.File]::ReadAllBytes($ElfPath)
$size = $bytes.Length
Write-Host "File size: $size bytes"

# ELF32 header parsing
# Magic: 0x7F 'E' 'L' 'F' at offset 0
if ($bytes[0] -ne 0x7F -or $bytes[1] -ne 0x45 -or $bytes[2] -ne 0x4C -or $bytes[3] -ne 0x46) {
    throw "Not an ELF file"
}
$eiClass = $bytes[4]  # 1=32-bit, 2=64-bit
$eiData = $bytes[5]   # 1=LE, 2=BE
Write-Host "Class: $(if($eiClass -eq 1){'32-bit'}else{'64-bit'})"
Write-Host "Endian: $(if($eiData -eq 1){'LE'}else{'BE'})"

# e_shoff = offset 32 (32-bit), e_shentsize=46, e_shnum=48, e_shstrndx=50
$e_shoff = [BitConverter]::ToInt32($bytes, 32)
$e_shentsize = [BitConverter]::ToUInt16($bytes, 46)
$e_shnum = [BitConverter]::ToUInt16($bytes, 48)
$e_shstrndx = [BitConverter]::ToUInt16($bytes, 50)
Write-Host "Section header offset: $e_shoff, count: $e_shnum, entsize: $e_shentsize, strndx: $e_shstrndx"

# Read section name string table
function Read-CString($off) {
    $sb = New-Object System.Text.StringBuilder
    while ($off -lt $bytes.Length -and $bytes[$off] -ne 0) {
        [void]$sb.Append([char]$bytes[$off])
        $off++
    }
    return $sb.ToString()
}

# Parse section headers
$sections = @()
for ($i = 0; $i -lt $e_shnum; $i++) {
    $off = $e_shoff + ($i * $e_shentsize)
    $sh_name = [BitConverter]::ToUInt32($bytes, $off)
    $sh_type = [BitConverter]::ToUInt32($bytes, $off + 4)
    $sh_offset = [BitConverter]::ToUInt32($bytes, $off + 16)
    $sh_size = [BitConverter]::ToUInt32($bytes, $off + 20)
    $sh_link = [BitConverter]::ToUInt32($bytes, $off + 24)
    $sh_entsize = [BitConverter]::ToUInt32($bytes, $off + 36)
    $name = Read-CString ($shstrtab_off + $sh_name) 2>$null
    $sections += [pscustomobject]@{
        Index = $i; Type = $sh_type; Offset = $sh_offset; Size = $sh_size;
        Link = $sh_link; Entsize = $sh_entsize; Name = $name
    }
}

# Get shstrtab first
$shstrtab = $sections[$e_shstrndx]
$shstrtab_off = $shstrtab.Offset
$shstrtab_size = $shstrtab.Size

# Re-parse with proper names
$sections = @()
for ($i = 0; $i -lt $e_shnum; $i++) {
    $off = $e_shoff + ($i * $e_shentsize)
    $sh_name = [BitConverter]::ToUInt32($bytes, $off)
    $sh_type = [BitConverter]::ToUInt32($bytes, $off + 4)
    $sh_offset = [BitConverter]::ToUInt32($bytes, $off + 16)
    $sh_size = [BitConverter]::ToUInt32($bytes, $off + 20)
    $sh_link = [BitConverter]::ToUInt32($bytes, $off + 24)
    $sh_entsize = [BitConverter]::ToUInt32($bytes, $off + 36)
    $name = Read-CString ($shstrtab_off + $sh_name)
    $sections += [pscustomobject]@{
        Index = $i; Type = $sh_type; Offset = $sh_offset; Size = $sh_size;
        Link = $sh_link; Entsize = $sh_entsize; Name = $name
    }
}

# List all sections
Write-Host "===== All sections ====="
foreach ($s in $sections) {
    Write-Host ("  [{0}] type={1} off=0x{2:X8} size=0x{3:X8} link={4} entsize={5} name={6}" -f $s.Index, $s.Type, $s.Offset, $s.Size, $s.Link, $s.Entsize, $s.Name)
}

# Find .symtab and .strtab
$symtab = $sections | Where-Object { $_.Name -eq ".symtab" } | Select-Object -First 1
$strtab_sec = $sections | Where-Object { $_.Name -eq ".strtab" } | Select-Object -First 1

if (-not $symtab) {
    Write-Host "No .symtab section - checking program headers for symbol table info"
    exit 0
}

Write-Host "Symtab offset: $($symtab.Offset), size: $($symtab.Size), entsize: $($symtab.Entsize)"
Write-Host "Strtab offset: $($strtab_sec.Offset), size: $($strtab_sec.Size)"

# Symbol table entry: 16 bytes
# st_name(4), st_value(4), st_size(4), st_info(1), st_other(1), st_shndx(2)
$sym_count = [int]($symtab.Size / $symtab.Entsize)
$symtab_off = $symtab.Offset
$strtab_off = $strtab_sec.Offset

$found = @{}
foreach ($w in $wanted) {
    $found[$w] = $null
}

for ($i = 0; $i -lt $sym_count; $i++) {
    $base = $symtab_off + ($i * 16)
    $st_name = [BitConverter]::ToUInt32($bytes, $base)
    $st_value = [BitConverter]::ToUInt32($bytes, $base + 4)
    $st_size = [BitConverter]::ToUInt32($bytes, $base + 8)
    $st_info = $bytes[$base + 12]
    $st_shndx = [BitConverter]::ToUInt16($bytes, $base + 14)

    $name = Read-CString ($strtab_off + $st_name)
    if ($null -ne $name -and $found.ContainsKey($name)) {
        $found[$name] = [pscustomobject]@{
            Value = $st_value; Size = $st_size; Info = $st_info; Shndx = $st_shndx
        }
    }
}

# Print results as JSON
$out = [ordered]@{}
foreach ($w in $wanted) {
    $s = $found[$w]
    if ($s) {
        $out[$w] = "0x{0:X8}" -f $s.Value
    } else {
        $out[$w] = "NOT_FOUND"
    }
}

# Add notes
$notes = @()
$notes += "ELF class: $(if($eiClass -eq 1){'32-bit'}else{'64-bit'}) little-endian"

# Find .text, .bss, .data, .vector_table
$text_sec = $sections | Where-Object { $_.Name -eq ".text" } | Select-Object -First 1
$bss_sec = $sections | Where-Object { $_.Name -eq ".bss" } | Select-Object -First 1
$vt_sec = $sections | Where-Object { $_.Name -eq ".vector_table" -or $_.Name -eq ".isr_vector" -or $_.Name -eq ".vectors" } | Select-Object -First 1
$data_sec = $sections | Where-Object { $_.Name -eq ".data" } | Select-Object -First 1

# Entry point
$e_entry = [BitConverter]::ToUInt32($bytes, 24)
$notes += "Entry point (e_entry): 0x{0:X8}" -f $e_entry

if ($text_sec) { $notes += ".text: 0x{0:X8} size=0x{1:X}" -f $text_sec.Offset, $text_sec.Size }
if ($bss_sec) { $notes += ".bss offset: 0x{0:X8} size=0x{1:X}" -f $bss_sec.Offset, $bss_sec.Size }
if ($data_sec) { $notes += ".data offset: 0x{0:X8} size=0x{1:X}" -f $data_sec.Offset, $data_sec.Size }
if ($vt_sec) { $notes += "$($vt_sec.Name) offset: 0x{0:X8} size=0x{1:X}" -f $vt_sec.Offset, $vt_sec.Size }

# Report missing
$missing = $wanted | Where-Object { $null -eq $found[$_] }
if ($missing.Count -gt 0) {
    $notes += "Missing symbols: $($missing -join ', ')"
}

$out["notes"] = $notes
$json = $out | ConvertTo-Json -Depth 5
Write-Host ""
Write-Host "===== JSON RESULT ====="
Write-Host $json
