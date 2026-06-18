<#
.SYNOPSIS
    Checks whether Microsoft Teams is running in a virtual desktop (Citrix
    HDX / generic VDI) session and whether the Teams VDI media-optimization
    component is present and active — the most common cause of poor call
    quality ("robotic audio", high latency, no video) inside virtual
    desktops. Read-only — no admin required.

.NOTES
    Run this INSIDE the VDI session / VDA, not on the physical endpoint.
    It cannot see the endpoint device's own OS, privacy settings, or
    locally installed Citrix/optimizer components — that requires a
    separate script run directly on the endpoint.
#>

$Host.UI.RawUI.WindowTitle = "Teams VDI / Citrix HDX Optimization Check"
Clear-Host

function Write-Header { param($t) Write-Host "`n  ── $t " -ForegroundColor Cyan }
function Write-OK     { param($m) Write-Host "  ✔  $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "  ⚠  $m" -ForegroundColor Yellow }
function Write-Fail   { param($m) Write-Host "  ✘  $m" -ForegroundColor Red }
function Write-Info   { param($m) Write-Host "  ℹ  $m" -ForegroundColor White }

$Issues = [System.Collections.Generic.List[string]]::new()
function Add-Issue { param($m) $Issues.Add($m) }

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   TEAMS VDI / CITRIX HDX OPTIMIZATION CHECK    ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

# ── 1. Session Type Detection ───────────────────────────────
Write-Header "Session Type"

$sessionName    = $env:SESSIONNAME
$isCitrixIca    = [bool]($sessionName -match '^ICA-')
$isRdp          = [bool]($sessionName -match '^RDP-')
$isRemoteSession = [bool]($sessionName -and $sessionName -ne 'Console')

if ($isCitrixIca) {
    Write-OK "Session type: Citrix ICA ($sessionName)"
} elseif ($isRdp) {
    Write-Warn "Session type: RDP ($sessionName) — not Citrix ICA. HDX-specific optimization does not apply to RDP sessions."
} elseif ($isRemoteSession) {
    Write-Info "Session type: remote session ($sessionName) — not recognized as Citrix ICA or RDP."
} else {
    Write-Info "Session type: local console session — this is not a VDI/remote session, HDX optimization is not applicable."
}

$volEnv = Get-ItemProperty -Path 'HKCU:\Volatile Environment' -ErrorAction SilentlyContinue
if ($volEnv) {
    if ($volEnv.ClientName)    { Write-Info "Connecting client (endpoint) name : $($volEnv.ClientName)" }
    if ($volEnv.ClientAddress) { Write-Info "Connecting client (endpoint) IP   : $($volEnv.ClientAddress)" }
} elseif ($isRemoteSession) {
    Write-Warn "Could not read client endpoint details from HKCU:\Volatile Environment."
}

# ── 2. Citrix Components Detected on This Machine ──────────
Write-Header "Citrix Components Detected on This Machine"

$citrixServices = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Citrix' -or $_.Name -match 'Citrix' }
if ($citrixServices) {
    foreach ($svc in $citrixServices) {
        $tag = if ($svc.Status -eq 'Running') { 'Running' } else { $svc.Status }
        if ($svc.Status -eq 'Running') { Write-OK "$($svc.DisplayName) — $tag" }
        else { Write-Warn "$($svc.DisplayName) — $tag" }
    }
    Write-Info "This machine has Citrix component(s) installed (likely a Citrix VDA)."
} else {
    Write-Warn "No Citrix services detected on this machine."
    if ($isCitrixIca) {
        Add-Issue "Session is Citrix ICA, but no Citrix services were found on this machine — unexpected"
    }
}

# ── 3. Teams VDI Optimization Component ─────────────────────
Write-Header "Teams VDI Optimization Component"

$uninstallPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installedPrograms = foreach ($p in $uninstallPaths) {
    Get-ItemProperty -Path $p -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
}

$optimizerPattern = 'Teams.*(VDI|Redirector)|WebRTC Redirector|HDX RealTime|RealTime Media Engine|RealTime Connector'
$optimizerPrograms = $installedPrograms | Where-Object { $_.DisplayName -match $optimizerPattern } | Sort-Object DisplayName -Unique
$optimizerServices = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $optimizerPattern -or $_.Name -match 'Redir|RTME|RTOP' }

if ($optimizerPrograms) {
    foreach ($prog in $optimizerPrograms) {
        $versionSuffix = if ($prog.DisplayVersion) { " (v$($prog.DisplayVersion))" } else { "" }
        Write-OK "Installed: $($prog.DisplayName)$versionSuffix"
    }
} else {
    Write-Fail "No Teams VDI optimization component (HDX RealTime Media Engine / WebRTC Redirector) found installed."
    if ($isCitrixIca) {
        Add-Issue "Teams VDI optimization component not installed — calls will run unoptimized inside the VM"
    }
}

