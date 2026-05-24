# ================================================================
#  IT Tools - URL Protocol Handler
#  Installed once by Start-Here.bat. Always fetches the latest
#  scripts from GitHub on every button click.
# ================================================================

param ([string]$Url)

$action = $Url -replace 'ittools://', '' -replace '/$', '' -replace '/', ''
$base   = "https://raw.githubusercontent.com/Aniket369/github-slideshow/gh-pages/setup"

function Run-FromGitHub($scriptName) {
    Write-Host ""
    Write-Host "  Fetching latest script from GitHub..." -ForegroundColor DarkGray
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

switch ($action) {
    'clear-teams-cache' { Run-FromGitHub "Clear-TeamsCache.ps1" }
    'restart-pc'        { Run-FromGitHub "Restart-PC.ps1"       }
    'gpupdate'          { Run-FromGitHub "GPUpdate.ps1"          }
    'sfc-scannow'       { Run-FromGitHub "SFC-Scan.ps1"          }
    'chkdsk'            { Run-FromGitHub "ChkDsk.ps1"            }
    default {
        Write-Host "Unknown action: $action" -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
}
