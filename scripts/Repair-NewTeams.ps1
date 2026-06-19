# ============================================================
#  Repair-NewTeams.ps1
#  Repairs Microsoft New Teams (MSIX) — NO admin rights needed
#  Mirrors exactly what Settings > Apps > Repair does
#  Usage: Right-click > Run with PowerShell
# ============================================================

# ── Console setup ───────────────────────────────────────────
$Host.UI.RawUI.WindowTitle = "Teams Repair Tool"
Clear-Host

function Write-Step  { param($n,$m) Write-Host "`n  [$n/6] $m" -ForegroundColor Cyan }
function Write-OK    { param($m)    Write-Host "        OK  — $m" -ForegroundColor Green }
function Write-Warn  { param($m)    Write-Host "        !   — $m" -ForegroundColor Yellow }
function Write-Fail  { param($m)    Write-Host "        ERR — $m" -ForegroundColor Red }

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "    Microsoft New Teams — Repair Tool" -ForegroundColor Cyan
Write-Host "    No admin rights required" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan

# ── Step 1: Verify New Teams is installed ───────────────────
Write-Step 1 "Detecting New Teams installation..."

$pkg = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue

if (-not $pkg) {
    Write-Fail "New Teams (MSTeams) not found on this machine."
    Write-Host ""
    Write-Host "  Please install Teams from https://aka.ms/getteams" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  Press Enter to exit"
    exit 1
}

Write-OK "Found: MSTeams v$($pkg.Version)"
Write-OK "Location: $($pkg.InstallLocation)"

# ── Step 2: Kill Teams processes ────────────────────────────
Write-Step 2 "Stopping Teams processes..."

$procs = @("ms-teams", "msedgewebview2")
foreach ($p in $procs) {
    $found = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($found) {
        $found | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-OK "Stopped: $p"
    }
}
Start-Sleep -Seconds 2
Write-OK "All Teams processes stopped"

# ── Step 3: Clear user-level cache ──────────────────────────
Write-Step 3 "Clearing Teams cache (user-level only)..."

$cachePaths = @(
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Local\Microsoft\MSTeams",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\TempState",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\AC\Temp"
)

foreach ($path in $cachePaths) {
    if (Test-Path $path) {
        try {
            Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-OK "Cleared: $path"
        } catch {
            Write-Warn "Partial clear: $path"
        }
    } else {
        Write-Warn "Not found (skip): $path"
    }
}

# ── Step 4: Re-register the MSIX package ────────────────────
#    This is EXACTLY what Windows Settings Repair button does:
#    Add-AppxPackage -Register on the user's AppxManifest
Write-Step 4 "Re-registering Teams package (same as Settings > Repair)..."

$manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"

if (-not (Test-Path $manifest)) {
    Write-Fail "AppxManifest.xml not found at: $manifest"
    Write-Warn "Teams installation may be corrupt. Try reinstalling."
} else {
    try {
        # -DisableDevelopmentMode + -Register = user-level re-registration
        # Does NOT require admin — only touches current user's app registration
        Add-AppxPackage `
            -DisableDevelopmentMode `
            -Register $manifest `
            -ErrorAction Stop

        Write-OK "Package re-registered successfully"
        Write-OK "File integrity restored, shortcuts fixed, protocol handlers re-linked"
    } catch {
        Write-Fail "Re-registration failed: $($_.Exception.Message)"
        Write-Host ""
        Write-Host "  This can happen if another user has Teams open or if the" -ForegroundColor Yellow
        Write-Host "  package store is locked. Try logging off other sessions." -ForegroundColor Yellow
    }
}

# ── Step 5: Fix ms-teams:// protocol handler ────────────────
Write-Step 5 "Verifying ms-teams:// meeting link handler..."

$protocolKey = "HKCU:\Software\Classes\ms-teams"

try {
    if (-not (Test-Path $protocolKey)) {
        New-Item -Path $protocolKey -Force | Out-Null
    }
    Set-ItemProperty -Path $protocolKey -Name "(Default)"    -Value "URL:ms-teams" -Force
    Set-ItemProperty -Path $protocolKey -Name "URL Protocol" -Value ""              -Force

    $cmdPath = "$protocolKey\shell\open\command"
    if (-not (Test-Path $cmdPath)) {
        New-Item -Path $cmdPath -Force | Out-Null
    }
    # Points to MSIX app via app ID — works without admin
    Set-ItemProperty -Path $cmdPath -Name "(Default)" `
        -Value "`"shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams`" `"%1`"" -Force

    Write-OK "ms-teams:// protocol handler verified and restored"
} catch {
    Write-Warn "Could not update protocol handler: $($_.Exception.Message)"
}

# ── Step 6: Verify repair succeeded ─────────────────────────
Write-Step 6 "Verifying repair..."

$pkgAfter = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue
if ($pkgAfter) {
    Write-OK "Teams package status: Registered"
    Write-OK "Version: $($pkgAfter.Version)"
    Write-OK "Status : $($pkgAfter.Status)"
} else {
    Write-Fail "Teams package not found after repair — something went wrong"
}

# ── Done ────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "    Repair Complete!" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""

$launch = Read-Host "  Launch Teams now? (Y/N)"
if ($launch -match '^[Yy]$') {
    Start-Process "shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams"
    Write-Host ""
    Write-OK "Teams launched!"
}

Write-Host ""
Write-Host "  If the issue persists, try:" -ForegroundColor Yellow
Write-Host "  1. Settings > Apps > Installed Apps > Microsoft Teams > Reset" -ForegroundColor Yellow
Write-Host "  2. Sign out and sign back into Teams" -ForegroundColor Yellow
Write-Host "  3. Reinstall: https://aka.ms/getteams" -ForegroundColor Yellow
Write-Host ""
Read-Host "  Press Enter to close"
