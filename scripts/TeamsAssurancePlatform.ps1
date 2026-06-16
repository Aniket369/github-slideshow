# ================================================================
#  Teams Assurance Platform v1.2
#  Network Diagnostic Module
#  Collects Teams-related network health, generates a report,
#  and optionally clears the DNS cache.
#  Usage: Right-click > Run with PowerShell
# ================================================================

$Host.UI.RawUI.WindowTitle = "Teams Assurance Platform"
Clear-Host
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ── Helpers ─────────────────────────────────────────────────
function Write-Header  { param($t) Write-Host "`n  ┌─────────────────────────────────────────────┐`n  │  $t`n  └─────────────────────────────────────────────┘" -ForegroundColor Cyan }
function Write-Section { param($t) Write-Host "`n  ── $t " -ForegroundColor DarkCyan }
function Write-OK      { param($m) Write-Host "     ✔  $m" -ForegroundColor Green  }
function Write-Warn    { param($m) Write-Host "     ⚠  $m" -ForegroundColor Yellow }
function Write-Fail    { param($m) Write-Host "     ✘  $m" -ForegroundColor Red    }
function Write-Info    { param($m) Write-Host "     ℹ  $m" -ForegroundColor White  }

$Report   = [System.Collections.Generic.List[string]]::new()
$Warnings = [System.Collections.Generic.List[string]]::new()
$Failures = [System.Collections.Generic.List[string]]::new()

function Add-Report  { param($m) $Report.Add($m)   }
function Add-Warning { param($m) $Warnings.Add($m) }
function Add-Failure { param($m) $Failures.Add($m) }

# ── Banner ──────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║       TEAMS ASSURANCE PLATFORM  v1.2         ║" -ForegroundColor Cyan
Write-Host "  ║       Network Diagnostic Module              ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$scanDate    = Get-Date -Format 'dd-MMM-yyyy HH:mm:ss'
$osCaption   = (Get-CimInstance Win32_OperatingSystem).Caption

Write-Info "Scan started : $scanDate"
Write-Info "Computer     : $env:COMPUTERNAME"
Write-Info "User         : $env:USERDOMAIN\$env:USERNAME"
Write-Info "OS           : $osCaption"

Add-Report "================================================================"
Add-Report " TEAMS ASSURANCE PLATFORM v1.2 — Network Diagnostic Report"
Add-Report "================================================================"
Add-Report "Scan Date : $scanDate"
Add-Report "Computer  : $env:COMPUTERNAME"
Add-Report "User      : $env:USERDOMAIN\$env:USERNAME"
Add-Report "OS        : $osCaption"
Add-Report ""

# ════════════════════════════════════════════════════════════
#  MODULE 1 — TEAMS INSTALLATION
# ════════════════════════════════════════════════════════════
Write-Header "Module 1 — Teams Installation"
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 1 : TEAMS INSTALLATION"
Add-Report "----------------------------------------------------------------"

$pkg = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue
if ($pkg) {
    Write-OK  "New Teams installed — v$($pkg.Version)"
    Write-OK  "Status   : $($pkg.Status)"
    Write-Info "Location : $($pkg.InstallLocation)"
    Add-Report "New Teams : INSTALLED  v$($pkg.Version)  [$($pkg.Status)]"
    Add-Report "Location  : $($pkg.InstallLocation)"
} else {
    Write-Fail "New Teams (MSTeams) NOT found"
    Add-Report "New Teams : NOT INSTALLED"
    Add-Failure "New Teams package not found on this machine"
}

