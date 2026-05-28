# ================================================================
#  IT Tools - URL Protocol Handler
#  Installed once by Start-Here.bat.
# ================================================================

param ([string]$Url)

$action = $Url -replace 'ittools://', '' -replace '/$', '' -replace '/', ''
$base   = "https://raw.githubusercontent.com/Aniket369/github-slideshow/gh-pages/setup"

function Run-Script($scriptName) {
    $downloadsPath = "$env:USERPROFILE\Downloads\$scriptName"
    if (Test-Path $downloadsPath) {
        Write-Host ""
        Write-Host "  Running script from Downloads folder..." -ForegroundColor Cyan
        Write-Host "  File: $downloadsPath" -ForegroundColor DarkGray
        Write-Host ""
        try { Unblock-File -Path $downloadsPath -ErrorAction SilentlyContinue; & $downloadsPath }
        catch { Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep -Seconds 5 }
    } else {
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
        } catch { Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep -Seconds 5 }
    }
}

function Run-ElevatedScript($scriptName) {
    $downloadsPath = "$env:USERPROFILE\Downloads\$scriptName"
    $scriptPath    = $downloadsPath
    if (-not (Test-Path $downloadsPath)) {
        Write-Host ""
        Write-Host "  Fetching latest script from GitHub..." -ForegroundColor DarkGray
        Write-Host ""
        try {
            $tmp = [System.IO.Path]::GetTempPath() + $scriptName
            Invoke-WebRequest -Uri "$base/$scriptName" -OutFile $tmp -UseBasicParsing
            Unblock-File -Path $tmp
            $scriptPath = $tmp
        } catch { Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep -Seconds 5; return }
    } else {
        Unblock-File -Path $scriptPath -ErrorAction SilentlyContinue
    }
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
        -Verb RunAs
}

switch ($action) {
    'clear-teams-cache'   { Run-Script         'Clear-TeamsCache.ps1'          }
    'restart-pc'          { Run-Script         'Restart-PC.ps1'                }
    'gpupdate'            { Run-Script         'GPUpdate.ps1'                  }
    'sfc-scannow'         { Run-Script         'SFC-Scan.ps1'                  }
    'chkdsk'              { Run-Script         'ChkDsk.ps1'                    }
    'outlook-teams-addin' { Run-Script         'Outlook-TeamsMeetingAddin.ps1' }
    'webview2-check'      { Run-ElevatedScript 'Check-WebView2ForTeams.ps1'    }
    default { Write-Host "Unknown action: $action" -ForegroundColor Red; Start-Sleep -Seconds 3 }
}
