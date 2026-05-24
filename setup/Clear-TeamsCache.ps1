# ================================================================
#  Clear Microsoft Teams Cache and Restart Teams
#  Deployed by SCCM to: C:\IT-Tools\Clear-TeamsCache.ps1
# ================================================================

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "   Microsoft Teams – Clear Cache & Restart" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Stop Teams ──────────────────────────────────────────
Write-Host "  [1/3] Stopping Microsoft Teams..." -ForegroundColor Yellow

$teamsProcesses = @("Teams", "ms-teams", "msedgewebview2")
foreach ($proc in $teamsProcesses) {
    $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($running) {
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host "        Stopped: $proc" -ForegroundColor DarkGray
    }
}

Start-Sleep -Seconds 4
Write-Host "        Teams stopped successfully." -ForegroundColor Green
Write-Host ""

# ── Step 2: Clear Cache Folders ─────────────────────────────────
Write-Host "  [2/3] Clearing cache folders..." -ForegroundColor Yellow

$cacheFolders = @(
    # Classic Teams cache locations
    "$env:APPDATA\Microsoft\Teams\Cache",
    "$env:APPDATA\Microsoft\Teams\blob_storage",
    "$env:APPDATA\Microsoft\Teams\databases",
    "$env:APPDATA\Microsoft\Teams\GPUCache",
    "$env:APPDATA\Microsoft\Teams\IndexedDB",
    "$env:APPDATA\Microsoft\Teams\Local Storage",
    "$env:APPDATA\Microsoft\Teams\tmp",

    # New Teams (work/school) cache locations
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams",
    "$env:LOCALAPPDATA\Microsoft\Teams\Current\Cache",

    # Teams PWA cache
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data"
)

$totalCleared = 0
foreach ($folder in $cacheFolders) {
    if (Test-Path $folder) {
        try {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
            Write-Host "        Cleared: $folder" -ForegroundColor DarkGray
            $totalCleared++
        } catch {
            Write-Host "        Skipped (file locked): $folder" -ForegroundColor DarkYellow
        }
    }
}

if ($totalCleared -eq 0) {
    Write-Host "        No cache folders found (already clean)." -ForegroundColor DarkGray
} else {
    Write-Host "        $totalCleared folder(s) cleared." -ForegroundColor Green
}
Write-Host ""

# ── Step 3: Restart Teams ───────────────────────────────────────
Write-Host "  [3/3] Restarting Microsoft Teams..." -ForegroundColor Yellow

# Path for new Teams (installed via Store / work account)
$newTeams     = "$env:LOCALAPPDATA\Microsoft\WindowsApps\ms-teams.exe"
# Path for classic Teams
$classicTeams = "$env:LOCALAPPDATA\Microsoft\Teams\Update.exe"

if (Test-Path $newTeams) {
    Start-Process $newTeams
    Write-Host "        New Teams launched." -ForegroundColor Green
} elseif (Test-Path $classicTeams) {
    Start-Process $classicTeams -ArgumentList "--processStart", "Teams.exe"
    Write-Host "        Classic Teams launched." -ForegroundColor Green
} else {
    Write-Host "        Could not find Teams. Please start it manually." -ForegroundColor Red
}

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "   Done! Teams cache cleared. Teams is restarting." -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This window will close in 5 seconds..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5
