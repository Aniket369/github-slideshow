<#
.SYNOPSIS
    Checks whether Zscaler Client Connector is installed and, if so, whether
    the user is currently logged in. If logged in, prompts the user to log out.

.DESCRIPTION
    - Detects Zscaler Client Connector via installed-program registry entries
      and the ZSAService Windows service.
    - Locates ZSATrayManager.exe (the Client Connector CLI) and uses its
      "/status" output to determine the current login state.
    - If the user is logged in, shows a Yes/No prompt asking whether to log
      out, and runs "/logout" if confirmed.

.NOTES
    - Intended for Windows. Run from an elevated PowerShell session if the
      Zscaler service / install paths require it.
    - The exact wording of "ZSATrayManager.exe /status" can vary slightly by
      Client Connector version; adjust the matches in Get-ZscalerLoginStatus
      if your version reports status differently.
#>

[CmdletBinding()]
param()

function Get-ZscalerInstallInfo {
    $installed = $false
    $installPath = $null

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($root in $uninstallRoots) {
        $match = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*Zscaler*' } |
            Select-Object -First 1

        if ($match) {
            $installed = $true
            if ($match.InstallLocation) {
                $installPath = $match.InstallLocation
            }
            break
        }
    }

    $service = Get-Service -Name 'ZSAService' -ErrorAction SilentlyContinue
    if ($service) {
        $installed = $true
    }

    if (-not $installPath) {
        foreach ($candidate in @(
            "$env:ProgramFiles\Zscaler",
            "${env:ProgramFiles(x86)}\Zscaler"
        )) {
            if (Test-Path $candidate) {
                $installPath = $candidate
                $installed = $true
                break
            }
        }
    }

    [PSCustomObject]@{
        Installed   = $installed
        InstallPath = $installPath
        Service     = $service
    }
}

function Find-ZsaTrayManager {
    param([string]$InstallPath)

    $searchRoots = New-Object System.Collections.Generic.List[string]
    if ($InstallPath) { $searchRoots.Add($InstallPath) }
    $searchRoots.Add("$env:ProgramFiles\Zscaler")
    $searchRoots.Add("${env:ProgramFiles(x86)}\Zscaler")

    foreach ($root in ($searchRoots | Select-Object -Unique)) {
        if ($root -and (Test-Path $root)) {
            $exe = Get-ChildItem -Path $root -Filter 'ZSATrayManager.exe' -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($exe) { return $exe.FullName }
        }
    }

    return $null
}

function Get-ZscalerLoginStatus {
    param([string]$TrayManagerPath)

    if (-not $TrayManagerPath) {
        return 'Unknown'
    }

    try {
        $output = & $TrayManagerPath '/status' 2>$null
    } catch {
        return 'Unknown'
    }

    $text = ($output -join "`n")

    if ($text -match 'Logged In') {
        return 'LoggedIn'
    } elseif ($text -match 'Logged Out|Not Logged In') {
        return 'LoggedOut'
    } else {
        return 'Unknown'
    }
}

function Show-LogoutPrompt {
    param([string]$Message)

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $result = [System.Windows.Forms.MessageBox]::Show(
            $Message,
            'Zscaler Client Connector',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
    } catch {
        $answer = Read-Host "$Message (Y/N)"
        return ($answer -match '^[Yy]')
    }
}

# ---- Main ----

$info = Get-ZscalerInstallInfo

if (-not $info.Installed) {
    Write-Host 'Zscaler Client Connector is not installed on this machine.' -ForegroundColor Yellow
    exit 0
}

Write-Host 'Zscaler Client Connector is installed.' -ForegroundColor Green
if ($info.InstallPath) {
    Write-Host "Install path: $($info.InstallPath)"
}

$trayManager = Find-ZsaTrayManager -InstallPath $info.InstallPath
$status = Get-ZscalerLoginStatus -TrayManagerPath $trayManager

switch ($status) {
    'LoggedIn' {
        Write-Host 'Zscaler is currently LOGGED IN.' -ForegroundColor Cyan

        $shouldLogout = Show-LogoutPrompt -Message 'Zscaler is currently logged in. Do you want to log out now?'

        if ($shouldLogout) {
            & $trayManager '/logout' | Out-Null
            Start-Sleep -Seconds 2

            $newStatus = Get-ZscalerLoginStatus -TrayManagerPath $trayManager
            if ($newStatus -eq 'LoggedOut') {
                Write-Host 'Zscaler has been logged out successfully.' -ForegroundColor Green
            } else {
                Write-Host 'Logout command sent. Verify status manually if needed.' -ForegroundColor Yellow
            }
        } else {
            Write-Host 'User chose not to log out.' -ForegroundColor Yellow
        }
    }
    'LoggedOut' {
        Write-Host 'Zscaler is installed but currently LOGGED OUT.' -ForegroundColor Yellow
    }
    default {
        Write-Host 'Zscaler is installed, but the login status could not be determined.' -ForegroundColor DarkYellow
        if (-not $trayManager) {
            Write-Host 'ZSATrayManager.exe was not found in the expected install locations.' -ForegroundColor DarkYellow
        }
    }
}
