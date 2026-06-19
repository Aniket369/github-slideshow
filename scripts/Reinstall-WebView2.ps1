<#
.SYNOPSIS
    Uninstalls and reinstalls Microsoft Edge WebView2 Runtime (x64).
    Prompts for administrator credentials if not already running elevated.

.PARAMETER InstallerSource
    URL or local/UNC path to the WebView2 installer. Defaults to Microsoft's
    stable Evergreen Bootstrapper, which installs the correct x64 runtime
    for this machine.
#>

[CmdletBinding()]
param(
    [string]$InstallerSource = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
)

# ── Elevate with admin credentials if needed ───────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Administrator rights are required to uninstall/reinstall WebView2." -ForegroundColor Yellow
    $cred = Get-Credential -Message "Enter administrator credentials to continue"

    $scriptArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -InstallerSource `"$InstallerSource`""
    Start-Process -FilePath 'powershell.exe' -Credential $cred -ArgumentList $scriptArgs -Wait
    exit
}

Write-Host "Running with administrator rights." -ForegroundColor Green

# ── 1. Uninstall any existing WebView2 Runtime(s) ───────────────
Write-Host "`nLooking for installed WebView2 Runtime..." -ForegroundColor Cyan

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$apps = Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*WebView2*' }

if (-not $apps) {
    Write-Host "No WebView2 Runtime installation found to remove." -ForegroundColor Yellow
} else {
    foreach ($app in $apps) {
        Write-Host "Uninstalling: $($app.DisplayName) ($($app.DisplayVersion))" -ForegroundColor Yellow

        if ($app.UninstallString -match '^"?(.+?\.exe)"?(\s+.*)?$') {
            $exePath = $Matches[1]
            $exeArgs = $Matches[2].Trim()
            Start-Process -FilePath $exePath -ArgumentList $exeArgs -Wait -ErrorAction SilentlyContinue
            Write-Host "  Removed." -ForegroundColor Green
        } else {
            Write-Host "  Could not parse uninstall command, skipping." -ForegroundColor Red
        }
    }
}

# ── 2. Reinstall via Evergreen Bootstrapper (x64) ────────────────
Write-Host "`nReinstalling WebView2 Runtime (x64)..." -ForegroundColor Cyan

$isUrl = $InstallerSource -match '^https?://'
$installerPath = $InstallerSource

if ($isUrl) {
    $installerPath = Join-Path $env:TEMP 'MicrosoftEdgeWebView2Setup.exe'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    Write-Host "Downloading installer from $InstallerSource ..."
    Invoke-WebRequest -Uri $InstallerSource -OutFile $installerPath -UseBasicParsing
}

Start-Process -FilePath $installerPath -ArgumentList '/silent', '/install' -Wait

if ($isUrl) { Remove-Item $installerPath -ErrorAction SilentlyContinue }

# ── 3. Verify ─────────────────────────────────────────────────
$guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$key = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$guid",
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid"
) | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
    Where-Object { $_.pv } | Select-Object -First 1

if ($key) {
    Write-Host "`nWebView2 Runtime reinstalled successfully (version $($key.pv))." -ForegroundColor Green
} else {
    Write-Host "`nReinstall finished, but WebView2 Runtime registration was not found." -ForegroundColor Red
}

Read-Host "`nPress Enter to close"
