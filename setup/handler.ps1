# ================================================================
#  IT Tools – URL Protocol Handler
#  Installed to: C:\IT-Tools\handler.ps1
#
#  This script is called automatically by Windows every time a
#  user clicks a button on the IT Tools website.
#  It receives the URL (e.g. ittools://clear-teams-cache) and
#  runs the matching script.
# ================================================================

param (
    [string]$Url   # e.g. "ittools://clear-teams-cache"
)

# Strip the protocol prefix to get the action name
$action = $Url -replace 'ittools://', '' -replace '/$', '' -replace '/', ''

$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path

switch ($action) {

    'clear-teams-cache' {
        & "$scriptFolder\Clear-TeamsCache.ps1"
    }

    'restart-pc' {
        & "$scriptFolder\Restart-PC.ps1"
    }

    default {
        Write-Host "Unknown action: $action" -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
}
