# ================================================================
#  ZscalerAndNetworkTeams.ps1
#  Combined Teams + Zscaler network health & compliance check
#  (merges TeamsAssurancePlatform.ps1 + Zscaler-NetworkCompliance.ps1)
#  Read-Only — No admin required (DNS cache clear may prompt for elevation)
#  Shows a live progress bar with elapsed time / ETA while running.
#  All results are buffered and printed together once the scan finishes.
# ================================================================

$Host.UI.RawUI.WindowTitle = "Zscaler & Teams Network Compliance Check"
Clear-Host
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ── Helpers — buffer console lines instead of printing immediately ──
$ConsoleBuffer = [System.Collections.Generic.List[psobject]]::new()

# ── Live progress bar (elapsed time + ETA) ───────────────────
$ScriptStartTime = Get-Date
$ModuleCounter   = 0
$TotalModules    = 14

function Buffer-Line { param($t, $c = 'White') $ConsoleBuffer.Add([pscustomobject]@{ Text = $t; Color = $c }) }

function Write-Header {
    param($t)
    $script:ModuleCounter++
    $elapsed      = (Get-Date) - $ScriptStartTime
    $avgPerModule = if ($ModuleCounter -gt 1) { $elapsed.TotalSeconds / ($ModuleCounter - 1) } else { 4 }
    $etaSeconds   = [math]::Round([math]::Max(0, ($TotalModules - $ModuleCounter) * $avgPerModule))
    $percent      = [math]::Min(100, [math]::Round(($ModuleCounter / $TotalModules) * 100))

    Write-Progress -Activity "Zscaler & Teams Network Compliance Check — Running..." `
        -Status "[$ModuleCounter/$TotalModules] $t   |   Elapsed: $($elapsed.ToString('mm\:ss'))" `
        -PercentComplete $percent `
        -SecondsRemaining $etaSeconds

    Buffer-Line "`n  ┌─────────────────────────────────────────────┐`n  │  $t`n  └─────────────────────────────────────────────┘" 'Cyan'
}

function Write-Section { param($t) Buffer-Line "`n  ── $t " 'DarkCyan' }
function Write-OK      { param($m) Buffer-Line "     ✔  $m" 'Green' }
function Write-Warn    { param($m) Buffer-Line "     ⚠  $m" 'Yellow' }
function Write-Fail    { param($m) Buffer-Line "     ✘  $m" 'Red' }
function Write-Info    { param($m) Buffer-Line "     ℹ  $m" 'White' }
function Flush-Console { foreach ($line in $ConsoleBuffer) { Write-Host $line.Text -ForegroundColor $line.Color } }

$Report   = [System.Collections.Generic.List[string]]::new()
$Warnings = [System.Collections.Generic.List[string]]::new()
$Failures = [System.Collections.Generic.List[string]]::new()

function Add-Report  { param($m) $Report.Add($m)   }
function Add-Warning { param($m) $Warnings.Add($m) }
function Add-Failure { param($m) $Failures.Add($m) }

# ── Banner ──────────────────────────────────────────────────
Buffer-Line "  ╔═══════════════════════════════════════════════╗" 'Cyan'
Buffer-Line "  ║   ZSCALER & TEAMS NETWORK COMPLIANCE CHECK     ║" 'Cyan'
Buffer-Line "  ║   Read-Only  •  No Admin Required              ║" 'Cyan'
Buffer-Line "  ╚═══════════════════════════════════════════════╝" 'Cyan'

$scanDate  = Get-Date -Format 'dd-MMM-yyyy HH:mm:ss'
$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption

Write-Info "Scan started : $scanDate"
Write-Info "Computer     : $env:COMPUTERNAME"
Write-Info "User         : $env:USERDOMAIN\$env:USERNAME"
Write-Info "OS           : $osCaption"

Add-Report "================================================================"
Add-Report " ZSCALER & TEAMS NETWORK COMPLIANCE REPORT"
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

