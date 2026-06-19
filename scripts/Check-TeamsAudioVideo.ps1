<#
.SYNOPSIS
    Checks common causes of Microsoft Teams audio/video call problems:
    Windows Audio service health, microphone/speaker/camera device status,
    best-effort default playback/recording device, Windows privacy
    permissions for camera & microphone, and other running apps that may
    be holding the camera/mic exclusively. Read-only — no admin required.
#>

$Host.UI.RawUI.WindowTitle = "Teams Audio/Video Health Check"
Clear-Host

function Write-Header { param($t) Write-Host "`n  ── $t " -ForegroundColor Cyan }
function Write-OK     { param($m) Write-Host "  ✔  $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "  ⚠  $m" -ForegroundColor Yellow }
function Write-Fail   { param($m) Write-Host "  ✘  $m" -ForegroundColor Red }
function Write-Info   { param($m) Write-Host "  ℹ  $m" -ForegroundColor White }

$Issues = [System.Collections.Generic.List[string]]::new()
function Add-Issue { param($m) $Issues.Add($m) }

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║       TEAMS AUDIO / VIDEO HEALTH CHECK        ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

# ── 1. Windows Audio Service ────────────────────────────────
Write-Header "Windows Audio Service"

foreach ($svcName in @('Audiosrv', 'AudioEndpointBuilder')) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Fail "$svcName service not found on this system."
        Add-Issue "$svcName service missing"
    } elseif ($svc.Status -ne 'Running') {
        Write-Fail "$($svc.DisplayName) is $($svc.Status) — audio devices will not work until this is running."
        Add-Issue "$($svc.DisplayName) service is not running"
    } else {
        Write-OK "$($svc.DisplayName) is running."
    }
}

# ── 2. Audio Devices (Speakers & Microphones) ───────────────
Write-Header "Audio Devices (Speakers & Microphones)"

$allEndpoints = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue
if (-not $allEndpoints) {
    Write-Warn "Could not enumerate audio endpoint devices on this system."
    Add-Issue "Unable to enumerate audio devices"
} else {
    $okEndpoints  = $allEndpoints | Where-Object { $_.Status -eq 'OK' }
    $badEndpoints = $allEndpoints | Where-Object { $_.Status -ne 'OK' }

    Write-Info "Total audio endpoints found : $($allEndpoints.Count)"
    Write-Info "Working (Status = OK)       : $($okEndpoints.Count)"

    if ($okEndpoints.Count -eq 0) {
        Write-Fail "No working audio endpoint devices detected — Teams has no mic/speaker to use."
        Add-Issue "No working audio devices detected"
    }

    foreach ($d in $okEndpoints)  { Write-OK   "$($d.FriendlyName)" }
    foreach ($d in $badEndpoints) {
        Write-Warn "$($d.FriendlyName) — Status: $($d.Status)"
        Add-Issue "Audio device '$($d.FriendlyName)' has Status=$($d.Status)"
    }

    $micLike = $okEndpoints | Where-Object { $_.FriendlyName -match 'Microphone|Mic\b|Headset' }
    if ($micLike.Count -eq 0) {
        Write-Warn "No device with a microphone-like name was found among working audio endpoints — verify a mic is connected."
        Add-Issue "No obvious working microphone device detected"
    }
}

# ── 3. Default Playback / Recording Device (best-effort) ───
Write-Header "Default Playback / Recording Device (best-effort)"

function Resolve-AudioDeviceName {
    param($DeviceIdString, $Flow)
    if (-not $DeviceIdString) { return $null }
    if ($DeviceIdString -notmatch '\}\.\{([0-9a-fA-F\-]{36})\}') { return $null }
    $guid = $Matches[1]
    $propPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$Flow\{$guid}\Properties"
    if (-not (Test-Path $propPath)) { return $null }
    foreach ($propName in @('{a45c254e-df1c-4efd-8020-67d146a850e0},14', '{a45c254e-df1c-4efd-8020-67d146a850e0},2')) {
        $val = (Get-ItemProperty -Path $propPath -Name $propName -ErrorAction SilentlyContinue).$propName
        if ($val) { return $val }
    }
    return $null
}

try {
    $playbackId = (Get-ItemProperty "HKCU:\Software\Microsoft\Multimedia\Sound Mapper" -Name Playback -ErrorAction Stop).Playback
    $recordId   = (Get-ItemProperty "HKCU:\Software\Microsoft\Multimedia\Sound Mapper" -Name Record   -ErrorAction Stop).Record

    $playbackName = Resolve-AudioDeviceName -DeviceIdString $playbackId -Flow 'Render'
    $recordName   = Resolve-AudioDeviceName -DeviceIdString $recordId   -Flow 'Capture'

    if ($playbackName) { Write-OK   "Default playback device  : $playbackName" }
    else                { Write-Warn "Could not resolve a friendly name for the default playback device." }

    if ($recordName)   { Write-OK   "Default recording device : $recordName" }
    else                { Write-Warn "Could not resolve a friendly name for the default recording device." }
} catch {
    Write-Warn "Could not read default audio device info from the registry (not available on all Windows builds)."
}