$configFile = "$env:APPDATA\Microsoft\Teams\desktop-config.json"
if (Test-Path $configFile) {
    try {
        $config     = Get-Content $configFile -Raw | ConvertFrom-Json
        $disableUDP = if ($null -ne $config.disableUDP) { $config.disableUDP } else { "Not set (UDP enabled)" }
        Write-Info "Disable UDP: $disableUDP"
        Add-Report "Config disableUDP : $disableUDP"
        if ($config.disableUDP -eq $true) {
            Write-Warn "UDP is disabled in Teams config — call quality may be degraded"
            Add-Warning "UDP disabled in Teams desktop-config.json — degrades call/meeting quality"
        }
    } catch {
        Write-Warn "Could not parse Teams config file"
        Add-Report "Config file : Parse error"
    }
} else {
    Write-Info "Teams config file not found (Teams 2.0 / fresh install)"
    Add-Report "Config file : Not found"
}

# ════════════════════════════════════════════════════════════
#  MODULE 2 — NETWORK ADAPTERS
# ════════════════════════════════════════════════════════════
Write-Header "Module 2 — Network Adapters"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 2 : NETWORK ADAPTERS"
Add-Report "----------------------------------------------------------------"

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
if ($adapters) {
    foreach ($a in $adapters) {
        $ip = (Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        Write-OK  "$($a.Name) — $($a.InterfaceDescription)"
        Write-Info "  IP: $ip  |  Speed: $($a.LinkSpeed)  |  MAC: $($a.MacAddress)"
        Add-Report "Adapter : $($a.Name) | IP: $ip | Speed: $($a.LinkSpeed) | MAC: $($a.MacAddress)"

        if ($a.InterfaceDescription -match "VPN|Cisco|Pulse|GlobalProtect|FortiClient|Zscaler|SonicWall") {
            Write-Warn "VPN adapter detected — may affect Teams media routing"
            Add-Warning "VPN adapter active: $($a.Name) — $($a.InterfaceDescription)"
        }
    }
} else {
    Write-Fail "No active network adapters found"
    Add-Failure "No active network adapters"
}

# ════════════════════════════════════════════════════════════
#  MODULE 3 — DNS RESOLUTION
# ════════════════════════════════════════════════════════════
Write-Header "Module 3 — DNS Resolution"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 3 : DNS RESOLUTION"
Add-Report "----------------------------------------------------------------"

$dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses } |
    Select-Object -ExpandProperty ServerAddresses -Unique
Write-Info "DNS Servers: $($dnsServers -join ', ')"
Add-Report "DNS Servers : $($dnsServers -join ', ')"

$dnsTargets = @(
    "teams.microsoft.com",
    "login.microsoftonline.com",
    "outlook.office365.com",
    "statics.teams.cdn.office.net",
    "aadcdn.msftauth.net",
    "api.interfaces.records.teams.microsoft.com",
    "worldaz.tr.teams.microsoft.com"
)

foreach ($target in $dnsTargets) {
    try {
        $resolved = Resolve-DnsName -Name $target -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } |
            Select-Object -ExpandProperty IPAddress -First 3
        Write-OK  "$target → $($resolved -join ', ')"
        Add-Report "DNS OK   : $target → $($resolved -join ', ')"
    } catch {
        Write-Fail "$target — RESOLUTION FAILED"
        Add-Report "DNS FAIL : $target — $($_.Exception.Message)"
        Add-Failure "DNS resolution failed: $target"
    }
}

# ════════════════════════════════════════════════════════════
#  MODULE 4 — PROXY CONFIGURATION
# ════════════════════════════════════════════════════════════
Write-Header "Module 4 — Proxy Configuration"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 4 : PROXY CONFIGURATION"
Add-Report "----------------------------------------------------------------"

$proxy = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
$proxyEnabled = $proxy.ProxyEnable
$proxyServer  = if ($proxy.ProxyServer)    { $proxy.ProxyServer    } else { 'Not configured' }
$proxyBypass  = if ($proxy.ProxyOverride)  { $proxy.ProxyOverride  } else { 'None' }
$proxyPAC     = if ($proxy.AutoConfigURL)  { $proxy.AutoConfigURL  } else { 'Not configured' }

