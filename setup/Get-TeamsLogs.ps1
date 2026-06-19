# ================================================================
#  Teams Performance Diagnostics
#  Collects Teams event logs, process health, and error reports
#  from the last 48 hours. Saves to Downloads for Copilot analysis.
# ================================================================

$timestamp   = Get-Date -Format 'yyyyMMdd-HHmm'
$outputFile  = "$env:USERPROFILE\Downloads\Teams-Diagnostics-$timestamp.txt"

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "   Microsoft Teams  —  Performance Diagnostics Collector" -ForegroundColor Cyan
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host ""

# ── Section 1: System snapshot ────────────────────────────────────
Write-Host "  [1/5] Collecting system info..." -ForegroundColor Yellow
$sysInfo = @"
TEAMS PERFORMANCE DIAGNOSTICS
Generated : $(Get-Date -Format 'dd MMM yyyy HH:mm:ss')
Computer  : $env:COMPUTERNAME
User      : $env:USERNAME
OS        : $((Get-WmiObject Win32_OperatingSystem).Caption) $((Get-WmiObject Win32_OperatingSystem).Version)
RAM Total : $([math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)) GB
RAM Free  : $([math]::Round((Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)) GB

"@
Write-Host "        Done." -ForegroundColor Green

# ── Section 2: Teams process health ──────────────────────────────
Write-Host "  [2/5] Checking Teams process health..." -ForegroundColor Yellow
$teamsProcs = Get-Process -Name "MS-Teams","MSTeams","Teams" -ErrorAction SilentlyContinue
$procInfo = if ($teamsProcs) {
    $teamsProcs | ForEach-Object {
        "  Process : $($_.Name)  (PID $($_.Id))`n" +
        "  CPU     : $([math]::Round($_.CPU, 2))s total`n" +
        "  Memory  : $([math]::Round($_.WorkingSet64 / 1MB, 1)) MB working set`n" +
        "  Threads : $($_.Threads.Count)`n" +
        "  Started : $($_.StartTime)`n"
    }
} else {
    "  Teams is not currently running.`n"
}
Write-Host "        Done." -ForegroundColor Green

# ── Section 3: Application Event Log (Teams, last 48h) ────────────
Write-Host "  [3/5] Reading Application event logs (48h)..." -ForegroundColor Yellow
$cutoff    = (Get-Date).AddHours(-48)
$appEvents = try {
    Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=$cutoff } -ErrorAction Stop |
        Where-Object { $_.ProviderName -match 'Teams|MSTeams|Microsoft\.Teams' -or
                       $_.Message      -match 'Teams' } |
        Select-Object -First 80 |
        ForEach-Object {
            "  [$($_.TimeCreated.ToString('dd/MM HH:mm:ss'))] [$($_.LevelDisplayName.ToUpper())] " +
            "Source: $($_.ProviderName) | ID: $($_.Id)`n  $($_.Message.Substring(0, [Math]::Min(300,$_.Message.Length)) -replace "`n",' ')`n"
        }
} catch {
    "  Could not read Application log: $($_.Exception.Message)`n"
}
$appEvents = if ($appEvents) { $appEvents -join "" } else { "  No Teams-related events found in last 48 hours.`n" }
Write-Host "        Done." -ForegroundColor Green

# ── Section 4: System Event Log (errors/warnings, last 24h) ───────
Write-Host "  [4/5] Reading System event logs (24h, errors only)..." -ForegroundColor Yellow
$sysEvents = try {
    Get-WinEvent -FilterHashtable @{ LogName='System'; Level=@(1,2,3); StartTime=(Get-Date).AddHours(-24) } -ErrorAction Stop |
        Select-Object -First 40 |
        ForEach-Object {
            "  [$($_.TimeCreated.ToString('dd/MM HH:mm:ss'))] [$($_.LevelDisplayName.ToUpper())] " +
            "Source: $($_.ProviderName) | ID: $($_.Id)`n  $($_.Message.Substring(0, [Math]::Min(200,$_.Message.Length)) -replace "`n",' ')`n"
        }
} catch {
    "  Could not read System log: $($_.Exception.Message)`n"
}
$sysEvents = if ($sysEvents) { $sysEvents -join "" } else { "  No errors/warnings found in last 24 hours.`n" }
Write-Host "        Done." -ForegroundColor Green

# ── Section 5: Write output file ──────────────────────────────────
Write-Host "  [5/5] Writing diagnostics file..." -ForegroundColor Yellow

$content = @"
$sysInfo
=== TEAMS PROCESS HEALTH ===
$procInfo
=== APPLICATION EVENT LOG — Teams related (last 48h) ===
$appEvents
=== SYSTEM EVENT LOG — Errors & Warnings (last 24h) ===
$sysEvents
=== END OF DIAGNOSTICS ===
"@

$content | Out-File -FilePath $outputFile -Encoding UTF8

Write-Host "        Done." -ForegroundColor Green
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "   Diagnostics saved!" -ForegroundColor Green
Write-Host "   File: $outputFile" -ForegroundColor White
Write-Host ""
Write-Host "   Go back to the IT Portal website and use" -ForegroundColor DarkGray
Write-Host "   'Analyse with Copilot' to review the results." -ForegroundColor DarkGray
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This window will close in 8 seconds..." -ForegroundColor DarkGray
Start-Sleep -Seconds 8
