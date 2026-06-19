# ================================================================
#  SFC /scannow - System File Checker with live status server
#  Sends real-time progress to the website via localhost:7779
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
        task           = "SFC System File Check"
        status         = if ($done) { "complete" } elseif ($error) { "error" } else { "running" }
        progress       = $progress
        eta            = $eta
        elapsedSeconds = $elapsed
        message        = $message
        lines          = @($global:logLines | Select-Object -Last 40)
        done           = ($done -or $error)
    } | ConvertTo-Json -Depth 3 | Set-Content $statusFile -Encoding UTF8
}

# ── Start local HTTP server (background job reads status file) ────
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

Start-Sleep -Milliseconds 800   # give server time to start

# ── Run SFC and parse output ──────────────────────────────────────
Set-Status 0 "Starting SFC scan — please wait..."
$global:lastPct = 0

try {
    $proc = Start-Process -FilePath "sfc" -ArgumentList "/scannow" `
        -RedirectStandardOutput "$env:TEMP\sfc-out.txt" `
        -RedirectStandardError  "$env:TEMP\sfc-err.txt" `
        -PassThru -WindowStyle Hidden -Wait

    $output = Get-Content "$env:TEMP\sfc-out.txt" -ErrorAction SilentlyContinue
    $output | ForEach-Object {
        $line = ($_ -replace '\x00', '').Trim()
        if (-not $line) { return }

        if ($line -match 'Verification\s+(\d+)%') {
            $pct = [int]$Matches[1]
            $global:lastPct = $pct
            Set-Status $pct $line
        } elseif ($line -match 'Beginning verification') {
            Set-Status 3 $line
        } elseif ($line -match 'beginning system scan') {
            Set-Status 1 $line
        } elseif ($line -match 'did not find any integrity') {
            Set-Status 99 $line
        } elseif ($line -match 'found and repaired') {
            Set-Status 99 $line
        } elseif ($line -match 'administrator') {
            Set-Status 0 "ERROR: Administrator rights required to run SFC." $false $true
        } else {
            Set-Status $global:lastPct $line
        }
    }

    Remove-Item "$env:TEMP\sfc-out.txt","$env:TEMP\sfc-err.txt" -Force -ErrorAction SilentlyContinue
    Set-Status 100 "SFC scan finished." $true

} catch {
    Set-Status 0 "Error: $($_.Exception.Message)" $false $true
}

# ── Shut down the server after 30s (gives website time to read final state) ──
Start-Sleep -Seconds 30
Stop-Job $serverJob -ErrorAction SilentlyContinue
Remove-Job $serverJob -ErrorAction SilentlyContinue
Remove-Item $statusFile -Force -ErrorAction SilentlyContinue
