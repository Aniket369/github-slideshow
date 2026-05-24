# ================================================================
#  Clear Microsoft Teams (New) Cache and Restart
#  No admin access required.
# ================================================================

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "   Microsoft Teams - Clear Cache & Restart" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Kill Teams ────────────────────────────────────────────
Write-Host "  [1/3] Stopping Microsoft Teams..." -ForegroundColor Yellow

$teamsProcesses = @("ms-teams", "Teams", "msedgewebview2")
foreach ($proc in $teamsProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 4
Write-Host "        Teams stopped." -ForegroundColor Green
Write-Host ""

# ── Step 2: Clear Cache ───────────────────────────────────────────
Write-Host "  [2/3] Clearing Teams cache..." -ForegroundColor Yellow

$cachePath = "$env:USERPROFILE\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"

if (Test-Path $cachePath) {
    try {
        Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction Stop
        Write-Host "        Cache cleared: $cachePath" -ForegroundColor Green
    } catch {
        Write-Host "        Some files were in use and skipped (this is normal)." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "        Cache folder not found - may already be clean." -ForegroundColor DarkGray
}

# Also reset the Teams app package (clears all stored data thoroughly)
Write-Host "        Resetting Teams app package..." -ForegroundColor Yellow
try {
    Get-AppxPackage -Name MSTeams | Reset-AppxPackage
    Write-Host "        Teams app reset successfully." -ForegroundColor Green
} catch {
    Write-Host "        App reset skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Host ""

# ── Step 3: Restart Teams ─────────────────────────────────────────
Write-Host "  [3/3] Restarting Microsoft Teams..." -ForegroundColor Yellow

Start-Sleep -Seconds 2

try {
    Start-Process "shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams"
    Write-Host "        Teams is launching..." -ForegroundColor Green
} catch {
    Write-Host "        Could not auto-launch Teams. Please open it manually." -ForegroundColor Red
}

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "   Done! Teams cache cleared and app is restarting." -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This window will close in 5 seconds..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5
