<#
.SYNOPSIS
    Checks for common causes of incorrect/stuck Microsoft Teams (New Teams)
    presence status. Read-only — no admin required.
#>

$Host.UI.RawUI.WindowTitle = "Teams Presence Check"
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
Write-Host "  ║         TEAMS PRESENCE STATUS CHECK            ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

# ── 1. Teams installed & running ────────────────────────────
Write-Header "Teams Installation & Process"

$pkg = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue
if (-not $pkg) {
    Write-Fail "New Teams (MSTeams) is not installed on this machine."
    Add-Issue "Teams is not installed"
} else {
    Write-OK "New Teams installed — v$($pkg.Version)"
}

$teamsProc = Get-Process -Name "ms-teams" -ErrorAction SilentlyContinue
if ($teamsProc) {
    Write-OK "Teams process is running (PID $($teamsProc[0].Id))"
} else {
    Write-Fail "Teams is not currently running — presence cannot update while closed."
    Add-Issue "Teams process is not running"
}

# ── 2. User activity / idle time ────────────────────────────
Write-Header "User Activity / Idle Time"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class IdleTimeCheck {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        GetLastInputInfo(ref lii);
        return ((uint)Environment.TickCount - lii.dwTime);
    }
}
"@

$idleMin = [math]::Round([IdleTimeCheck]::GetIdleMilliseconds() / 60000, 1)
Write-Info "User has been idle for $idleMin minute(s)"

if ($idleMin -ge 5) {
    Write-Warn "Idle for $idleMin min — Teams may correctly show 'Away' due to inactivity (expected behavior, not a bug)."
} else {
    Write-OK "User is actively using the machine — presence should show 'Available' unless something else is wrong."
}

# ── 3. Workstation lock state ───────────────────────────────
Write-Header "Workstation Lock State"

if (Get-Process -Name "LogonUI" -ErrorAction SilentlyContinue) {
    Write-Warn "Workstation is currently locked — Teams will show 'Away'/'Offline' until unlocked. Expected behavior."
} else {
    Write-OK "Workstation is unlocked."
}

# ── 4. Conflicting presence sources ─────────────────────────
Write-Header "Conflicting Presence Sources"

if (Get-Process -Name "lync","Communicator" -ErrorAction SilentlyContinue) {
    Write-Warn "Skype for Business / Lync client is also running — can conflict with Teams presence."
    Add-Issue "Skype for Business client running alongside Teams — may cause presence conflicts"
} else {
    Write-OK "No legacy Skype for Business / Lync client detected running."
}

# ── 5. System clock sync ────────────────────────────────────
Write-Header "System Clock Sync"

try {
    $timeStatus = w32tm /query /status 2>$null | Out-String
    if ($timeStatus -match "Source:\s*(.+)") {
        Write-OK "Time sync source: $($Matches[1].Trim())"
    } else {
        Write-Warn "Could not determine time sync source — an incorrect system clock can break Teams auth/presence."
        Add-Issue "Unable to verify system clock sync"
    }
} catch {
    Write-Warn "w32tm not available — could not verify clock sync."
}

# ── 6. Network connectivity to presence/signaling endpoints ──
Write-Header "Network Connectivity (Presence / Signaling Endpoints)"

$endpoints = @(
    @{ Host="teams.microsoft.com";                        Port=443; Label="Core Teams"                  },
    @{ Host="login.microsoftonline.com";                  Port=443; Label="Authentication"               },
    @{ Host="aadcdn.msftauth.net";                        Port=443; Label="AAD Auth CDN"                 },
    @{ Host="api.interfaces.records.teams.microsoft.com"; Port=443; Label="Teams Config API"             },
    @{ Host="worldaz.tr.teams.microsoft.com";             Port=443; Label="Signaling / Trouter"          },
    @{ Host="outlook.office365.com";                      Port=443; Label="Calendar (meeting presence)" }
)

foreach ($ep in $endpoints) {
    try {
        $tcp  = New-Object System.Net.Sockets.TcpClient
        $conn = $tcp.BeginConnect($ep.Host, $ep.Port, $null, $null)
        $ok   = $conn.AsyncWaitHandle.WaitOne(3000)
        if ($ok) {
            $tcp.EndConnect($conn)
            Write-OK "$($ep.Label.PadRight(28)) $($ep.Host):$($ep.Port)"
        } else {
            Write-Fail "$($ep.Label.PadRight(28)) $($ep.Host):$($ep.Port) — TIMEOUT"
            Add-Issue "Cannot reach $($ep.Host) — may block presence/signaling updates"
        }
        $tcp.Close()
    } catch {
        Write-Fail "$($ep.Label.PadRight(28)) $($ep.Host):$($ep.Port) — FAILED"
        Add-Issue "Cannot reach $($ep.Host) — may block presence/signaling updates"
    }
}

# ── 7. Teams local cache sanity ─────────────────────────────
Write-Header "Teams Cache Sanity"

$cachePaths = @(
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Local\Microsoft\MSTeams"
)

$cacheIssue = $false
foreach ($path in $cachePaths) {
    if (Test-Path $path) {
        $zeroByteFiles = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -eq 0 }
        if ($zeroByteFiles) {
            Write-Warn "$($zeroByteFiles.Count) zero-byte file(s) found in $path"
            $cacheIssue = $true
        }
    }
}

if ($cacheIssue) {
    Write-Warn "Potential cache corruption detected — may cause stale/stuck presence."
    Add-Issue "Teams cache shows signs of corruption (zero-byte files)"
} else {
    Write-OK "No obvious cache corruption detected."
}

# ── Summary ──────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                   SUMMARY                      ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($Issues.Count -eq 0) {
    Write-OK "No presence-related issues detected."
    Write-Info "If presence still looks wrong, try signing out and back into Teams, or running Settings > Apps > Repair."
} else {
    Write-Fail "$($Issues.Count) potential issue(s) found:"
    $Issues | ForEach-Object { Write-Fail "  $_" }
    Write-Host ""
    Write-Info "Suggested next steps:"
    Write-Info "  1. Restart the Teams app (right-click taskbar icon > Quit, then relaunch)."
    Write-Info "  2. Sign out and back in (profile picture > Sign out)."
    Write-Info "  3. If cache corruption was flagged, run Repair-NewTeams.ps1 or Teams-CacheHealthCheck.ps1."
    Write-Info "  4. If network checks failed, confirm VPN/Zscaler/proxy isn't blocking the listed endpoints."
}

Write-Host ""
Read-Host "  Press Enter to close"