# ════════════════════════════════════════════════════════════
#  MODULE 2 — ZSCALER INSTALL / ENABLED STATUS
# ════════════════════════════════════════════════════════════
Write-Header "Module 2 — Zscaler Install & Enabled Status"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 2 : ZSCALER INSTALL & ENABLED STATUS"
Add-Report "----------------------------------------------------------------"

$zsService = Get-Service -Name 'ZSAService' -ErrorAction SilentlyContinue
$zsInstallDir = Get-Item "$env:ProgramFiles\Zscaler", "${env:ProgramFiles(x86)}\Zscaler" -ErrorAction SilentlyContinue | Select-Object -First 1

$zscalerInstalled = [bool]($zsService -or $zsInstallDir)

if (-not $zscalerInstalled) {
    Write-Fail "Zscaler is NOT installed on this machine."
    Add-Report "Zscaler Installed : NO"
    Add-Failure "Zscaler Client Connector not installed"
} else {
    Write-OK "Zscaler is installed."
    Add-Report "Zscaler Installed : YES"
}

$zscalerEnabled = $false
$trayManager = $null

if ($zscalerInstalled) {
    Write-Info "Service Status: $(if ($zsService) { $zsService.Status } else { 'Service not found' })"
    Add-Report "ZSAService Status : $(if ($zsService) { $zsService.Status } else { 'Not found' })"

    $trayManager = Get-ChildItem "$env:ProgramFiles\Zscaler", "${env:ProgramFiles(x86)}\Zscaler" -Filter 'ZSATrayManager.exe' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName

    if ($trayManager) {
        $statusOutput = & $trayManager '/status' 2>$null | Out-String

        if ($statusOutput -match 'Enabled' -or $statusOutput -match 'Logged In' -or ($zsService -and $zsService.Status -eq 'Running')) {
            $zscalerEnabled = $true
        }
    } elseif ($zsService -and $zsService.Status -eq 'Running') {
        $zscalerEnabled = $true
    }

    if ($zscalerEnabled) {
        Write-OK "Zscaler is ENABLED / active on this machine."
        Add-Report "Zscaler Enabled : YES"
    } else {
        Write-Warn "Zscaler is installed but NOT currently enabled/active."
        Add-Report "Zscaler Enabled : NO"
        Add-Warning "Zscaler is installed but not currently enabled/active"
    }
}