Write-Info "Proxy Enabled  : $(if ($proxyEnabled -eq 1) { 'YES' } else { 'NO' })"
Write-Info "Proxy Server   : $proxyServer"
Write-Info "Proxy Bypass   : $proxyBypass"
Write-Info "PAC / Auto URL : $proxyPAC"

Add-Report "Proxy Enabled  : $(if ($proxyEnabled -eq 1) { 'YES' } else { 'NO' })"
Add-Report "Proxy Server   : $proxyServer"
Add-Report "Proxy Bypass   : $proxyBypass"
Add-Report "PAC URL        : $proxyPAC"

if ($proxyEnabled -eq 1) {
    Write-Warn "Proxy is active — ensure Microsoft 365 IPs are in bypass list"
    Add-Warning "Proxy enabled ($proxyServer) — Microsoft 365 endpoints should be bypassed"
    if ($proxyBypass -match "microsoft|office365|teams") {
        Write-OK "Microsoft domains found in proxy bypass list"
        Add-Report "Microsoft bypass : FOUND"
    } else {
        Write-Warn "Microsoft domains NOT in proxy bypass list"
        Add-Warning "Microsoft/Teams domains missing from proxy bypass — common cause of call quality issues"
        Add-Report "Microsoft bypass : NOT FOUND"
    }
}

Write-Section "WinHTTP System Proxy"
$winhttpOutput = netsh winhttp show proxy 2>&1
$winhttpOutput | ForEach-Object { Write-Info $_; Add-Report "WinHTTP: $_" }

# ════════════════════════════════════════════════════════════
#  MODULE 5 — TCP CONNECTIVITY
# ════════════════════════════════════════════════════════════
Write-Header "Module 5 — TCP Connectivity (Port 443)"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 5 : TCP CONNECTIVITY (Port 443)"
Add-Report "----------------------------------------------------------------"

$tcpEndpoints = @(
    @{ Host="teams.microsoft.com";                        Port=443; Label="Core Teams"        },
    @{ Host="login.microsoftonline.com";                  Port=443; Label="Authentication"     },
    @{ Host="aadcdn.msftauth.net";                        Port=443; Label="AAD Auth CDN"       },
    @{ Host="outlook.office365.com";                      Port=443; Label="Outlook/Calendar"   },
    @{ Host="statics.teams.cdn.office.net";               Port=443; Label="Static Assets"      },
    @{ Host="worldaz.tr.teams.microsoft.com";             Port=443; Label="Media Transport"    },
    @{ Host="api.interfaces.records.teams.microsoft.com"; Port=443; Label="Teams API"          },
    @{ Host="accounts.accesscontrol.windows.net";         Port=443; Label="Access Control"     },
    @{ Host="substrate.office.com";                       Port=443; Label="Substrate/Search"   },
    @{ Host="teams.events.data.microsoft.com";            Port=443; Label="Telemetry"          }
)

foreach ($ep in $tcpEndpoints) {
    try {
        $tcp  = New-Object System.Net.Sockets.TcpClient
        $conn = $tcp.BeginConnect($ep.Host, $ep.Port, $null, $null)
        $ok   = $conn.AsyncWaitHandle.WaitOne(3000)
        if ($ok) {
            $tcp.EndConnect($conn)
            Write-OK  "$($ep.Label.PadRight(20))  $($ep.Host):$($ep.Port)"
            Add-Report "TCP OK      [$($ep.Label)] $($ep.Host):$($ep.Port)"
        } else {
            Write-Warn "TIMEOUT  $($ep.Label.PadRight(20))  $($ep.Host):$($ep.Port)"
            Add-Report "TCP TIMEOUT [$($ep.Label)] $($ep.Host):$($ep.Port)"
            Add-Warning "TCP timeout: $($ep.Host):$($ep.Port) [$($ep.Label)]"
        }
        $tcp.Close()
    } catch {
        Write-Fail "FAILED   $($ep.Label.PadRight(20))  $($ep.Host):$($ep.Port)"
        Add-Report "TCP FAIL    [$($ep.Label)] $($ep.Host):$($ep.Port)"
        Add-Failure "TCP unreachable: $($ep.Host):$($ep.Port) [$($ep.Label)]"
    }
}