# ── 4. System Volume & Mute Status (Speaker & Microphone) ──
Write-Header "System Volume & Mute Status"

$volumeInteropCode = @"
using System;
using System.Runtime.InteropServices;

namespace TeamsAVVolumeCheck
{
    internal enum EDataFlow { eRender = 0, eCapture = 1, eAll = 2 }
    internal enum ERole { eConsole = 0, eMultimedia = 1, eCommunications = 2 }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(EDataFlow dataFlow, int dwStateMask, out IntPtr ppDevices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppEndpoint);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string pwstrId, out IMMDevice ppDevice);
        int RegisterEndpointNotificationCallback(IntPtr pClient);
        int UnregisterEndpointNotificationCallback(IntPtr pClient);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
        int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
        int GetState(out int pdwState);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume
    {
        int RegisterControlChangeNotify(IntPtr pNotify);
        int UnregisterControlChangeNotify(IntPtr pNotify);
        int GetChannelCount(out int pnChannelCount);
        int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
        int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
        int GetMasterVolumeLevel(out float pfLevelDB);
        int GetMasterVolumeLevelScalar(out float pfLevel);
        int SetChannelVolumeLevel(int nChannel, float fLevelDB, ref Guid pguidEventContext);
        int SetChannelVolumeLevelScalar(int nChannel, float fLevel, ref Guid pguidEventContext);
        int GetChannelVolumeLevel(int nChannel, out float pfLevelDB);
        int GetChannelVolumeLevelScalar(int nChannel, out float pfLevel);
        int SetMute(bool bMute, ref Guid pguidEventContext);
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
        int GetVolumeStepInfo(out int pnStep, out int pnStepCount);
        int VolumeStepUp(ref Guid pguidEventContext);
        int VolumeStepDown(ref Guid pguidEventContext);
        int QueryHardwareSupport(out int pdwHardwareSupportMask);
        int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
    }

    public static class AudioVolumeHelper
    {
        public static bool TryGetVolume(int dataFlow, out float scalarLevel, out bool isMuted)
        {
            scalarLevel = -1f;
            isMuted = false;
            try
            {
                var enumerator = (IMMDeviceEnumerator)(object)new MMDeviceEnumeratorComObject();
                IMMDevice device;
                int hr = enumerator.GetDefaultAudioEndpoint((EDataFlow)dataFlow, ERole.eConsole, out device);
                if (hr != 0 || device == null) return false;

                Guid iid = typeof(IAudioEndpointVolume).GUID;
                object iface;
                hr = device.Activate(ref iid, 1, IntPtr.Zero, out iface);
                if (hr != 0 || iface == null) return false;

                var epVolume = (IAudioEndpointVolume)iface;
                epVolume.GetMasterVolumeLevelScalar(out scalarLevel);
                epVolume.GetMute(out isMuted);
                return true;
            }
            catch
            {
                return false;
            }
        }
    }
}
"@

$volumeCheckAvailable = $false
try {
    Add-Type -TypeDefinition $volumeInteropCode -ErrorAction Stop
    $volumeCheckAvailable = $true
} catch {
    Write-Warn "Could not load the audio volume interop helper — skipping volume/mute checks."
}

if ($volumeCheckAvailable) {
    $spkLevel = 0.0; $spkMuted = $false
    $micLevel = 0.0; $micMuted = $false
    $spkOk = [TeamsAVVolumeCheck.AudioVolumeHelper]::TryGetVolume(0, [ref]$spkLevel, [ref]$spkMuted)
    $micOk = [TeamsAVVolumeCheck.AudioVolumeHelper]::TryGetVolume(1, [ref]$micLevel, [ref]$micMuted)

    if ($spkOk) {
        $spkPct = [math]::Round($spkLevel * 100)
        if ($spkMuted) {
            Write-Fail "Default speaker/output is MUTED in Windows volume settings."
            Add-Issue "Default speaker/output device is muted"
        } elseif ($spkPct -eq 0) {
            Write-Fail "Default speaker/output volume slider is at 0% in Windows volume settings."
            Add-Issue "Default speaker/output volume is at 0%"
        } else {
            Write-OK "Default speaker/output volume: $spkPct% (not muted)"
        }
    } else {
        Write-Warn "Could not read default speaker volume/mute state."
    }

    if ($micOk) {
        $micPct = [math]::Round($micLevel * 100)
        if ($micMuted) {
            Write-Fail "Default microphone is MUTED in Windows sound settings."
            Add-Issue "Default microphone is muted"
        } elseif ($micPct -eq 0) {
            Write-Fail "Default microphone input level is at 0% in Windows sound settings."
            Add-Issue "Default microphone input level is at 0%"
        } else {
            Write-OK "Default microphone level: $micPct% (not muted)"
        }
    } else {
        Write-Warn "Could not read default microphone volume/mute state."
    }
}

# ── 5. Camera Devices ────────────────────────────────────────
Write-Header "Camera Devices"

$cameras  = @()
$cameras += Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue
$cameras += Get-PnpDevice -Class Image  -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'cam|webcam' }
$cameras  = $cameras | Sort-Object InstanceId -Unique

