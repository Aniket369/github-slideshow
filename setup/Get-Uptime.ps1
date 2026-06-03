# ================================================================
#  System Uptime Check
#  Shows how long the PC has been running. Suggests a restart
#  if uptime exceeds 1 day and offers to schedule one.
# ================================================================

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "   System Uptime Check" -ForegroundColor Cyan
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host ""

$os      = Get-CimInstance Win32_OperatingSystem
$uptime  = (Get-Date) - $os.LastBootUpTime
$days    = [int]$uptime.TotalDays
$hours   = $uptime.Hours
$minutes = $uptime.Minutes

Write-Host "  Computer  : $env:COMPUTERNAME" -ForegroundColor DarkGray
Write-Host "  Last Boot : $($os.LastBootUpTime.ToString('dd MMM yyyy  HH:mm'))" -ForegroundColor DarkGray
Write-Host ""

if ($uptime.TotalDays -ge 1) {
    Write-Host "  Uptime : $days day(s)  $hours hr  $minutes min" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ⚠  Your PC has been running for over $days day(s)." -ForegroundColor Yellow
    Write-Host "     A restart is recommended to improve performance" -ForegroundColor Yellow
    Write-Host "     and apply any pending Windows updates." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Would you like to schedule a restart in 60 seconds? (Y/N)" -ForegroundColor Cyan
    $ans = Read-Host "  "
    if ($ans -eq 'Y' -or $ans -eq 'y') {
        shutdown /r /t 60 /c "IT Portal: Restart after extended uptime"
        Write-Host ""
        Write-Host "  Restart scheduled in 60 seconds." -ForegroundColor Green
        Write-Host "  To cancel, open Command Prompt and run: shutdown /a" -ForegroundColor DarkGray
    } else {
        Write-Host ""
        Write-Host "  No restart scheduled. Please restart when convenient." -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Uptime : $hours hr  $minutes min" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ✅ Uptime is healthy — less than 1 day." -ForegroundColor Green
}

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "  This window will close in 10 seconds..." -ForegroundColor DarkGray
Start-Sleep -Seconds 10
