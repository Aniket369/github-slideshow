<#
.SYNOPSIS
    Checks if Microsoft Edge WebView2 Runtime is installed and whether
    the installation appears corrupted (missing/mismatched files).
#>

$guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'  # WebView2 Runtime product GUID

# 1. Check install registration (Evergreen runtime via EdgeUpdate)
$key = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$guid",
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid",
    "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$guid"
) | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
    Where-Object { $_.pv } | Select-Object -First 1

if (-not $key) {
    Write-Host "WebView2 Runtime is NOT installed." -ForegroundColor Red
    exit
}

$version = $key.pv
Write-Host "WebView2 Runtime registered (version $version)." -ForegroundColor Green

# 2. Locate the runtime binary for that version
$searchDirs = @(
    "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application\$version",
    "$env:ProgramFiles\Microsoft\EdgeWebView\Application\$version"
)
$exe = Get-ChildItem -Path $searchDirs -Filter 'msedgewebview2.exe' -ErrorAction SilentlyContinue | Select-Object -First 1

# 3. Verify it's not corrupted
if (-not $exe) {
    Write-Host "CORRUPTED: msedgewebview2.exe not found for version $version." -ForegroundColor Red
    exit
}

if (-not (Test-Path (Join-Path $exe.Directory.FullName 'msedge.dll'))) {
    Write-Host "CORRUPTED: msedge.dll missing from $($exe.Directory.FullName)." -ForegroundColor Red
    exit
}

$fileVersion = $exe.VersionInfo.ProductVersion
if ($fileVersion -ne $version) {
    Write-Host "WARNING: Registered version ($version) != binary version ($fileVersion)." -ForegroundColor Yellow
} else {
    Write-Host "WebView2 Runtime looks healthy (version $fileVersion)." -ForegroundColor Green
}