if ($cameras.Count -eq 0) {
    Write-Fail "No camera devices detected on this system."
    Add-Issue "No camera detected"
} else {
    foreach ($cam in $cameras) {
        if ($cam.Status -eq 'OK') {
            Write-OK "$($cam.FriendlyName)"
        } else {
            Write-Fail "$($cam.FriendlyName) — Status: $($cam.Status)"
            Add-Issue "Camera '$($cam.FriendlyName)' has Status=$($cam.Status)"
        }
    }
    if (-not ($cameras | Where-Object { $_.Status -eq 'OK' })) {
        Write-Fail "All detected camera(s) are in a non-working state."
        Add-Issue "All cameras are non-functional (Status != OK)"
    }
}

# ── 6. Windows Privacy Permissions (Camera & Microphone) ────
Write-Header "Windows Privacy Permissions (Camera & Microphone)"

function Get-ConsentStatus {
    param($Capability)
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$Capability"
    if (Test-Path $path) {
        return (Get-ItemProperty -Path $path -Name Value -ErrorAction SilentlyContinue).Value
    }
    return $null
}

$camConsent = Get-ConsentStatus -Capability 'webcam'
$micConsent = Get-ConsentStatus -Capability 'microphone'

if     ($camConsent -eq 'Allow') { Write-OK   "Camera access is allowed at the Windows privacy level." }
elseif ($camConsent -eq 'Deny')  {
    Write-Fail "Camera access is BLOCKED at the Windows privacy level (Settings > Privacy & security > Camera)."
    Add-Issue "Windows privacy settings are blocking camera access"
} else { Write-Warn "Could not determine the Windows camera privacy setting." }

if     ($micConsent -eq 'Allow') { Write-OK   "Microphone access is allowed at the Windows privacy level." }
elseif ($micConsent -eq 'Deny')  {
    Write-Fail "Microphone access is BLOCKED at the Windows privacy level (Settings > Privacy & security > Microphone)."
    Add-Issue "Windows privacy settings are blocking microphone access"
} else { Write-Warn "Could not determine the Windows microphone privacy setting." }

$teamsAppConsentPaths = @(
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam\Microsoft.Teams_8wekyb3d8bbwe";     Device = 'camera' },
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\Microsoft.Teams_8wekyb3d8bbwe"; Device = 'microphone' },
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam\MSTeams_8wekyb3d8bbwe";              Device = 'camera' },
    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\MSTeams_8wekyb3d8bbwe";          Device = 'microphone' }
)
foreach ($entry in $teamsAppConsentPaths) {
    if (Test-Path $entry.Path) {
        $v = (Get-ItemProperty -Path $entry.Path -Name Value -ErrorAction SilentlyContinue).Value
        if ($v -eq 'Deny') {
            Write-Fail "Teams app-specific $($entry.Device) permission is set to Deny — Teams cannot use the $($entry.Device) even though the global Windows setting allows it."
            Add-Issue "Teams app-specific $($entry.Device) permission is Deny"
        } elseif ($v -eq 'Allow') {
            Write-OK "Teams app-specific $($entry.Device) permission: Allow"
        }
    }
}

# ── 7. Other Apps That May Be Holding the Camera/Microphone ─
Write-Header "Other Apps That May Be Holding the Camera/Microphone"

$conflictApps = @(
    @{ Name = 'Zoom';             Process = 'Zoom' },
    @{ Name = 'Skype (classic)';  Process = 'Skype' },
    @{ Name = 'Discord';          Process = 'Discord' },
    @{ Name = 'OBS Studio';       Process = 'obs64' },
    @{ Name = 'Cisco Webex';      Process = 'CiscoCollabHost' }
)

$conflictFound = $false
foreach ($app in $conflictApps) {
    if (Get-Process -Name $app.Process -ErrorAction SilentlyContinue) {
        Write-Warn "$($app.Name) is running — may be holding the camera/microphone exclusively, blocking Teams from accessing it."
        Add-Issue "$($app.Name) is running and may conflict with Teams for camera/mic access"
        $conflictFound = $true
    }
}
if (-not $conflictFound) {
    Write-OK "No common conflicting conferencing apps detected running."
}

# ── Summary ──────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                   SUMMARY                      ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($Issues.Count -eq 0) {
    Write-OK "No audio/video issues detected."
    Write-Info "If calls still have problems, check the correct mic/speaker/camera are selected inside Teams: Settings > Devices."
} else {
    Write-Fail "$($Issues.Count) potential issue(s) found:"
    $Issues | ForEach-Object { Write-Fail "  $_" }
    Write-Host ""
    Write-Info "Suggested next steps:"
    Write-Info "  1. In Teams: Settings > Devices, confirm the correct mic/speaker/camera are selected."
    Write-Info "  2. Windows Settings > Privacy & security > Camera/Microphone — ensure access is allowed."
    Write-Info "  3. Close other apps that may be using the camera/microphone (Zoom, Skype, Discord, OBS, etc.)."
    Write-Info "  4. Restart the Windows Audio service, or reboot, if audio devices show as non-OK."
}

Write-Host ""
Read-Host "  Press Enter to close"
