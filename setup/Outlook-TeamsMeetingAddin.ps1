# ================================================================
#  Outlook – Teams Meeting Add-in Fix
#  Stops Outlook and Teams, clears the Teams cache, resets the
#  Teams app package, then restarts both apps so the "New Teams
#  Meeting" button re-appears in Outlook.
# ================================================================

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "   Outlook – Teams Meeting Add-in Fix" -ForegroundColor Cyan
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Stop Outlook ─────────────────────────────────────────
Write-Host "  [1/6] Stopping Outlook..." -ForegroundColor Yellow
Stop-Process -Name "Outlook" -Force -ErrorAction SilentlyContinue
Write-Host "        Done." -ForegroundColor Green

# ── Step 2: Stop Teams ───────────────────────────────────────────
Write-Host "  [2/6] Stopping Teams..." -ForegroundColor Yellow
Stop-Process -Name "MS-Teams" -Force -ErrorAction SilentlyContinue
Write-Host "        Done." -ForegroundColor Green

# ── Step 3: Wait after stopping ──────────────────────────────────
Write-Host "  [3/6] Waiting 3 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# ── Step 4: Clear Teams cache (keep Backgrounds) ─────────────────
Write-Host "  [4/6] Clearing Teams cache (Backgrounds preserved)..." -ForegroundColor Yellow
$TeamsCachePath = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"
if (Test-Path $TeamsCachePath) {
    Get-ChildItem -Path $TeamsCachePath -Force -Recurse |
        Where-Object { $_.FullName -notlike "*\Backgrounds*" } |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "        Cache cleared." -ForegroundColor Green
} else {
    Write-Host "        Cache path not found — skipping." -ForegroundColor DarkGray
}

# ── Step 5: Wait, then reset Teams app package ───────────────────
Write-Host "  [5/6] Resetting Teams app package..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue | Reset-AppxPackage
Write-Host "        Done." -ForegroundColor Green

# ── Step 6: Restart Teams, then Outlook ──────────────────────────
Write-Host "  [6/6] Restarting Teams and Outlook..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
Start-Process "MS-Teams"
Write-Host "        Teams launched." -ForegroundColor Green

Start-Sleep -Seconds 5
Start-Process "Outlook"
Write-Host "        Outlook launched." -ForegroundColor Green

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "   Done! Both apps are starting." -ForegroundColor Green
Write-Host "   Once Outlook opens, check the Calendar ribbon —" -ForegroundColor DarkGray
Write-Host "   the 'New Teams Meeting' button should now appear." -ForegroundColor DarkGray
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This window will close in 8 seconds..." -ForegroundColor DarkGray
Start-Sleep -Seconds 8
