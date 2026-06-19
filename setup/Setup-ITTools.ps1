# ================================================================
#  IT Tools – SCCM Deployment Script (Install)
#
#  PURPOSE : Deploys the IT Tools URL protocol handler to a PC.
#            Run this once per machine via SCCM.
#
#  RUN AS  : SYSTEM (or any local administrator account)
#
#  WHAT IT DOES:
#    1. Creates  C:\IT-Tools\  and copies all scripts there
#    2. Registers the  ittools://  custom URL protocol in Windows
#       so that any browser on this machine can trigger scripts
#       when a user clicks a button on the IT Tools website.
#
#  SCCM SETTINGS:
#    Install command   : powershell.exe -ExecutionPolicy Bypass -File Setup-ITTools.ps1
#    Uninstall command : powershell.exe -ExecutionPolicy Bypass -File Uninstall-ITTools.ps1
#    Detection method  : File exists  C:\IT-Tools\handler.ps1
#    Run as            : System
# ================================================================

$ErrorActionPreference = 'Stop'

# ── Configuration ───────────────────────────────────────────────
$installFolder = "C:\IT-Tools"           # Where scripts are placed on each PC
$protocolName  = "ittools"               # The custom URL protocol (ittools://)

# ── Step 1: Create install folder ──────────────────────────────
Write-Host "[1/3] Creating install folder: $installFolder"
if (-not (Test-Path $installFolder)) {
    New-Item -ItemType Directory -Path $installFolder -Force | Out-Null
}

# ── Step 2: Copy scripts to the machine ────────────────────────
Write-Host "[2/3] Copying scripts..."

# The source folder is wherever THIS script is running from.
# When deployed via SCCM, all files in the package are in the same folder.
$sourceFolder = Split-Path -Parent $MyInvocation.MyCommand.Path

$filesToCopy = @(
    "handler.ps1",
    "Clear-TeamsCache.ps1",
    "Restart-PC.ps1"
)

foreach ($file in $filesToCopy) {
    $src = Join-Path $sourceFolder $file
    $dst = Join-Path $installFolder $file
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "  Copied: $file"
    } else {
        Write-Warning "  File not found in package: $file"
    }
}

# ── Step 3: Register ittools:// URL protocol in Windows ────────
# We write to HKLM (Local Machine) so it works for ALL users on this PC.
# SCCM runs as SYSTEM which has full registry access.
Write-Host "[3/3] Registering URL protocol: $protocolName://"

$registryBase = "HKLM:\SOFTWARE\Classes\$protocolName"

# The command Windows will run when any browser opens an ittools:// link
$handlerCommand = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Normal -File `"$installFolder\handler.ps1`" `"%1`""

# Create the protocol entry
New-Item -Path $registryBase -Force | Out-Null
Set-ItemProperty -Path $registryBase -Name "(Default)"    -Value "URL:IT Tools Protocol"
Set-ItemProperty -Path $registryBase -Name "URL Protocol" -Value ""

# Create the command entry
New-Item -Path "$registryBase\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$registryBase\shell\open\command" -Name "(Default)" -Value $handlerCommand

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " IT Tools installed successfully!" -ForegroundColor Green
Write-Host " Install path : $installFolder"   -ForegroundColor Green
Write-Host " Protocol     : $protocolName`://"  -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
