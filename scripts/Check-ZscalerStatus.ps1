<#
.SYNOPSIS
    Checks if Zscaler Client Connector is installed and logged in,
    and prompts to log out if it is.
#>

# 1. Check if installed (service or install folder)
$service = Get-Service -Name 'ZSAService' -ErrorAction SilentlyContinue
$installDir = Get-Item "$env:ProgramFiles\Zscaler", "${env:ProgramFiles(x86)}\Zscaler" -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $service -and -not $installDir) {
    Write-Host "Zscaler is not installed." -ForegroundColor Yellow
    exit
}
Write-Host "Zscaler is installed." -ForegroundColor Green

# 2. Find the Client Connector CLI and check login status
$trayManager = Get-ChildItem "$env:ProgramFiles\Zscaler", "${env:ProgramFiles(x86)}\Zscaler" -Filter 'ZSATrayManager.exe' -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $trayManager) {
    Write-Host "Could not find ZSATrayManager.exe to check login status." -ForegroundColor Yellow
    exit
}

$status = & $trayManager '/status' 2>$null | Out-String

# 3. Prompt to log out if currently logged in
if ($status -match 'Logged In') {
    Write-Host "Zscaler is currently logged in." -ForegroundColor Cyan

    Add-Type -AssemblyName System.Windows.Forms
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Zscaler is currently logged in. Do you want to log out now?",
        "Zscaler Client Connector",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        & $trayManager '/logout' | Out-Null
        Write-Host "Logout command sent." -ForegroundColor Green
    }
} else {
    Write-Host "Zscaler is installed but not logged in." -ForegroundColor Yellow
}
