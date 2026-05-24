# ================================================================
#  IT Tools - URL Protocol Handler
#  This file lives locally on your PC (installed once by Start-Here.bat).
#  It always fetches the LATEST script from GitHub when a button
#  is clicked, so updates are automatic - no file management needed.
# ================================================================

param ([string]$Url)

$action = $Url -replace 'ittools://', '' -replace '/$', '' -replace '/', ''

# ── Always pull latest scripts from GitHub ────────────────────────
$base = "https://raw.githubusercontent.com/Aniket369/github-slideshow/gh-pages/setup"

function Run-FromGitHub($scriptName) {
    Write-Host ""
    Write-Host "  Fetching latest script from GitHub..." -ForegroundColor DarkGray
    try {
        $url = "$base/$scriptName"
        $tmp = [System.IO.Path]::GetTempPath() + $scriptName
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        Unblock-File -Path $tmp
        & $tmp
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  ERROR: Could not fetch script. Check your internet connection." -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkRed
        Start-Sleep -Seconds 5
    }
}

switch ($action) {
    'clear-teams-cache' { Run-FromGitHub "Clear-TeamsCache.ps1" }
    'restart-pc'        { Run-FromGitHub "Restart-PC.ps1"       }
    'gpupdate'          { Run-FromGitHub "GPUpdate.ps1"          }
    default {
        Write-Host "Unknown action: $action" -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
}