# ════════════════════════════════════════════════════════════
#  MODULE 3 — NETWORK ADAPTERS
# ════════════════════════════════════════════════════════════
Write-Header "Module 3 — Network Adapters"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 3 : NETWORK ADAPTERS"
Add-Report "----------------------------------------------------------------"

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
if ($adapters) {
    foreach ($a in $adapters) {
        $ip = (Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        Write-OK  "$($a.Name) — $($a.InterfaceDescription)"
        Write-Info "  IP: $ip  |  Speed: $($a.LinkSpeed)  |  MAC: $($a.MacAddress)"
        Add-Report "Adapter : $($a.Name) | IP: $ip | Speed: $($a.LinkSpeed) | MAC: $($a.MacAddress)"

        if ($a.InterfaceDescription -match "VPN|Cisco|Pulse|GlobalProtect|FortiClient|Zscaler|SonicWall") {
            Write-Warn "VPN/tunnel adapter detected: $($a.Name) — may affect Teams media routing"
            Add-Warning "VPN/tunnel adapter active: $($a.Name) — $($a.InterfaceDescription)"
        }
    }
} else {
    Write-Fail "No active network adapters found"
    Add-Failure "No active network adapters"
}

# ════════════════════════════════════════════════════════════
#  MODULE 4 — VPN CLIENT DETECTION
# ════════════════════════════════════════════════════════════
Write-Header "Module 4 — VPN Client Detection"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 4 : VPN CLIENT DETECTION"
Add-Report "----------------------------------------------------------------"

$vpnClients = @(
    @{ Name = 'Cisco AnyConnect / Secure Client'; Processes = @('vpnui','vpnagent','acwebhelper'); Services = @('vpnagent'); Paths = @("$env:ProgramFiles\Cisco\Cisco AnyConnect Secure Mobility Client", "${env:ProgramFiles(x86)}\Cisco\Cisco AnyConnect Secure Mobility Client", "$env:ProgramFiles\Cisco\Cisco Secure Client", "${env:ProgramFiles(x86)}\Cisco\Cisco Secure Client") },
    @{ Name = 'Zscaler Client Connector';          Processes = @('ZSATray','ZSATrayManager','ZSAUpm');           Services = @('ZSAService');  Paths = @("$env:ProgramFiles\Zscaler", "${env:ProgramFiles(x86)}\Zscaler") },
    @{ Name = 'Palo Alto GlobalProtect';            Processes = @('PanGPA','PanGPS');                            Services = @('PanGPS');      Paths = @("$env:ProgramFiles\Palo Alto Networks\GlobalProtect", "${env:ProgramFiles(x86)}\Palo Alto Networks\GlobalProtect") },
    @{ Name = 'Pulse Secure / Ivanti Secure Access'; Processes = @('Pulse','dsAccessService');                   Services = @('DSAccessService'); Paths = @("${env:ProgramFiles(x86)}\Common Files\Pulse Secure", "$env:ProgramFiles\Common Files\Pulse Secure") },
    @{ Name = 'FortiClient';                        Processes = @('FortiClient','FCAppDB');                     Services = @('FAService');   Paths = @("$env:ProgramFiles\Fortinet\FortiClient", "${env:ProgramFiles(x86)}\Fortinet\FortiClient") },
    @{ Name = 'SonicWall NetExtender';              Processes = @('NeService','NEGui');                         Services = @('NeService');   Paths = @("${env:ProgramFiles(x86)}\SonicWALL\SSL-VPN\NetExtender", "$env:ProgramFiles\SonicWALL\SSL-VPN\NetExtender") },
    @{ Name = 'OpenVPN';                            Processes = @('openvpn','openvpn-gui');                     Services = @('OpenVPNService'); Paths = @("$env:ProgramFiles\OpenVPN", "${env:ProgramFiles(x86)}\OpenVPN") },
    @{ Name = 'WireGuard';                          Processes = @('wireguard');                                 Services = @('WireGuardManager'); Paths = @("$env:ProgramFiles\WireGuard") }
)

$installedVpns = @()
$activeVpns    = @()

foreach ($vpn in $vpnClients) {
    $pathFound    = $vpn.Paths     | Where-Object { Test-Path $_ } | Select-Object -First 1
    $serviceFound = $vpn.Services  | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    $procFound    = $vpn.Processes | ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue } | Select-Object -First 1

    $isInstalled = [bool]($pathFound -or $serviceFound)
    $isActive    = [bool]($procFound -or ($serviceFound -and $serviceFound.Status -eq 'Running'))

    if ($isInstalled) { $installedVpns += $vpn.Name }
    if ($isActive)    { $activeVpns    += $vpn.Name }
}

$usingCisco = $activeVpns -contains 'Cisco AnyConnect / Secure Client'

if ($installedVpns.Count -eq 0) {
    Write-Info "No known VPN client software detected on this machine."
    Add-Report "VPN Clients Installed : None detected"
} else {
    Write-Info "VPN client(s) installed: $($installedVpns -join ', ')"
    Add-Report "VPN Clients Installed : $($installedVpns -join ', ')"
}

if ($activeVpns.Count -eq 0) {
    Write-Warn "No VPN client currently appears to be active/connected."
    Add-Report "VPN Clients Active : None"
    Add-Warning "No active VPN client detected — confirm the user is connected via a sanctioned VPN/Zscaler tunnel"
} else {
    foreach ($v in $activeVpns) {
        if ($v -eq 'Cisco AnyConnect / Secure Client') {
            Write-OK "Active VPN: Cisco AnyConnect / Secure Client"
            Add-Report "VPN Active : Cisco AnyConnect / Secure Client"
        } else {
            Write-Info "Active VPN: $v"
            Add-Report "VPN Active : $v"
        }
    }
}

