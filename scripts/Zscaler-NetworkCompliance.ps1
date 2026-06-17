# ================================================================
#  Zscaler-NetworkCompliance.ps1
#  Full network health check + Zscaler enabled/AD group compliance
#  Read-Only — No admin required
# ================================================================

$Host.UI.RawUI.WindowTitle = "Zscaler Network & Compliance Check"
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
Write-Host "  ║     ZSCALER NETWORK & COMPLIANCE CHECK         ║" -ForegroundColor Cyan
Write-Host "  ║     Read-Only  •  No Admin Required            ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

$scanDate = Get-Date -Format 'dd-MMM-yyyy HH:mm:ss'
Write-Info "Scan started : $scanDate"
Write-Info "Computer     : $env:COMPUTERNAME"
Write-Info "User         : $env:USERDOMAIN\$env:USERNAME"

Add-Report "================================================================"
Add-Report " ZSCALER NETWORK & COMPLIANCE REPORT"
Add-Report "================================================================"
Add-Report "Scan Date : $scanDate"
Add-Report "Computer  : $env:COMPUTERNAME"
Add-Report "User      : $env:USERDOMAIN\$env:USERNAME"
Add-Report ""

# ════════════════════════════════════════════════════════════
#  MODULE 1 — ZSCALER INSTALL / ENABLED STATUS
# ════════════════════════════════════════════════════════════
Write-Header "Module 1 — Zscaler Install & Enabled Status"
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 1 : ZSCALER INSTALL & ENABLED STATUS"
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
            Write-Info "VPN/tunnel adapter detected: $($a.Name)"
            Add-Report "Tunnel adapter detected: $($a.Name) — $($a.InterfaceDescription)"
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
    "www.google.com",
    "www.microsoft.com",
    "login.microsoftonline.com",
    "www.cisco.com"
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
$proxyServer  = if ($proxy.ProxyServer)   { $proxy.ProxyServer   } else { 'Not configured' }
$proxyBypass  = if ($proxy.ProxyOverride) { $proxy.ProxyOverride } else { 'None' }
$proxyPAC     = if ($proxy.AutoConfigURL) { $proxy.AutoConfigURL } else { 'Not configured' }

Write-Info "Proxy Enabled  : $(if ($proxyEnabled -eq 1) { 'YES' } else { 'NO' })"
Write-Info "Proxy Server   : $proxyServer"
Write-Info "PAC / Auto URL : $proxyPAC"

Add-Report "Proxy Enabled  : $(if ($proxyEnabled -eq 1) { 'YES' } else { 'NO' })"
Add-Report "Proxy Server   : $proxyServer"
Add-Report "Proxy Bypass   : $proxyBypass"
Add-Report "PAC URL        : $proxyPAC"

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
    @{ Host="www.google.com";              Port=443; Label="General Internet" },
    @{ Host="www.microsoft.com";           Port=443; Label="Microsoft"        },
    @{ Host="login.microsoftonline.com";   Port=443; Label="Authentication"   },
    @{ Host="www.cisco.com";               Port=443; Label="Cisco"            }
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
#  MODULE 6 — NETWORK ROUTING
# ════════════════════════════════════════════════════════════
Write-Header "Module 6 — Network Routing"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 6 : NETWORK ROUTING"
Add-Report "----------------------------------------------------------------"

foreach ($ip in @("8.8.8.8", "1.1.1.1")) {
    try {
        $route = Find-NetRoute -RemoteIPAddress $ip -ErrorAction Stop | Select-Object -First 1
        Write-Info "Route to $ip → via $($route.NextHop) on $($route.InterfaceAlias)"
        Add-Report "Route $ip : via $($route.NextHop) on $($route.InterfaceAlias)"
    } catch {
        Write-Warn "Could not determine route for $ip"
        Add-Report "Route $ip : Unable to determine"
    }
}

# ════════════════════════════════════════════════════════════
#  MODULE 7 — HOSTS FILE
# ════════════════════════════════════════════════════════════
Write-Header "Module 7 — Hosts File Inspection"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 7 : HOSTS FILE"
Add-Report "----------------------------------------------------------------"

try {
    $hostsContent = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction Stop
    $overrides = $hostsContent | Where-Object { $_ -notmatch '^#' -and $_ -match 'zscaler|microsoft|cisco' }

    if ($overrides) {
        Write-Warn "Relevant overrides found in hosts file:"
        $overrides | ForEach-Object {
            Write-Fail "  $_"
            Add-Report "HOSTS OVERRIDE: $_"
            Add-Warning "Hosts file override: $_"
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
#  MODULE 8 — DNS CACHE SNAPSHOT
# ════════════════════════════════════════════════════════════
Write-Header "Module 8 — DNS Cache Snapshot"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 8 : DNS CACHE"
Add-Report "----------------------------------------------------------------"

try {
    $dnsCache = Get-DnsClientCache -ErrorAction Stop | Where-Object { $_.Entry -match "zscaler|microsoft|cisco" }
    if ($dnsCache) {
        foreach ($entry in $dnsCache) {
            Write-Info "  $($entry.Entry.PadRight(45)) TTL: $($entry.TimeToLive)s  → $($entry.Data)"
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
#  MODULE 9 — AD GROUP COMPLIANCE (only if Zscaler is enabled)
# ════════════════════════════════════════════════════════════
Write-Header "Module 9 — Zscaler AD Group Compliance"
Add-Report ""
Add-Report "----------------------------------------------------------------"
Add-Report " MODULE 9 : ZSCALER AD GROUP COMPLIANCE"
Add-Report "----------------------------------------------------------------"

$requiredGroups = @(
    'GLO-CLI-SEC-AZAD-MDE-FW-ZSCALER',
    'GLO-CLI-SEC-FAT-iwZscalerCLIENT4301-EN'
)

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
            Add-Failure "Device not a member of required Zscaler AD group(s): $($missing -join ', ')"

            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show(
                "This device is not a member of the required Zscaler AD group(s):`n`n$($missing -join "`n")`n`nZscaler may not function correctly on this device.`nPlease use Cisco AnyConnect VPN instead.",
                "Zscaler AD Group Compliance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    }
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
$reportFile = "$env:USERPROFILE\Desktop\ZscalerCompliance_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$Report | Out-File -FilePath $reportFile -Encoding UTF8 -ErrorAction SilentlyContinue

Write-Host ""
if (Test-Path $reportFile) {
    Write-OK "Report saved to: $reportFile"
}

Write-Host ""
Read-Host "  Press Enter to close"