# ════════════════════════════════════════════════════════════
#  MODULE 6 — UDP MEDIA PORTS
# ════════════════════════════════════════════════════════════
Write-Header "Module 6 — UDP Media Ports (Teams Calling & Meetings)"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 6 : UDP MEDIA PORTS"
Add-Report "----------------------------------------------------------------"
Write-Info "Teams prefers UDP 3478-3481 for audio/video. Blocked UDP forces TCP fallback."

$udpTargets = @(
    @{ Host="13.107.64.21"; Port=3478 }, @{ Host="13.107.64.21"; Port=3479 },
    @{ Host="13.107.64.21"; Port=3480 }, @{ Host="13.107.64.21"; Port=3481 },
    @{ Host="52.112.0.8";   Port=3478 }, @{ Host="52.112.0.8";   Port=3479 }
)

foreach ($ep in $udpTargets) {
    try {
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.Connect($ep.Host, $ep.Port)
        $udp.Client.SendTimeout    = 1500
        $udp.Client.ReceiveTimeout = 1500
        $udp.Send([byte[]](0x00), 1) | Out-Null
        $udp.Close()
        Write-OK  "UDP $($ep.Host):$($ep.Port) — Reachable"
        Add-Report "UDP OK   : $($ep.Host):$($ep.Port)"
    } catch [System.Net.Sockets.SocketException] {
        $code = $_.Exception.SocketErrorCode
        if ($code -in 'ConnectionReset','TimedOut') {
            Write-OK  "UDP $($ep.Host):$($ep.Port) — Reachable (no response expected)"
            Add-Report "UDP OK   : $($ep.Host):$($ep.Port) (no ICMP block)"
        } else {
            Write-Warn "UDP $($ep.Host):$($ep.Port) — $code"
            Add-Report "UDP WARN : $($ep.Host):$($ep.Port) — $code"
            Add-Warning "UDP port may be blocked: $($ep.Host):$($ep.Port)"
        }
    } catch {
        Write-Fail "UDP $($ep.Host):$($ep.Port) — BLOCKED or unreachable"
        Add-Report "UDP FAIL : $($ep.Host):$($ep.Port) — $($_.Exception.Message)"
        Add-Failure "UDP blocked: $($ep.Host):$($ep.Port) — forces TCP fallback, degrades call quality"
    }
}

# ════════════════════════════════════════════════════════════
#  MODULE 7 — TLS / SSL INSPECTION
# ════════════════════════════════════════════════════════════
Write-Header "Module 7 — TLS / SSL Certificate Inspection"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 7 : TLS / SSL INSPECTION"
Add-Report "----------------------------------------------------------------"
Write-Info "Checking if SSL inspection is intercepting Teams traffic..."

$tlsTargets = @(
    "https://login.microsoftonline.com",
    "https://teams.microsoft.com",
    "https://aadcdn.msftauth.net"
)

foreach ($url in $tlsTargets) {
    try {
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Timeout          = 6000
        $req.AllowAutoRedirect = $true
        $resp   = $req.GetResponse()
        $cert   = $req.ServicePoint.Certificate
        $issuer = $cert.Issuer
        $expiry = [datetime]::Parse($cert.GetExpirationDateString())

        Write-Info "URL     : $url"
        Write-Info "Subject : $($cert.Subject)"
        Write-Info "Issuer  : $issuer"
        Write-Info "Expires : $($expiry.ToString('dd-MMM-yyyy'))"
        Add-Report "TLS : $url | Issuer: $issuer | Expires: $($expiry.ToString('dd-MMM-yyyy'))"

        if ($issuer -notmatch "Microsoft|DigiCert|Baltimore") {
            Write-Warn "SSL INSPECTION DETECTED — Issuer: $issuer"
            Add-Warning "SSL inspection active for $url — Issuer: $issuer. Can break Teams auth and media."
            Add-Report "  !! SSL INSPECTION DETECTED"
        } else {
            Write-OK "Legitimate issuer: $issuer"
            Add-Report "  Cert issuer : LEGITIMATE"
        }
        $resp.Close()
    } catch {
        Write-Fail "TLS check failed: $url — $($_.Exception.Message)"
        Add-Report "TLS FAIL : $url — $($_.Exception.Message)"
        Add-Failure "TLS connection failed: $url"
    }
}

