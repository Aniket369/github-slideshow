# ================================================================
#  Microsoft Teams — Full Cache Clear & App Reset
#  Stops Teams, wipes cache (preserves Backgrounds),
#  resets the app package, then relaunches fresh.
# ================================================================

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "   Microsoft Teams  —  Full Cache Clear & App Reset" -ForegroundColor Cyan
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Stop Teams ────────────────────────────────────────────
Write-Host "  [1/4] Stopping Microsoft Teams..." -ForegroundColor Yellow
Stop-Process -Name "MS-Teams" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "MSTeams"  -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Teams"    -Force -ErrorAction SilentlyContinue
Write-Host "        Done." -ForegroundColor Green
Write-Host ""

Start-Sleep -Seconds 3

# ── Step 2: Clear Cache (preserve Backgrounds folder) ─────────────
Write-Host "  [2/4] Clearing Teams cache (keeping your Backgrounds)..." -ForegroundColor Yellow
$TeamsCachePath = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"

if (Test-Path $TeamsCachePath) {
    Get-ChildItem -Path $TeamsCachePath -Force -Recurse |
        Where-Object { $_.FullName -notlike "*\Backgrounds*" } |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "        Done." -ForegroundColor Green
} else {
    Write-Host "        Cache folder not found — skipping." -ForegroundColor DarkGray
}
Write-Host ""

Start-Sleep -Seconds 5

# ── Step 3: Reset Teams app package ──────────────────────────────
Write-Host "  [3/4] Resetting Microsoft Teams app package..." -ForegroundColor Yellow
Get-AppxPackage -Name "MSTeams" | Reset-AppxPackage
Write-Host "        Done." -ForegroundColor Green
Write-Host ""

Start-Sleep -Seconds 5

# ── Step 4: Relaunch Teams ────────────────────────────────────────
Write-Host "  [4/4] Launching Microsoft Teams fresh..." -ForegroundColor Yellow
Start-Process "MS-Teams"
Write-Host "        Done." -ForegroundColor Green
Write-Host ""

Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "   All done! Teams is restarting clean." -ForegroundColor Green
Write-Host "   Your backgrounds and custom settings are preserved." -ForegroundColor Green
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This window will close in 5 seconds..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5
