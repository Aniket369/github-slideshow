<#
.SYNOPSIS
    Audio / Video Device Health Check — Enterprise Helpdesk Edition v2.0

.DESCRIPTION
    Runs a full AV health report covering privacy settings, device status,
    camera shutter detection, driver info, audio services, default devices,
    app conflicts, and enterprise headset presence.
    No Administrator rights required.
#>

#Requires -Version 5.1

Clear-Host

# ── Counters ──────────────────────────────────────────────────────────────────
$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0

function Write-Pass {
    param($Text)
    $script:PassCount++
    Write-Host "  [PASS] $Text" -ForegroundColor Green
}
function Write-Fail {
    param($Text)
    $script:FailCount++
    Write-Host "  [FAIL] $Text" -ForegroundColor Red
}
function Write-Warn {
    param($Text)
    $script:WarnCount++
    Write-Host "  [WARN] $Text" -ForegroundColor Yellow
}
function Write-Info {
    param($Text)
    Write-Host "  [INFO] $Text" -ForegroundColor Cyan
}
function Write-Section {
    param($Title)
    Write-Host ""
    Write-Host "  ── $Title " -ForegroundColor Yellow -NoNewline
    $pad = 50 - $Title.Length
    if ($pad -gt 0) { Write-Host ("─" * $pad) -ForegroundColor DarkGray } else { Write-Host "" }
}

# ── Header ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     AUDIO / VIDEO DEVICE HEALTH REPORT          ║" -ForegroundColor Cyan
Write-Host "  ║     Enterprise Helpdesk Edition  v2.0           ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Computer  : $env:COMPUTERNAME"                          -ForegroundColor Gray
Write-Host "  User      : $env:USERDOMAIN\$env:USERNAME"             -ForegroundColor Gray
Write-Host "  Date/Time : $(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host "  OS        : $((Get-CimInstance Win32_OperatingSystem).Caption)" -ForegroundColor Gray

# ── 1. AUDIO SERVICES ─────────────────────────────────────────────────────────
Write-Section "AUDIO SERVICES"

$AudioServices = @(
    @{ Name = 'Audiosrv';  Label = 'Windows Audio' },
    @{ Name = 'AudioEndpointBuilder'; Label = 'Audio Endpoint Builder' },
    @{ Name = 'RpcSs';     Label = 'Remote Procedure Call (dependency)' }
)

foreach ($svc in $AudioServices) {
    try {
        $s = Get-Service -Name $svc.Name -ErrorAction Stop
        if ($s.Status -eq 'Running') {
            Write-Pass "$($svc.Label) is running"
        } else {
            Write-Fail "$($svc.Label) is $($s.Status)"
        }
    } catch {
        Write-Warn "$($svc.Label) — service not found"
    }
}

# ── 2. MICROPHONE PRIVACY ─────────────────────────────────────────────────────
Write-Section "MICROPHONE PRIVACY"

$MicPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"
if (Test-Path $MicPath) {
    $MicVal = (Get-ItemProperty $MicPath).Value
    if ($MicVal -eq 'Allow') {
        Write-Pass "Microphone access is Allowed"
    } else {
        Write-Fail "Microphone access is Blocked ($MicVal) — fix: ms-settings:privacy-microphone"
    }

    # Check which apps last accessed the microphone
    $MicApps = Get-ChildItem "$MicPath\NonPackaged" -ErrorAction SilentlyContinue
    if ($MicApps) {
        Write-Info "Apps with recent microphone access:"
        foreach ($app in $MicApps) {
            $appProp = Get-ItemProperty $app.PSPath -ErrorAction SilentlyContinue
            if ($appProp.LastUsedTimeStart) {
                $ts = [datetime]::FromFileTime($appProp.LastUsedTimeStart)
                Write-Info "  $($app.PSChildName.Split('#')[-1])  (last used: $($ts.ToString('dd-MMM-yyyy HH:mm')))"
            }
        }
    }
} else {
    Write-Warn "Microphone privacy key not found in registry"
}

# ── 3. CAMERA PRIVACY ────────────────────────────────────────────────────────
Write-Section "CAMERA PRIVACY"

$CamPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
if (Test-Path $CamPath) {
    $CamVal = (Get-ItemProperty $CamPath).Value
    if ($CamVal -eq 'Allow') {
        Write-Pass "Camera access is Allowed"
    } else {
        Write-Fail "Camera access is Blocked ($CamVal) — fix: ms-settings:privacy-webcam"
    }

    # Check which apps last accessed the camera
    $CamApps = Get-ChildItem "$CamPath\NonPackaged" -ErrorAction SilentlyContinue
    if ($CamApps) {
        Write-Info "Apps with recent camera access:"
        foreach ($app in $CamApps) {
            $appProp = Get-ItemProperty $app.PSPath -ErrorAction SilentlyContinue
            if ($appProp.LastUsedTimeStart) {
                $ts = [datetime]::FromFileTime($appProp.LastUsedTimeStart)
                Write-Info "  $($app.PSChildName.Split('#')[-1])  (last used: $($ts.ToString('dd-MMM-yyyy HH:mm')))"
            }
        }
    }
} else {
    Write-Warn "Camera privacy key not found in registry"
}

# ── 4. GROUP POLICY RESTRICTIONS ─────────────────────────────────────────────
Write-Section "GROUP POLICY RESTRICTIONS"

$PolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
if (Test-Path $PolicyPath) {
    Write-Warn "IT policy restrictions detected — listing values:"
    try {
        Get-ItemProperty $PolicyPath | Format-List | Out-String | ForEach-Object {
            Write-Host "  $_" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Warn "Unable to read policy values"
    }
} else {
    Write-Pass "No AppPrivacy Group Policy restrictions found"
}

# ── 5. CAMERA DEVICES & SHUTTER CHECK ────────────────────────────────────────
Write-Section "CAMERA DEVICES & SHUTTER CHECK"

# PnP device status
$Cameras = Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue

if ($Cameras) {
    foreach ($cam in $Cameras) {

        if ($cam.Status -eq 'OK') {
            Write-Pass "$($cam.FriendlyName)"
        } elseif ($cam.Status -eq 'Unknown') {
            Write-Warn "$($cam.FriendlyName) — status Unknown (may be disabled or in use)"
        } else {
            Write-Fail "$($cam.FriendlyName) — Status: $($cam.Status)"
        }

        # Driver info
        try {
            $drv = Get-PnpDeviceProperty -InstanceId $cam.InstanceId `
                -KeyName 'DEVPKEY_Device_DriverDate','DEVPKEY_Device_DriverVersion' `
                -ErrorAction SilentlyContinue
            $drvDate    = ($drv | Where-Object { $_.KeyName -match 'DriverDate' }).Data
            $drvVersion = ($drv | Where-Object { $_.KeyName -match 'DriverVersion' }).Data
            if ($drvVersion) { Write-Info "  Driver : v$drvVersion  (dated $($drvDate.ToString('dd-MMM-yyyy')))" }
        } catch {}

        # WMI error code — detects driver-level problems (e.g. closed shutter on some hardware)
        try {
            $wmiCam = Get-CimInstance Win32_PnPEntity |
                Where-Object { $_.DeviceID -eq $cam.InstanceId } |
                Select-Object -First 1
            $errCode = $wmiCam.ConfigManagerErrorCode
            $errMap  = @{
                0  = $null
                1  = 'Device not configured correctly'
                10 = 'Device cannot start'
                18 = 'Reinstall device drivers'
                22 = 'Device is disabled'
                28 = 'Drivers not installed'
                43 = 'Device stopped (possible hardware shutter or power issue)'
                45 = 'Device not connected'
            }
            if ($errCode -and $errCode -ne 0) {
                $msg = $errMap[$errCode] ?? "WMI error code $errCode"
                Write-Warn "  WMI    : $msg"
            }
        } catch {}
    }
} else {
    Write-Fail "No camera devices detected"
}

# ── Camera shutter detection ──────────────────────────────────────────────────
Write-Host ""
Write-Host "  ·· Physical / Software Shutter Check" -ForegroundColor DarkCyan

# Manufacturer-specific shutter registry checks
$ShutterChecks = @(
    @{ Brand='HP';     Path='HKLM:\SOFTWARE\HP\HP Privacy Settings';      ValueName='CameraShutter' },
    @{ Brand='HP';     Path='HKLM:\SOFTWARE\HP\HPSystemEventUtility';     ValueName=$null },
    @{ Brand='Lenovo'; Path='HKLM:\SOFTWARE\Lenovo\ThinkShutter';         ValueName=$null },
    @{ Brand='Lenovo'; Path='HKLM:\SOFTWARE\Lenovo\ImController\Plugins\LenovoCameraSettingsPackage'; ValueName=$null },
    @{ Brand='Dell';   Path='HKLM:\SOFTWARE\Dell\CCO';                    ValueName=$null }
)

$shutterBrandFound = $false
foreach ($check in $ShutterChecks) {
    if (Test-Path $check.Path) {
        $shutterBrandFound = $true
        Write-Info "$($check.Brand) privacy/shutter software detected at: $($check.Path)"
        if ($check.ValueName) {
            try {
                $val = (Get-ItemProperty $check.Path).$($check.ValueName)
                Write-Info "  $($check.ValueName) = $val"
            } catch {}
        }
    }
}

if (-not $shutterBrandFound) {
    Write-Info "No manufacturer-specific shutter registry key found"
    Write-Info "  → If your camera has a physical slider/switch, ensure it is open"
}

# Windows Camera Frame Server — if stopped, camera stream is broken
$cfs = Get-Service -Name 'FrameServer' -ErrorAction SilentlyContinue
if ($cfs) {
    if ($cfs.Status -eq 'Running') {
        Write-Pass "Windows Camera Frame Server is running"
    } else {
        Write-Fail "Windows Camera Frame Server is $($cfs.Status) — camera feed will fail"
    }
} else {
    Write-Warn "Windows Camera Frame Server service not found (older OS)"
}

# Check if camera is currently locked by another process
$CamInUsePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
$recentApps = Get-ChildItem "$CamInUsePath\NonPackaged" -ErrorAction SilentlyContinue |
    Where-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $p.LastUsedTimeStop -eq 0 -and $p.LastUsedTimeStart -gt 0
    }
