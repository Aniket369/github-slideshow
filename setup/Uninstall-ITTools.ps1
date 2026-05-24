# ================================================================
#  IT Tools – SCCM Deployment Script (Uninstall)
#  Run as: SYSTEM
# ================================================================

Write-Host "Removing IT Tools..."

# Remove scripts
if (Test-Path "C:\IT-Tools") {
    Remove-Item -Path "C:\IT-Tools" -Recurse -Force
    Write-Host "  Removed: C:\IT-Tools"
}

# Remove URL protocol registration
$registryBase = "HKLM:\SOFTWARE\Classes\ittools"
if (Test-Path $registryBase) {
    Remove-Item -Path $registryBase -Recurse -Force
    Write-Host "  Removed: registry key $registryBase"
}

Write-Host "IT Tools uninstalled successfully."
