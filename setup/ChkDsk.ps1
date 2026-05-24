# ================================================================
#  CHKDSK C: /scan - Online disk check with live status server
#  Sends real-time progress to the website via localhost:7779
#  /scan = online NTFS scan, no reboot needed, no admin required
# ================================================================

$statusFile = "$env:TEMP\it-tools-status.json"
$port       = 7779
$global:logLines = [System.Collections.ArrayList]@()
$startTime  = Get-Date

# ── Helper: write status to file ─────────────────────────────────
function Set-Status {
    param([int]$progress, [string]$message, [bool]$done = $false, [bool]$error = $false)

    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
    $eta = if ($error -or $done) { if ($error) { "Failed" } else { "Complete" } }
          elseif ($progress -gt 2) {
              $totalSecs = $elapsed / ($progress / 100)
              $rem = [math]::Round($totalSecs - $elapsed)
              if ($rem -gt 60) { "~$([math]::Round($rem/60)) min remaining" } else { "~${rem}s remaining" }
          } else { "Calculating..." }

    if ($message) { [void]$global:logLines.Add($message) }

    [ordered]@{
        task           = "CHKDSK Disk Check (C:)"
        status         = if ($done) { "complete" } elseif ($error) { "error" } else { "running" }
        progress       = $progress
        eta            = $eta
        elapsedSeconds = $elapsed
        message        = $message
        lines          = @($global:logLines | Select-Object -Last 40)
        done           = ($done -or $error)
    } | ConvertTo-Json -Depth 3 | Set-Content $statusFile -Encoding UTF8
}

# ── Start local HTTP server ───────────────────────────────────────
$serverJob = Start-Job -ScriptBlock {
    param($sf, $p)
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$p/")
    try { $listener.Start() } catch { return }
    while ($listener.IsListening) {
        try {
            $ctx = $listener.GetContext()
            $ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*")
            $ctx.Response.Headers.Add("Access-Control-Allow-Methods", "GET, OPTIONS")
            if ($ctx.Request.HttpMethod -eq 'OPTIONS') {
                $ctx.Response.StatusCode = 204; $ctx.Response.Close(); continue
            }
            $raw = try { [System.IO.File]::ReadAllText($sf) } catch { '{"status":"starting","progress":0,"eta":"Connecting...","lines":[],"done":false}' }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
            $ctx.Response.ContentType = "application/json; charset=utf-8"
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $ctx.Response.Close()
        } catch {}
    }
} -ArgumentList $statusFile, $port

Start-Sleep -Milliseconds 800

# ── Run CHKDSK and parse output ───────────────────────────────────
Set-Status 0 "Starting CHKDSK on C: — please wait..."

# Stage weights: Stage1=33%, Stage2=33%, Stage3=34%
$stageBase = @{ 1 = 0; 2 = 33; 3 = 66 }
$global:currentStage = 0
$global:lastPct = 0

try {
    $proc = Start-Process -FilePath "chkdsk" -ArgumentList "C: /scan" `
        -RedirectStandardOutput "$env:TEMP\chkdsk-out.txt" `
        -RedirectStandardError  "$env:TEMP\chkdsk-err.txt" `
        -PassThru -WindowStyle Hidden -Wait

    $output = Get-Content "$env:TEMP\chkdsk-out.txt" -ErrorAction SilentlyContinue
    $output | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }

        # Detect stage
        if ($line -match 'Stage (\d)') {
            $global:currentStage = [int]$Matches[1]
            Set-Status ($stageBase[$global:currentStage]) $line
        }
        # Detect percentage within a stage
        elseif ($line -match '(\d+)\s+percent') {
            $innerPct  = [int]$Matches[1]
            $base      = if ($stageBase.ContainsKey($global:currentStage)) { $stageBase[$global:currentStage] } else { 0 }
            $totalPct  = [math]::Round($base + ($innerPct * 0.33))
            $global:lastPct = [math]::Min($totalPct, 99)
            Set-Status $global:lastPct $line
        }
        # Other output lines
        else {
            Set-Status $global:lastPct $line
        }
    }

    Remove-Item "$env:TEMP\chkdsk-out.txt","$env:TEMP\chkdsk-err.txt" -Force -ErrorAction SilentlyContinue
    Set-Status 100 "CHKDSK finished." $true

} catch {
    Set-Status 0 "Error: $($_.Exception.Message)" $false $true
}

Start-Sleep -Seconds 30
Stop-Job $serverJob -ErrorAction SilentlyContinue
Remove-Job $serverJob -ErrorAction SilentlyContinue
Remove-Item $statusFile -Force -ErrorAction SilentlyContinue