if ($recentApps) {
    Write-Warn "Camera may currently be in use by:"
    foreach ($a in $recentApps) {
        Write-Warn "  $($a.PSChildName.Split('#')[-1])"
    }
} else {
    Write-Pass "Camera does not appear to be locked by another app"
}

# ── 6. MICROPHONE DEVICES ────────────────────────────────────────────────────
Write-Section "MICROPHONE DEVICES"

$Mics = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Microphone|Mic' }

if ($Mics) {
    foreach ($mic in $Mics) {
        if ($mic.Status -eq 'OK') {
            Write-Pass "$($mic.FriendlyName)"
        } else {
            Write-Fail "$($mic.FriendlyName) — $($mic.Status)"
        }
        # Driver version
        try {
            $drv = Get-PnpDeviceProperty -InstanceId $mic.InstanceId `
                -KeyName 'DEVPKEY_Device_DriverVersion' -ErrorAction SilentlyContinue
            $drvVer = $drv.Data
            if ($drvVer) { Write-Info "  Driver : v$drvVer" }
        } catch {}
    }
} else {
    Write-Fail "No microphone devices detected"
}

# ── 7. SPEAKERS / HEADSETS ───────────────────────────────────────────────────
Write-Section "SPEAKERS / HEADSETS"

$Speakers = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -notmatch 'Microphone|Mic' }

if ($Speakers) {
    foreach ($spk in $Speakers) {
        if ($spk.Status -eq 'OK') {
            Write-Pass "$($spk.FriendlyName)"
        } else {
            Write-Fail "$($spk.FriendlyName) — $($spk.Status)"
        }
    }
} else {
    Write-Fail "No speaker/output devices detected"
}

# ── 8. DEFAULT AUDIO DEVICES ─────────────────────────────────────────────────
Write-Section "DEFAULT AUDIO DEVICES"

try {
    $DefaultAudioReg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio'
    $RenderPath  = "$DefaultAudioReg\Render"
    $CapturePath = "$DefaultAudioReg\Capture"

    # Default playback
    $defaultRender = Get-ChildItem $RenderPath -ErrorAction SilentlyContinue |
        Where-Object {
            $props = Get-ChildItem "$($_.PSPath)\Properties" -ErrorAction SilentlyContinue
            ($props | Get-ItemProperty -ErrorAction SilentlyContinue) -match 'Default'
        } | Select-Object -First 1

    # Simpler: report all active render/capture endpoints
    $renderDevices = Get-ChildItem $RenderPath -ErrorAction SilentlyContinue
    foreach ($dev in $renderDevices) {
        $state = (Get-ItemProperty $dev.PSPath -ErrorAction SilentlyContinue).DeviceState
        if ($state -eq 1) {  # 1 = DEVICE_STATE_ACTIVE
            $nameProp = Get-ItemProperty "$($dev.PSPath)\Properties" -ErrorAction SilentlyContinue
            Write-Info "Playback device active: $($dev.PSChildName)"
        }
    }

    if (-not $renderDevices) { Write-Warn "Could not enumerate render devices" }

} catch {
    Write-Warn "Default device check skipped: $_"
}

# Simpler fallback using Get-AudioDevice if module present
if (Get-Command Get-AudioDevice -ErrorAction SilentlyContinue) {
    $defPlay = Get-AudioDevice -Playback
    $defRec  = Get-AudioDevice -Recording
    if ($defPlay) { Write-Pass "Default Playback  : $($defPlay.Name)" }
    if ($defRec)  { Write-Pass "Default Recording : $($defRec.Name)" }
}

# ── 9. ENTERPRISE HEADSET DETECTION ─────────────────────────────────────────
Write-Section "ENTERPRISE HEADSET DETECTION"

$Brands = 'Jabra|Poly|Plantronics|EPOS|Sennheiser|Logitech|Yealink|Bose|Sony'
$EnterpriseDevices = Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match $Brands }

if ($EnterpriseDevices) {
    foreach ($dev in $EnterpriseDevices) {
        if ($dev.Status -eq 'OK') {
            Write-Pass "$($dev.FriendlyName)  [$($dev.Class)]"
        } else {
            Write-Warn "$($dev.FriendlyName) — $($dev.Status)"
        }
    }
} else {
    Write-Warn "No enterprise headset detected (checked: $Brands)"
}

# ── 10. APP CONFLICTS (camera/mic in use) ────────────────────────────────────
Write-Section "APP CONFLICT CHECK"

$ConflictApps = @('Teams','ms-teams','Zoom','WebexMeetings','Slack','obs64','obs32','discord')
$RunningConflicts = @()

foreach ($app in $ConflictApps) {
    $proc = Get-Process -Name $app -ErrorAction SilentlyContinue
    if ($proc) { $RunningConflicts += $proc.ProcessName }
}

if ($RunningConflicts.Count -gt 0) {
    Write-Warn "The following apps are running and may hold the camera/mic:"
    foreach ($r in $RunningConflicts) { Write-Warn "  $r" }
} else {
    Write-Pass "No known conflicting AV apps are running"
}

# ── 11. SETTINGS SHORTCUTS ───────────────────────────────────────────────────
Write-Section "QUICK SETTINGS SHORTCUTS"

$Shortcuts = @(
    @{ Label = 'Microphone Privacy'; Command = "Start-Process 'ms-settings:privacy-microphone'" },
    @{ Label = 'Camera Privacy';     Command = "Start-Process 'ms-settings:privacy-webcam'" },
    @{ Label = 'Sound Settings';     Command = "Start-Process 'ms-settings:sound'" },
    @{ Label = 'Camera Settings';    Command = "Start-Process 'ms-settings:camera'" },
    @{ Label = 'Bluetooth & Devices';Command = "Start-Process 'ms-settings:bluetooth'" }
)

foreach ($s in $Shortcuts) {
    Write-Host "  $($s.Label):" -ForegroundColor Gray
    Write-Host "    $($s.Command)" -ForegroundColor DarkCyan
}

# ── SUMMARY ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                    SUMMARY                      ║" -ForegroundColor Cyan
Write-Host "  ╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "  ║  PASS : $($script:PassCount.ToString().PadRight(3))                                   ║" -ForegroundColor Green
Write-Host "  ║  WARN : $($script:WarnCount.ToString().PadRight(3))                                   ║" -ForegroundColor Yellow
Write-Host "  ║  FAIL : $($script:FailCount.ToString().PadRight(3))                                   ║" -ForegroundColor Red
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($script:FailCount -eq 0 -and $script:WarnCount -eq 0) {
    Write-Host ""
    Write-Host "  All checks passed. AV devices look healthy." -ForegroundColor Green
} elseif ($script:FailCount -gt 0) {
    Write-Host ""
    Write-Host "  Action required — review [FAIL] items above." -ForegroundColor Red
} else {
    Write-Host ""
    Write-Host "  Review [WARN] items — may affect call quality." -ForegroundColor Yellow
}

# ── Optional: export report to file ──────────────────────────────────────────
$LogPath = "$env:TEMP\AVHealthCheck_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$export  = Read-Host "`n  Export report to file? (Y/N)"
if ($export -match '^[Yy]') {
    & $PSCommandPath *>&1 | Out-File -FilePath $LogPath -Encoding UTF8
    Write-Host "  Report saved to: $LogPath" -ForegroundColor Cyan
}

Write-Host ""
