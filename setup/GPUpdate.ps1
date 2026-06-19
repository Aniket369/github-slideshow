# ================================================================
#  Run Group Policy Update
#  No admin required for user policy. Machine policy needs admin.
# ================================================================

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "   Group Policy Update" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Running gpupdate /force ..." -ForegroundColor Yellow
Write-Host ""

gpupdate /force

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "   Group Policy update complete." -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This window will close in 5 seconds..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5