if ($usingCisco) {
    Write-OK "This device IS currently using Cisco AnyConnect."
    Add-Report "Using Cisco AnyConnect : YES"
} else {
    Write-Info "This device is NOT currently using Cisco AnyConnect."
    Add-Report "Using Cisco AnyConnect : NO"
}

# ════════════════════════════════════════════════════════════
#  MODULE 5 — DNS RESOLUTION
# ════════════════════════════════════════════════════════════
Write-Header "Module 5 — DNS Resolution"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 5 : DNS RESOLUTION"
Add-Report "----------------------------------------------------------------"

$dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses } |
    Select-Object -ExpandProperty ServerAddresses -Unique
Write-Info "DNS Servers: $($dnsServers -join ', ')"
Add-Report "DNS Servers : $($dnsServers -join ', ')"

$dnsTargets = @(
    "www.google.com",
    "www.microsoft.com",
    "www.cisco.com",
    "login.microsoftonline.com",
    "teams.microsoft.com",
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
#  MODULE 6 — PROXY CONFIGURATION
# ════════════════════════════════════════════════════════════
Write-Header "Module 6 — Proxy Configuration"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 6 : PROXY CONFIGURATION"
Add-Report "----------------------------------------------------------------"

$proxy = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
$proxyEnabled = $proxy.ProxyEnable
$proxyServer  = if ($proxy.ProxyServer)   { $proxy.ProxyServer   } else { 'Not configured' }
$proxyBypass  = if ($proxy.ProxyOverride) { $proxy.ProxyOverride } else { 'None' }
$proxyPAC     = if ($proxy.AutoConfigURL) { $proxy.AutoConfigURL } else { 'Not configured' }

Write-Info "Proxy Enabled  : $(if ($proxyEnabled -eq 1) { 'YES' } else { 'NO' })"
Write-Info "Proxy Server   : $proxyServer"
Write-Info "Proxy Bypass   : $proxyBypass"
Write-Info "PAC / Auto URL : $proxyPAC"

Add-Report "Proxy Enabled  : $(if ($proxyEnabled -eq 1) { 'YES' } else { 'NO' })"
Add-Report "Proxy Server   : $proxyServer"
Add-Report "Proxy Bypass   : $proxyBypass"
Add-Report "PAC URL        : $proxyPAC"

if ($proxyEnabled -eq 1) {
    Write-Warn "Proxy is active — ensure Microsoft 365/Teams IPs are in bypass list"
    Add-Warning "Proxy enabled ($proxyServer) — Microsoft 365/Teams endpoints should be bypassed"
    if ($proxyBypass -match "microsoft|office365|teams") {
        Write-OK "Microsoft/Teams domains found in proxy bypass list"
        Add-Report "Microsoft bypass : FOUND"
    } else {
        Write-Warn "Microsoft/Teams domains NOT in proxy bypass list"
        Add-Warning "Microsoft/Teams domains missing from proxy bypass — common cause of call quality issues"
        Add-Report "Microsoft bypass : NOT FOUND"
    }
}

Write-Section "WinHTTP System Proxy"
$winhttpOutput = netsh winhttp show proxy 2>&1
$winhttpOutput | ForEach-Object { Write-Info $_; Add-Report "WinHTTP: $_" }

# ════════════════════════════════════════════════════════════
#  MODULE 7 — TCP CONNECTIVITY
# ════════════════════════════════════════════════════════════
Write-Header "Module 7 — TCP Connectivity (Port 443)"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 7 : TCP CONNECTIVITY (Port 443)"
Add-Report "----------------------------------------------------------------"

$tcpEndpoints = @(
    @{ Host="www.google.com";                            Port=443; Label="General Internet"   },
    @{ Host="www.microsoft.com";                          Port=443; Label="Microsoft"           },
    @{ Host="www.cisco.com";                              Port=443; Label="Cisco"                },
    @{ Host="login.microsoftonline.com";                  Port=443; Label="Authentication"       },
    @{ Host="teams.microsoft.com";                        Port=443; Label="Core Teams"           },
    @{ Host="aadcdn.msftauth.net";                        Port=443; Label="AAD Auth CDN"         },
    @{ Host="outlook.office365.com";                      Port=443; Label="Outlook/Calendar"     },
    @{ Host="statics.teams.cdn.office.net";               Port=443; Label="Static Assets"        },
    @{ Host="worldaz.tr.teams.microsoft.com";             Port=443; Label="Media Transport"      },
    @{ Host="api.interfaces.records.teams.microsoft.com"; Port=443; Label="Teams API"            },
    @{ Host="accounts.accesscontrol.windows.net";         Port=443; Label="Access Control"       },
    @{ Host="substrate.office.com";                       Port=443; Label="Substrate/Search"     },
    @{ Host="teams.events.data.microsoft.com";            Port=443; Label="Telemetry"            }
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
#  MODULE 8 — UDP MEDIA PORTS
# ════════════════════════════════════════════════════════════
Write-Header "Module 8 — UDP Media Ports (Teams Calling & Meetings)"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 8 : UDP MEDIA PORTS"
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
#  MODULE 9 — TLS / SSL INSPECTION
# ════════════════════════════════════════════════════════════
Write-Header "Module 9 — TLS / SSL Certificate Inspection"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 9 : TLS / SSL INSPECTION"
Add-Report "----------------------------------------------------------------"
Write-Info "Checking if SSL inspection is intercepting Teams/Zscaler traffic..."

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

        if ($issuer -notmatch "Microsoft|DigiCert|Baltimore|Zscaler") {
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
#  MODULE 10 — HOSTS FILE
# ════════════════════════════════════════════════════════════
Write-Header "Module 10 — Hosts File Inspection"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 10 : HOSTS FILE"
Add-Report "----------------------------------------------------------------"

try {
    $hostsContent = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction Stop
    $overrides = $hostsContent | Where-Object { $_ -notmatch '^#' -and $_ -match 'zscaler|cisco|teams|microsoft|office|microsoftonline|aadcdn' }

    if ($overrides) {
        Write-Warn "Relevant overrides found in hosts file:"
        $overrides | ForEach-Object {
            Write-Fail "  $_"
            Add-Report "HOSTS OVERRIDE: $_"
            Add-Warning "Hosts file override: $_ — may redirect Teams/Zscaler traffic"
        }
    } else {
        Write-OK "Hosts file clean — no relevant overrides"
        Add-Report "Hosts file : CLEAN"
    }
} catch {
    Write-Warn "Could not read hosts file — $($_.Exception.Message)"
    Add-Report "Hosts file : Read error"
}

# ════════════════════════════════════════════════════════════
#  MODULE 11 — NETWORK ROUTING
# ════════════════════════════════════════════════════════════
Write-Header "Module 11 — Network Routing"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 11 : NETWORK ROUTING"
Add-Report "----------------------------------------------------------------"

foreach ($ip in @("8.8.8.8", "1.1.1.1", "52.112.0.0", "13.107.64.0", "52.120.0.0")) {
    try {
        $route = Find-NetRoute -RemoteIPAddress $ip -ErrorAction Stop | Select-Object -First 1
        Write-Info "Route to $ip → via $($route.NextHop) on $($route.InterfaceAlias)"
        Add-Report "Route $ip : via $($route.NextHop) on $($route.InterfaceAlias)"
        if ($route.InterfaceAlias -match "VPN|Tunnel|Cisco|Pulse|Zscaler") {
            Write-Warn "Traffic to $ip routing via VPN/tunnel ($($route.InterfaceAlias)) — consider split tunnelling for Teams media"
            Add-Warning "IP $ip routing via VPN/tunnel ($($route.InterfaceAlias)) — consider split tunnelling"
        }
    } catch {
        Write-Warn "Could not determine route for $ip"
        Add-Report "Route $ip : Unable to determine"
    }
}

# ════════════════════════════════════════════════════════════
#  MODULE 12 — DNS CACHE SNAPSHOT
# ════════════════════════════════════════════════════════════
Write-Header "Module 12 — DNS Cache Snapshot"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 12 : DNS CACHE"
Add-Report "----------------------------------------------------------------"

try {
    $dnsCache = Get-DnsClientCache -ErrorAction Stop |
        Where-Object { $_.Entry -match "zscaler|cisco|teams|microsoft|office|microsoftonline|aadcdn|cdn" }

    if ($dnsCache) {
        Write-Info "Relevant DNS cache entries ($($dnsCache.Count) found):"
        foreach ($entry in $dnsCache) {
            Write-Info "  $($entry.Entry.PadRight(55)) TTL: $($entry.TimeToLive)s  → $($entry.Data)"
            Add-Report "DNS Cache : $($entry.Entry) | TTL: $($entry.TimeToLive)s | Data: $($entry.Data)"
        }
    } else {
        Write-Info "No relevant entries in DNS cache"
        Add-Report "DNS Cache : No relevant entries found"
    }
} catch {
    Write-Warn "Could not read DNS cache — $($_.Exception.Message)"
    Add-Report "DNS Cache : Read error"
}

# ════════════════════════════════════════════════════════════
#  MODULE 13 — DNS CACHE CLEAR
# ════════════════════════════════════════════════════════════
Write-Header "Module 13 — Clear DNS Cache"
Write-Info "Clearing the DNS cache can resolve stale/incorrect Teams or Zscaler DNS entries."

Add-Type -AssemblyName System.Windows.Forms
$clearResult = [System.Windows.Forms.MessageBox]::Show(
    "Do you want to clear the DNS cache now?`n`nThis resolves stale DNS entries that can cause Teams connection or Zscaler routing issues.",
    "Zscaler & Teams Network Check — Clear DNS Cache",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 13 : DNS CACHE CLEAR"
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
#  MODULE 14 — ZSCALER AD GROUP COMPLIANCE (only if Zscaler is enabled)
# ════════════════════════════════════════════════════════════
Write-Header "Module 14 — Zscaler AD Group Compliance"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 14 : ZSCALER AD GROUP COMPLIANCE"
Add-Report "----------------------------------------------------------------"

$requiredGroups = @(
    'GLO-CLI-SEC-AZAD-MDE-FW-ZSCALER',
    'GLO-CLI-SEC-FAT-iwZscalerCLIENT4301-EN'
)

$notCompliant = $false
$missing = @()

if (-not $zscalerEnabled) {
    Write-Info "Skipped — Zscaler is not enabled/active on this machine."
    Add-Report "AD Group Check : Skipped (Zscaler not enabled)"
} else {
    Write-Info "Checking computer object '$env:COMPUTERNAME' against required AD groups..."

    $computerGroups = $null
    try {
        $searcher = [adsisearcher]"(&(objectCategory=computer)(name=$env:COMPUTERNAME))"
        $searcher.PropertiesToLoad.Add('memberOf') | Out-Null
        $result = $searcher.FindOne()

        if ($result) {
            $computerGroups = $result.Properties['memberOf'] | ForEach-Object {
                ($_ -split ',')[0] -replace '^CN=', ''
            }
        }
    } catch {
        Write-Warn "AD lookup failed: $($_.Exception.Message)"
        Add-Report "AD Group Check : Lookup failed — $($_.Exception.Message)"
    }

    if ($null -eq $computerGroups) {
        Write-Warn "Could not retrieve AD group membership (machine may be off-domain or DC unreachable)."
        Add-Report "AD Group Check : Could not retrieve group membership"
        Add-Warning "Could not verify AD group membership for Zscaler compliance"
    } else {
        $missing = $requiredGroups | Where-Object { $_ -notin $computerGroups }

        foreach ($g in $requiredGroups) {
            if ($g -in $computerGroups) {
                Write-OK "Member of: $g"
                Add-Report "AD Group : $g — PRESENT"
            } else {
                Write-Fail "NOT a member of: $g"
                Add-Report "AD Group : $g — MISSING"
            }
        }

        if ($missing.Count -eq 0) {
            Write-OK "Device is compliant — member of all required Zscaler AD groups."
            Add-Report "AD Group Compliance : PASS"
        } else {
            Write-Fail "Device is NOT compliant — missing $($missing.Count) required group(s)."
            Add-Report "AD Group Compliance : FAIL — missing $($missing -join ', ')"

            if ($usingCisco) {
                Write-OK "Device is already connected via Cisco AnyConnect — acceptable fallback in use."
                Add-Report "Cisco Fallback : ALREADY IN USE"
            } else {
                Add-Failure "Device not a member of required Zscaler AD group(s): $($missing -join ', ') — not using Cisco either"
                $notCompliant = $true
            }
        }
    }
}

# ════════════════════════════════════════════════════════════
#  SUMMARY
# ════════════════════════════════════════════════════════════
Write-Progress -Activity "Zscaler & Teams Network Compliance Check — Running..." -Completed

Buffer-Line ""
Buffer-Line "  ╔═══════════════════════════════════════════════╗" 'Cyan'
Buffer-Line "  ║              DIAGNOSTIC SUMMARY              ║" 'Cyan'
Buffer-Line "  ╚═══════════════════════════════════════════════╝" 'Cyan'

$totalElapsed = (Get-Date) - $ScriptStartTime
Buffer-Line "  Total scan time: $($totalElapsed.ToString('mm\:ss'))" 'White'

Add-Report ""
Add-Report "================================================================"
Add-Report " SUMMARY"
Add-Report "================================================================"
Add-Report "Total scan time : $($totalElapsed.ToString('mm\:ss'))"

if ($Failures.Count -eq 0 -and $Warnings.Count -eq 0) {
    Write-OK "All checks passed — no issues detected."
    Add-Report "Result : ALL CHECKS PASSED"
} else {
    if ($Failures.Count -gt 0) {
        Buffer-Line ""
        Buffer-Line "  FAILURES ($($Failures.Count)):" 'Red'
        $Failures | ForEach-Object { Write-Fail $_; Add-Report "FAILURE : $_" }
    }
    if ($Warnings.Count -gt 0) {
        Buffer-Line ""
        Buffer-Line "  WARNINGS ($($Warnings.Count)):" 'Yellow'
        $Warnings | ForEach-Object { Write-Warn $_; Add-Report "WARNING : $_" }
    }
}

# ── Save report ─────────────────────────────────────────────
$reportFile = "$env:USERPROFILE\Desktop\ZscalerAndNetworkTeams_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$Report | Out-File -FilePath $reportFile -Encoding UTF8 -ErrorAction SilentlyContinue

Buffer-Line ""
if (Test-Path $reportFile) {
    Write-OK "Report saved to: $reportFile"
}

# ── Print everything that was buffered, all at once ─────────
Flush-Console

# ── Show the Cisco fallback popup last, after all output is visible ──
if ($notCompliant) {
    [System.Windows.Forms.MessageBox]::Show(
        "This device is not a member of the required Zscaler AD group(s):`n`n$($missing -join "`n")`n`nZscaler may not function correctly on this device.`nPlease use Cisco AnyConnect VPN instead.",
        "Zscaler AD Group Compliance",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

Write-Host ""
Read-Host "  Press Enter to close"
