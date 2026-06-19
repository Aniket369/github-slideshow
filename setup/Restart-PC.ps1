# ================================================================
#  Restart PC
#  Deployed by SCCM to: C:\IT-Tools\Restart-PC.ps1
# ================================================================

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Red
Write-Host "   PC Restart Utility" -ForegroundColor Red
Write-Host "  ================================================" -ForegroundColor Red
Write-Host ""
Write-Host "  Your PC will restart in 60 seconds." -ForegroundColor Yellow
Write-Host "  Please SAVE ALL OPEN FILES now!" -ForegroundColor Yellow
Write-Host ""
Write-Host "  To CANCEL the restart, open a Command Prompt and type:" -ForegroundColor DarkGray
Write-Host "      shutdown /a" -ForegroundColor White
Write-Host ""
Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray

# Schedule the restart (60-second delay so user can cancel)
shutdown /r /t 60 /c "IT Tools: Restarting PC as requested by user."

# Show countdown
for ($i = 60; $i -gt 0; $i--) {
    $bar = '#' * [math]::Floor((60 - $i) / 3)
    $spaces = ' ' * (20 - $bar.Length)
    Write-Host "`r  Restarting in ${i}s  [$bar$spaces]   " -NoNewline -ForegroundColor DarkYellow
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host ""
Write-Host "  Restarting now..." -ForegroundColor Red