# ════════════════════════════════════════════════════════════
#  MODULE 8 — HOSTS FILE
# ════════════════════════════════════════════════════════════
Write-Header "Module 8 — Hosts File Inspection"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 8 : HOSTS FILE"
Add-Report "----------------------------------------------------------------"

try {
    $hostsContent = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction Stop
    $teamsEntries = $hostsContent | Where-Object { $_ -notmatch '^#' -and $_ -match 'teams|microsoft|office|microsoftonline|aadcdn' }

    if ($teamsEntries) {
        Write-Warn "Teams-related overrides found in hosts file:"
        $teamsEntries | ForEach-Object {
            Write-Fail "  $_"
            Add-Report "HOSTS OVERRIDE: $_"
            Add-Warning "Hosts file override: $_ — may redirect Teams traffic"
        }
    } else {
        Write-OK "Hosts file clean — no Teams-related overrides"
        Add-Report "Hosts file : CLEAN"
    }
} catch {
    Write-Warn "Could not read hosts file — $($_.Exception.Message)"
    Add-Report "Hosts file : Read error"
}

# ════════════════════════════════════════════════════════════
#  MODULE 9 — NETWORK ROUTING
# ════════════════════════════════════════════════════════════
Write-Header "Module 9 — Network Routing"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 9 : NETWORK ROUTING"
Add-Report "----------------------------------------------------------------"

foreach ($ip in @("52.112.0.0", "13.107.64.0", "52.120.0.0")) {
    try {
        $route = Find-NetRoute -RemoteIPAddress $ip -ErrorAction Stop | Select-Object -First 1
        Write-Info "Route to $ip → via $($route.NextHop) on $($route.InterfaceAlias)"
        Add-Report "Route $ip : via $($route.NextHop) on $($route.InterfaceAlias)"
        if ($route.InterfaceAlias -match "VPN|Tunnel|Cisco|Pulse|Zscaler") {
            Write-Warn "Microsoft traffic via VPN ($($route.InterfaceAlias)) — consider split tunnelling"
            Add-Warning "Microsoft IP $ip routing via VPN — consider split tunnelling"
        }
    } catch {
        Write-Warn "Could not determine route for $ip"
        Add-Report "Route $ip : Unable to determine"
    }
}

# ════════════════════════════════════════════════════════════
#  MODULE 10 — DNS CACHE SNAPSHOT
# ════════════════════════════════════════════════════════════
Write-Header "Module 10 — DNS Cache Snapshot"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 10 : DNS CACHE (Teams-related entries)"
Add-Report "----------------------------------------------------------------"

try {
    $dnsCache = Get-DnsClientCache -ErrorAction Stop |
        Where-Object { $_.Entry -match "teams|microsoft|office|microsoftonline|aadcdn|cdn" }

    if ($dnsCache) {
        Write-Info "Teams-related DNS cache entries ($($dnsCache.Count) found):"
        foreach ($entry in $dnsCache) {
            Write-Info "  $($entry.Entry.PadRight(55)) TTL: $($entry.TimeToLive)s  → $($entry.Data)"
            Add-Report "DNS Cache : $($entry.Entry) | TTL: $($entry.TimeToLive)s | Data: $($entry.Data)"
        }
    } else {
        Write-Info "No Teams-related entries in DNS cache"
        Add-Report "DNS Cache : No Teams-related entries found"
    }
} catch {
    Write-Warn "Could not read DNS cache — $($_.Exception.Message)"
    Add-Report "DNS Cache : Read error"
}

