<#
.SYNOPSIS
    Checks WebView2 Runtime version for Microsoft Teams compatibility and installs/updates as needed.

.DESCRIPTION
    Microsoft Teams (new) requires WebView2 Runtime version 86.0.622.38 or later.
    This script:
      - Detects the installed WebView2 version from the Windows registry
      - Compares it against the minimum version required by MS Teams
      - Downloads and installs/updates WebView2 if missing or below minimum
    Must be run with Administrator privileges.

.NOTES
    Registry GUIDs:
      Machine-wide (WOW6432Node): HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}
      Native 64-bit:              HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}
      Per-user:                   HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}
#>

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Configuration ───────────────────────────────────────────────────────────────
$MinTeamsVersion  = [Version]'86.0.622.38'          # Minimum WebView2 version for MS Teams
$DownloadUrl      = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'  # Evergreen Bootstrapper
$DownloadFolder   = "$env:TEMP\WebView2Runtime"
$BootstrapperPath = Join-Path $DownloadFolder 'MicrosoftEdgeWebview2Setup.exe'

$WebView2Guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$RegistryPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$WebView2Guid",  # 32-bit / machine-wide
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$WebView2Guid",              # 64-bit / machine-wide
    "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$WebView2Guid"               # per-user
)
# ────────────────────────────────────────────────────────────────────────────────

function Write-Status {
    param([string]$Message, [string]$Level = 'INFO')
    $colors = @{ INFO = 'Cyan'; OK = 'Green'; WARN = 'Yellow'; ERROR = 'Red' }
    $color  = $colors[$Level] ?? 'White'
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Get-InstalledWebView2Version {
    foreach ($path in $RegistryPaths) {
        try {
            $prop = Get-ItemProperty -Path $path -ErrorAction Stop
            if ($prop.pv -and $prop.pv -ne '0.0.0.0') {
                return [PSCustomObject]@{
                    Version      = [Version]$prop.pv
                    RegistryPath = $path
                    DisplayName  = $prop.name ?? 'Microsoft Edge WebView2 Runtime'
                }
            }
        } catch {
            # Path doesn't exist or pv not present — try next
        }
    }
    return $null
}

function Download-Bootstrapper {
    Write-Status "Creating download folder: $DownloadFolder"
    New-Item -ItemType Directory -Path $DownloadFolder -Force | Out-Null

    Write-Status "Downloading WebView2 Evergreen Bootstrapper..."
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($DownloadUrl, $BootstrapperPath)
        Write-Status "Downloaded to: $BootstrapperPath" -Level OK
    } catch {
        throw "Download failed: $_"
    }
}

function Install-WebView2 {
    param([string]$Mode = 'install')

    if (-not (Test-Path $BootstrapperPath)) {
        Download-Bootstrapper
    }

    Write-Status "Running WebView2 bootstrapper (silent $Mode)..."
    $proc = Start-Process -FilePath $BootstrapperPath `
                          -ArgumentList '/silent', '/install' `
                          -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -eq 0) {
        Write-Status "WebView2 $Mode completed successfully." -Level OK
    } elseif ($proc.ExitCode -eq 3010) {
        Write-Status "WebView2 $Mode succeeded — a reboot is required." -Level WARN
    } else {
        throw "Bootstrapper exited with code $($proc.ExitCode). Check Event Viewer for details."
    }
}

# ── Main logic ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "======================================================" -ForegroundColor Magenta
Write-Host "  WebView2 Runtime — MS Teams Compatibility Checker   " -ForegroundColor Magenta
Write-Host "======================================================" -ForegroundColor Magenta
Write-Host ""

Write-Status "Minimum WebView2 version required for MS Teams : $MinTeamsVersion"
Write-Host ""

$installed = Get-InstalledWebView2Version

if ($null -eq $installed) {
    # ── Not installed ───────────────────────────────────────────────────────────
    Write-Status "WebView2 Runtime is NOT installed on this machine." -Level WARN
    Write-Status "Installing WebView2 Runtime for MS Teams compatibility..." -Level WARN
    Write-Host ""

    try {
        Install-WebView2 -Mode 'install'
    } catch {
        Write-Status $_ -Level ERROR
        exit 1
    }

} else {
    # ── Already installed — check version ───────────────────────────────────────
    Write-Status "WebView2 Runtime detected"              -Level OK
    Write-Status "  Display name  : $($installed.DisplayName)"
    Write-Status "  Installed ver : $($installed.Version)"
    Write-Status "  Registry path : $($installed.RegistryPath)"
    Write-Host ""

    if ($installed.Version -lt $MinTeamsVersion) {
        Write-Status ("Installed version {0} is BELOW the minimum required {1}." -f $installed.Version, $MinTeamsVersion) -Level WARN
        Write-Status "Updating WebView2 Runtime..." -Level WARN
        Write-Host ""

        try {
            Install-WebView2 -Mode 'update'
        } catch {
            Write-Status $_ -Level ERROR
            exit 1
        }

    } else {
        Write-Status ("Installed version {0} meets the minimum requirement ({1})." -f $installed.Version, $MinTeamsVersion) -Level OK
        Write-Status "No action required — MS Teams WebView2 requirement is satisfied." -Level OK
    }
}

# ── Post-install version confirmation ────────────────────────────────────────────
Write-Host ""
Write-Status "Verifying WebView2 version after operation..."
$postInstall = Get-InstalledWebView2Version

if ($null -ne $postInstall) {
    Write-Status "Confirmed installed version: $($postInstall.Version)" -Level OK

    if ($postInstall.Version -ge $MinTeamsVersion) {
        Write-Status "WebView2 is compatible with MS Teams." -Level OK
    } else {
        Write-Status "WebView2 version still does not meet Teams minimum. Manual intervention may be needed." -Level ERROR
        exit 1
    }
} else {
    Write-Status "Could not detect WebView2 after install attempt. Please reboot and re-run." -Level ERROR
    exit 1
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
