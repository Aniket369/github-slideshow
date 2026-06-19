<#
.SYNOPSIS
    Pulls the official, live list of Microsoft Teams / Skype for Business
    Online required & optional network endpoints from Microsoft's Office 365
    IP & URL web service, then tests DNS resolution and TCP 443 reachability
    for every concrete (non-wildcard) FQDN in that list.
    Read-only — no admin required.

.NOTES
    Source of truth: https://learn.microsoft.com/en-us/microsoft-365/enterprise/microsoft-365-ip-web-service
    This avoids guessing internal-looking hostnames (e.g. presence.teams.microsoft.com) —
    only FQDNs Microsoft itself currently publishes for the "Skype" service area
    (Skype for Business Online & Microsoft Teams) are tested.
#>

$Host.UI.RawUI.WindowTitle = "Teams Endpoint Connectivity Check"
Clear-Host
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Write-Header { param($t) Write-Host "`n  ── $t " -ForegroundColor Cyan }
function Write-OK     { param($m) Write-Host "  ✔  $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "  ⚠  $m" -ForegroundColor Yellow }
function Write-Fail   { param($m) Write-Host "  ✘  $m" -ForegroundColor Red }
function Write-Info   { param($m) Write-Host "  ℹ  $m" -ForegroundColor White }

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   TEAMS SERVICE ENDPOINT CONNECTIVITY CHECK    ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

# ── 1. Pull the live, official endpoint list from Microsoft ─────
Write-Header "Fetching official Teams endpoint list from Microsoft"

$clientRequestId = [guid]::NewGuid().ToString()
$apiUrl = "https://endpoints.office.com/endpoints/Worldwide?ServiceAreas=Skype&ClientRequestId=$clientRequestId&Format=JSON"

$endpointSets = $null
try {
    $endpointSets = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
    Write-OK "Retrieved $($endpointSets.Count) endpoint set(s) from Microsoft's official Office 365 IP & URL web service."
} catch {
    Write-Fail "Could not reach Microsoft's endpoint web service: $($_.Exception.Message)"
    Write-Warn "This host may have endpoints.office.com blocked by proxy/Zscaler — check the bypass list."
    Write-Host ""
    Read-Host "  Press Enter to close"
    exit 1
}

# ── 2. Flatten to a unique URL list, separating wildcards ───────
$urlEntries = @()
foreach ($set in $endpointSets) {
    if (-not $set.urls) { continue }
    foreach ($url in $set.urls) {
        $urlEntries += [pscustomobject]@{
            Url        = $url
            Category   = $set.category
            Required   = [bool]$set.required
            AreaName   = $set.serviceAreaDisplayName
            IsWildcard = $url.StartsWith('*.')
        }
    }
}

$urlEntries = $urlEntries | Sort-Object Url -Unique
Write-Info "Total unique Teams-related URLs in official list : $($urlEntries.Count)"

$concrete  = $urlEntries | Where-Object { -not $_.IsWildcard }
$wildcards = $urlEntries | Where-Object { $_.IsWildcard }

Write-Info "Concrete FQDNs (will be tested)                  : $($concrete.Count)"
Write-Info "Wildcard domains (cannot be tested directly)     : $($wildcards.Count)"

# ── 3. Test DNS + TCP 443 for every concrete FQDN ────────────────
Write-Header "Testing DNS resolution + TCP 443 reachability"

$results = [System.Collections.Generic.List[psobject]]::new()

foreach ($entry in $concrete) {
    $fqdn   = $entry.Url
    $dnsOk  = $false
    $tcpOk  = $false

    try {
        Resolve-DnsName -Name $fqdn -Type A -ErrorAction Stop | Out-Null
        $dnsOk = $true
    } catch { }

    if ($dnsOk) {
        try {
            $tcp  = New-Object System.Net.Sockets.TcpClient
            $conn = $tcp.BeginConnect($fqdn, 443, $null, $null)
            $tcpOk = $conn.AsyncWaitHandle.WaitOne(2000)
            if ($tcpOk) { $tcp.EndConnect($conn) }
            $tcp.Close()
        } catch {
            $tcpOk = $false
        }
    }

    $status = if ($dnsOk -and $tcpOk) { "OK" } elseif ($dnsOk) { "TCP-FAIL" } else { "DNS-FAIL" }

    $results.Add([pscustomobject]@{
        Url      = $fqdn
        Required = $entry.Required
        Category = $entry.Category
        Area     = $entry.AreaName
        Status   = $status
    })

    $tag = "[$($entry.Category)$(if ($entry.Required) { '/Required' })]"
    switch ($status) {
        "OK"       { Write-OK   "$($fqdn.PadRight(45)) $tag" }
        "TCP-FAIL" { Write-Warn "$($fqdn.PadRight(45)) DNS OK, TCP 443 unreachable $tag" }
        "DNS-FAIL" { Write-Fail "$($fqdn.PadRight(45)) DNS resolution FAILED $tag" }
    }
}

# ── 4. Wildcard domains — informational only ──────────────────────
Write-Header "Wildcard Domains (cannot be tested directly)"
foreach ($w in $wildcards) {
    Write-Info "$($w.Url.PadRight(35)) — covers all subdomains under this pattern [$($w.Category)$(if ($w.Required) { '/Required' })]"
}

# ── 5. Summary ─────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                   SUMMARY                      ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

$okCount      = ($results | Where-Object { $_.Status -eq "OK" }).Count
$tcpFailCount = ($results | Where-Object { $_.Status -eq "TCP-FAIL" }).Count
$dnsFailCount = ($results | Where-Object { $_.Status -eq "DNS-FAIL" }).Count
$reqFail      = $results | Where-Object { $_.Required -and $_.Status -ne "OK" }

Write-Info "Reachable       : $okCount"
Write-Warn "TCP unreachable : $tcpFailCount"
Write-Fail "DNS failed      : $dnsFailCount"

if ($reqFail.Count -gt 0) {
    Write-Host ""
    Write-Fail "$($reqFail.Count) REQUIRED endpoint(s) failed — these can break core Teams functionality:"
    $reqFail | ForEach-Object { Write-Fail "  $($_.Url) [$($_.Status)] — $($_.Area)" }
} else {
    Write-OK "All REQUIRED endpoints are reachable."
}

# ── Save report ──────────────────────────────────────────────
$reportFile = "$env:USERPROFILE\Desktop\TeamsEndpointCheck_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $reportFile -NoTypeInformation -ErrorAction SilentlyContinue
if (Test-Path $reportFile) {
    Write-Host ""
    Write-OK "Full results saved to: $reportFile"
}

Write-Host ""
Read-Host "  Press Enter to close"
