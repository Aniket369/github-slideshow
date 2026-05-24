# ================================================================
#  Clear Microsoft Teams Cache and Restart
#  No admin access required.
# ================================================================

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "   Microsoft Teams - Clear Cache & Restart" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Stop Teams ────────────────────────────────────────────
Write-Host "  [1/4] Stopping Teams..." -ForegroundColor Yellow
Stop-Process -Name MSTeams -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Write-Host "        Done." -ForegroundColor Green
Write-Host ""

# ── Step 2: Clear Cache ───────────────────────────────────────────
Write-Host "  [2/4] Clearing Teams cache..." -ForegroundColor Yellow
$cachePath = "$env:USERPROFILE\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"
Get-ChildItem -Path $cachePath -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "        Done." -ForegroundColor Green
Write-Host ""

# ── Step 3: Reset Teams App ───────────────────────────────────────
Write-Host "  [3/4] Resetting Teams app..." -ForegroundColor Yellow
Get-AppxPackage -Name MSTeams | Reset-AppxPackage
Write-Host "        Done." -ForegroundColor Green
Write-Host ""

# ── Step 4: Start Teams ───────────────────────────────────────────
Write-Host "  [4/4] Starting Teams..." -ForegroundColor Yellow
Start-Process MSTeams
Write-Host "        Done." -ForegroundColor Green
Write-Host ""

Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "   All done! Teams is restarting." -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This window will close in 5 seconds..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5
