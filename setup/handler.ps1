# ================================================================
#  IT Tools - URL Protocol Handler
#  Installed once by Start-Here.bat.
#
#  Execution order:
#    1. If the user already clicked "Load" — runs the script from
#       their Downloads folder (so they can inspect it first).
#    2. Otherwise — fetches the latest version from GitHub.
# ================================================================

param ([string]$Url)

$action = $Url -replace 'ittools://', '' -replace '/$', '' -replace '/', ''
$base   = "https://raw.githubusercontent.com/Aniket369/github-slideshow/gh-pages/setup"

# ── Run a script: Downloads folder first, then GitHub ────────────
function Run-Script($scriptName) {
    $downloadsPath = "$env:USERPROFILE\Downloads\$scriptName"

    if (Test-Path $downloadsPath) {
        # User clicked Load before Run — execute their local copy
        Write-Host ""
        Write-Host "  Running script from Downloads folder..." -ForegroundColor Cyan
        Write-Host "  File: $downloadsPath" -ForegroundColor DarkGray
        Write-Host ""
        try {
            Unblock-File -Path $downloadsPath -ErrorAction SilentlyContinue
            & $downloadsPath
        } catch {
            Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
    } else {
        # No local copy — fetch the latest version from GitHub
        Write-Host ""
        Write-Host "  Fetching latest script from GitHub..." -ForegroundColor DarkGray
        Write-Host "  (Tip: click 'Load' first to inspect the script before running)" -ForegroundColor DarkGray
        Write-Host ""
        try {
            $tmp = [System.IO.Path]::GetTempPath() + $scriptName
            Invoke-WebRequest -Uri "$base/$scriptName" -OutFile $tmp -UseBasicParsing
            Unblock-File -Path $tmp
            & $tmp
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
    }
}

switch ($action) {
    'clear-teams-cache' { Run-Script "Clear-TeamsCache.ps1" }
    'restart-pc'        { Run-Script "Restart-PC.ps1"       }
    'gpupdate'          { Run-Script "GPUpdate.ps1"          }
    'sfc-scannow'       { Run-Script "SFC-Scan.ps1"          }
    'chkdsk'            { Run-Script "ChkDsk.ps1"            }
    default {
        Write-Host "Unknown action: $action" -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
}
