# Diagnostic 1: 监控 SPI1->SR 的 BSY 位变化
# 用法：
#   1) 启动当前固件 (probe-rs run / gdb continue)
#   2) powershell -ExecutionPolicy Bypass -File scripts\watch_spi_sr.ps1
#   3) 拍传感器 / 摇晃棒子
#   4) 观察 BSY 是否周期性 1/0 切换
#
# 输出解读：
#   BSY 周期性 toggle     -> SPI 在跑，转查 595 链路
#   BSY 全程 0             -> SPI 没在跑 (CR1.SPE 未真置位 / NVIC 没接通)
#   BSY 全程 1             -> SPI 总线死锁

$SPI_SR_ADDR = 0x40013008
$CHIP        = "STM32F103RC"
$INTERVAL_MS = 50
$COUNT       = 60

Write-Host "=== Diagnostic 1: SPI1->SR monitor ==="
Write-Host "addr = 0x$('{0:X8}' -f $SPI_SR_ADDR), interval = $INTERVAL_MS ms, count = $COUNT"
Write-Host "Sample:  tick SR        BSY TXE  marker"
Write-Host "------  ---- --------  --- ---  ------"

for ($i = 0; $i -lt $COUNT; $i++) {
    $raw = probe-rs read --chip $CHIP b32 $SPI_SR_ADDR 1
    $hexStr = ($raw -replace '\s+', '')
    if ([string]::IsNullOrWhiteSpace($hexStr)) {
        Write-Host ("{0,-6}  TIMEOUT" -f $i)
        continue
    }
    $sr = [Convert]::ToInt32($hexStr, 16)
    $bsy = (($sr -band 0x80) -ne 0)
    $txe = (($sr -band 0x02) -ne 0)
    $marker = ""
    if ($bsy) { $marker = ">>> HIGHLIGHT (SPI shifting)" }
    Write-Host ("{0,-6}  0x{1:X8}  {2}   {3}   {4}" -f `
        $i, $sr, `
        $(if($bsy){"1"}else{"0"}), `
        $(if($txe){"1"}else{"0"}), `
        $marker)
    Start-Sleep -Milliseconds $INTERVAL_MS
}

Write-Host "=== done ==="