# ════════════════════════════════════════════════════════════
#  MODULE 11 — DNS CACHE CLEAR
# ════════════════════════════════════════════════════════════
Write-Header "Module 11 — Clear DNS Cache"
Write-Info "Clearing the DNS cache can resolve stale/incorrect Teams DNS entries."

Add-Type -AssemblyName System.Windows.Forms
$clearResult = [System.Windows.Forms.MessageBox]::Show(
    "Do you want to clear the DNS cache now?`n`nThis resolves stale DNS entries that can cause Teams connection issues.",
    "Teams Assurance Platform — Clear DNS Cache",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 11 : DNS CACHE CLEAR"
Add-Report "----------------------------------------------------------------"

if ($clearResult -eq [System.Windows.Forms.DialogResult]::Yes) {
    try {
        Clear-DnsClientCache -ErrorAction Stop
        Write-OK "DNS cache cleared successfully."
        Add-Report "DNS Cache Clear : SUCCESS"
    } catch {
        Write-Warn "Insufficient privileges to clear DNS cache. Attempting elevated clear..."
        Add-Report "DNS Cache Clear : Retrying with elevation..."
        try {
            Start-Process -FilePath 'powershell.exe' `
                -ArgumentList '-NoProfile -Command "Clear-DnsClientCache"' `
                -Verb RunAs -Wait -ErrorAction Stop
            Write-OK "DNS cache cleared via elevated prompt."
            Add-Report "DNS Cache Clear : SUCCESS (elevated)"
        } catch {
            Write-Fail "DNS cache clear failed — user declined elevation or insufficient rights."
            Add-Report "DNS Cache Clear : FAILED — $($_.Exception.Message)"
            Add-Warning "DNS cache not cleared — run 'ipconfig /flushdns' from an elevated prompt"
        }
    }
} else {
    Write-Info "DNS cache clear skipped by user."
    Add-Report "DNS Cache Clear : Skipped by user"
}

# ════════════════════════════════════════════════════════════
#  SUMMARY
# ════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║              DIAGNOSTIC SUMMARY              ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

Add-Report ""
Add-Report "================================================================"
Add-Report " SUMMARY"
Add-Report "================================================================"

if ($Failures.Count -eq 0 -and $Warnings.Count -eq 0) {
    Write-OK "All checks passed — no issues detected."
    Add-Report "Result : ALL CHECKS PASSED"
} else {
    if ($Failures.Count -gt 0) {
        Write-Host ""
        Write-Host "  FAILURES ($($Failures.Count)):" -ForegroundColor Red
        $Failures | ForEach-Object { Write-Fail $_; Add-Report "FAILURE : $_" }
    }
    if ($Warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "  WARNINGS ($($Warnings.Count)):" -ForegroundColor Yellow
        $Warnings | ForEach-Object { Write-Warn $_; Add-Report "WARNING : $_" }
    }
}

# ── Save report ─────────────────────────────────────────────
$reportFile = "$env:USERPROFILE\Desktop\TeamsAssurance_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$Report | Out-File -FilePath $reportFile -Encoding UTF8 -ErrorAction SilentlyContinue

Write-Host ""
if (Test-Path $reportFile) {
    Write-OK "Report saved to: $reportFile"
    $open = [System.Windows.Forms.MessageBox]::Show(
        "Diagnostic complete.`n`nReport saved to:`n$reportFile`n`nOpen it now?",
        "Teams Assurance Platform",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($open -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-Process notepad.exe -ArgumentList $reportFile
    }
} else {
    Write-Warn "Could not save report to Desktop."
}

Write-Host ""
Read-Host "  Press Enter to close"