if ($optimizerServices) {
    foreach ($svc in $optimizerServices) {
        if ($svc.Status -eq 'Running') { Write-OK   "$($svc.DisplayName) service — Running" }
        else {
            Write-Fail "$($svc.DisplayName) service — $($svc.Status) (not running)"
            Add-Issue "Teams VDI optimization service '$($svc.DisplayName)' is not running"
        }
    }
} elseif ($optimizerPrograms) {
    Write-Warn "Optimization component is installed but no matching service was found running — it may load as a DLL inside Teams instead of a standalone service (this is normal for some versions)."
}

# ── 4. Teams Log: Best-Effort Optimization Status ──────────
Write-Header "Teams Log — Best-Effort Optimization Status"

$logFolders = @(
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Logs",
    "$env:APPDATA\Microsoft\Teams"
)

$logHits = @()
foreach ($folder in $logFolders) {
    if (Test-Path $folder) {
        $recentLogs = Get-ChildItem -Path $folder -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 3
        foreach ($log in $recentLogs) {
            $hits = Select-String -Path $log.FullName -Pattern 'VDI|Citrix|HDX|WebRTC Redirect' -ErrorAction SilentlyContinue |
                Select-Object -Last 5
            if ($hits) { $logHits += $hits }
        }
    }
}

if ($logHits.Count -gt 0) {
    Write-Info "Found $($logHits.Count) recent log line(s) mentioning VDI/Citrix/HDX/WebRTC (most recent shown):"
    $logHits | Select-Object -Last 5 | ForEach-Object {
        $line = $_.Line.Trim()
        if ($line.Length -gt 140) { $line = $line.Substring(0, 140) + '...' }
        Write-Info "  $line"
    }
    Write-Warn "Log content is best-effort/diagnostic only — Teams log formats change between versions and are not an authoritative API."
} else {
    Write-Info "No matching VDI/Citrix/HDX log lines found in recent Teams logs (or logs were not accessible)."
}

# ── 5. Camera/Microphone Privacy on This Machine ────────────
Write-Header "Camera/Microphone Privacy on This Machine"
Write-Info "(This checks privacy consent on THIS machine, i.e. the VM/session host."
Write-Info " It does not check the physical endpoint device — that requires a separate script run on the endpoint.)"

function Get-ConsentStatus {
    param($Capability)
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$Capability"
    if (Test-Path $path) {
        return (Get-ItemProperty -Path $path -Name Value -ErrorAction SilentlyContinue).Value
    }
    return $null
}

$camConsent = Get-ConsentStatus -Capability 'webcam'
$micConsent = Get-ConsentStatus -Capability 'microphone'

if     ($camConsent -eq 'Allow') { Write-OK   "Camera access is allowed at the Windows privacy level on this machine." }
elseif ($camConsent -eq 'Deny')  {
    Write-Fail "Camera access is BLOCKED at the Windows privacy level on this machine."
    Add-Issue "Windows privacy settings on this machine are blocking camera access"
} else { Write-Warn "Could not determine the Windows camera privacy setting on this machine." }

if     ($micConsent -eq 'Allow') { Write-OK   "Microphone access is allowed at the Windows privacy level on this machine." }
elseif ($micConsent -eq 'Deny')  {
    Write-Fail "Microphone access is BLOCKED at the Windows privacy level on this machine."
    Add-Issue "Windows privacy settings on this machine are blocking microphone access"
} else { Write-Warn "Could not determine the Windows microphone privacy setting on this machine." }

# ── Summary ──────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                   SUMMARY                      ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($Issues.Count -eq 0) {
    Write-OK "No VDI optimization issues detected on this machine."
    if (-not $isCitrixIca) {
        Write-Info "Note: this session was not detected as Citrix ICA, so HDX-specific checks were limited."
    }
} else {
    Write-Fail "$($Issues.Count) potential issue(s) found:"
    $Issues | ForEach-Object { Write-Fail "  $_" }
    Write-Host ""
    Write-Info "Suggested next steps:"
    Write-Info "  1. Confirm the Teams VDI optimization component (HDX RealTime Media Engine or WebRTC Redirector Service) is installed and running on this VM."
    Write-Info "  2. Confirm the matching Citrix Workspace App / optimizer plugin is installed on the physical endpoint device (run the endpoint-side script there)."
    Write-Info "  3. Confirm Citrix policies for client microphone/webcam redirection are enabled for this delivery group."
    Write-Info "  4. If privacy settings are blocking access, check Windows Settings > Privacy & security > Camera/Microphone."
}

Write-Host ""
Read-Host "  Press Enter to close"
