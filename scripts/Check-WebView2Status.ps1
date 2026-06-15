<#
.SYNOPSIS
    Checks if Microsoft Edge WebView2 Runtime (x64) is installed and healthy,
    and silently installs/repairs it if it's missing or corrupted.

.PARAMETER InstallerSource
    URL or local/UNC path to the WebView2 installer. Defaults to Microsoft's
    stable Evergreen Bootstrapper, which downloads and installs the correct
    x64 runtime for this machine. For offline/air-gapped environments, point
    this at a pre-staged MicrosoftEdgeWebView2RuntimeInstallerX64.exe instead.

.NOTES
    Exit codes (useful for Intune/SCCM detection + remediation):
      0 = WebView2 is installed and healthy
      1 = WebView2 was missing/corrupted and has been (re)installed successfully
      2 = Install/repair failed
#>

[CmdletBinding()]
param(
    [string]$InstallerSource = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
)

$guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'  # WebView2 Runtime product GUID

function Test-WebView2 {
    $key = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$guid",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid",
        "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$guid"
    ) | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_.pv } | Select-Object -First 1

    if (-not $key) {
        return [PSCustomObject]@{ Installed = $false; Healthy = $false; Version = $null }
    }

    $version = $key.pv
    $searchDirs = @(
        "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application\$version",
        "$env:ProgramFiles\Microsoft\EdgeWebView\Application\$version"
    )
    $exe = Get-ChildItem -Path $searchDirs -Filter 'msedgewebview2.exe' -ErrorAction SilentlyContinue | Select-Object -First 1

    $healthy = $false
    if ($exe -and (Test-Path (Join-Path $exe.Directory.FullName 'msedge.dll'))) {
        $healthy = ($exe.VersionInfo.ProductVersion -eq $version)
    }

    [PSCustomObject]@{ Installed = $true; Healthy = $healthy; Version = $version }
}

function Install-WebView2 {
    param([string]$Source)

    $isUrl = $Source -match '^https?://'
    $installerPath = $Source

    if ($isUrl) {
        $installerPath = Join-Path $env:TEMP 'MicrosoftEdgeWebView2Setup.exe'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        Write-Host "Downloading WebView2 installer from $Source ..."
        try {
            Invoke-WebRequest -Uri $Source -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "Download failed: $_" -ForegroundColor Red
            return -1
        }
    }

    Write-Host "Running WebView2 installer (silent, x64)..."
    $proc = Start-Process -FilePath $installerPath -ArgumentList '/silent', '/install' -Wait -PassThru

    if ($isUrl) { Remove-Item $installerPath -ErrorAction SilentlyContinue }

    return $proc.ExitCode
}

# ---- Main ----

$status = Test-WebView2

if ($status.Installed -and $status.Healthy) {
    Write-Host "WebView2 Runtime is installed and healthy (version $($status.Version))." -ForegroundColor Green
    exit 0
}

if (-not $status.Installed) {
    Write-Host "WebView2 Runtime is NOT installed. Installing..." -ForegroundColor Yellow
} else {
    Write-Host "WebView2 Runtime is installed but appears CORRUPTED (version $($status.Version)). Repairing..." -ForegroundColor Yellow
}

$exitCode = Install-WebView2 -Source $InstallerSource
if ($exitCode -ne 0) {
    Write-Host "WebView2 install/repair failed with exit code $exitCode." -ForegroundColor Red
    exit 2
}

$status = Test-WebView2
if ($status.Installed -and $status.Healthy) {
    Write-Host "WebView2 Runtime installed successfully (version $($status.Version))." -ForegroundColor Green
    exit 1
} else {
    Write-Host "WebView2 Runtime still not healthy after install." -ForegroundColor Red
    exit 2
}
