# ================================================================
#  Teams-CacheHealthCheck.ps1
#  Detects signs of Teams cache corruption
#  Read-Only — No admin required
#  New Teams (MSIX) + Classic Teams
# ================================================================

$Host.UI.RawUI.WindowTitle = "Teams Cache Health Check"
Clear-Host

function Write-Header { param($t)
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  │  $t" -ForegroundColor Cyan
    Write-Host "  └─────────────────────────────────────────────┘" -ForegroundColor Cyan
}
function Write-OK   { param($m) Write-Host "     ✔  $m" -ForegroundColor Green  }
function Write-Warn { param($m) Write-Host "     ⚠  $m" -ForegroundColor Yellow }
function Write-Fail { param($m) Write-Host "     ✘  $m" -ForegroundColor Red    }
function Write-Info { param($m) Write-Host "     ℹ  $m" -ForegroundColor White  }

$Issues  = [System.Collections.Generic.List[string]]::new()
$Healthy = [System.Collections.Generic.List[string]]::new()

function Add-Issue  { param($m) $Issues.Add($m)  }
function Add-Health { param($m) $Healthy.Add($m) }

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     Teams Cache Corruption Detector           ║" -ForegroundColor Cyan
Write-Host "  ║     Read-Only  •  No Admin Required           ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan

# ── Detect which Teams is installed ─────────────────────────
$newTeamsPkg  = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue
$classicPath  = "$env:APPDATA\Microsoft\Teams"
$newCachePath = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"

# ════════════════════════════════════════════════════════════
#  CHECK 1 — Zero-byte files (most common corruption sign)
# ════════════════════════════════════════════════════════════
Write-Header "Check 1 — Zero-Byte Files"
Write-Info "Zero-byte files = incomplete write = corruption"

$cachesToCheck = @()
if (Test-Path $newCachePath)  { $cachesToCheck += $newCachePath  }
if (Test-Path $classicPath)   { $cachesToCheck += $classicPath   }

foreach ($cachePath in $cachesToCheck) {
    Write-Info "Scanning: $cachePath"

    $zeroFiles = Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object {
                     $_.Length -eq 0 -and
                     $_.Extension -match "\.db$|\.json$|\.ldb$|\.log$|\.manifest$"
                 }

    if ($zeroFiles) {
        Write-Fail "Found $($zeroFiles.Count) zero-byte critical file(s):"
        $zeroFiles | ForEach-Object {
            Write-Fail "    0 bytes → $($_.FullName)"
            Add-Issue "Zero-byte file: $($_.FullName)"
        }
    } else {
        Write-OK "No zero-byte critical files found"
        Add-Health "Zero-byte check passed: $cachePath"
    }
}

# ════════════════════════════════════════════════════════════
#  CHECK 2 — Corrupted SQLite DB Files
# ════════════════════════════════════════════════════════════
Write-Header "Check 2 — SQLite Database Integrity"
Write-Info "Teams uses .db files for chat, contacts, settings"

foreach ($cachePath in $cachesToCheck) {
    $dbFiles = Get-ChildItem -Path $cachePath -Recurse -Filter "*.db" -ErrorAction SilentlyContinue

    if (-not $dbFiles) {
        Write-Info "No .db files found in $cachePath"
    } else {
        foreach ($db in $dbFiles) {
            # SQLite files always start with "SQLite format 3" header (first 16 bytes)
            try {
                $bytes = [System.IO.File]::ReadAllBytes($db.FullName) |
                         Select-Object -First 16

                if ($bytes.Count -lt 16) {
                    Write-Fail "CORRUPT (too small): $($db.Name) — $($db.Length) bytes"
                    Add-Issue "Truncated SQLite DB: $($db.FullName) ($($db.Length) bytes)"
                } else {
                    # SQLite header magic bytes: 53 51 4C 69 74 65 20 66 6F 72 6D 61 74 20 33 00
                    $sqliteHeader = @(83,81,76,105,116,101,32,102,111,114,109,97,116,32,51,0)
                    $headerMatch  = $true

                    for ($i = 0; $i -lt 15; $i++) {
                        if ($bytes[$i] -ne $sqliteHeader[$i]) {
                            $headerMatch = $false
                            break
                        }
                    }

                    if ($headerMatch) {
                        Write-OK  "Valid SQLite header: $($db.Name) ($([math]::Round($db.Length/1KB,1)) KB)"
                        Add-Health "SQLite OK: $($db.Name)"
                    } else {
                        Write-Fail "CORRUPT header: $($db.Name) — not a valid SQLite file"
                        Add-Issue "Corrupt SQLite header: $($db.FullName)"
                    }
                }
            } catch {
                Write-Warn "Could not read: $($db.Name) — may be locked by Teams"
                Add-Issue "Locked/unreadable DB: $($db.FullName)"
            }
        }
    }
}

# ════════════════════════════════════════════════════════════
#  CHECK 3 — JSON Config File Corruption
# ════════════════════════════════════════════════════════════
Write-Header "Check 3 — JSON Config Files"
Write-Info "Corrupt JSON = Teams launches with wrong settings or crashes"

$jsonFiles = @(
    "$env:APPDATA\Microsoft\Teams\desktop-config.json",
    "$env:APPDATA\Microsoft\Teams\app-settings.json",
    "$env:APPDATA\Microsoft\Teams\settings.json",
    "$newCachePath\app-settings.json"
)

foreach ($jsonPath in $jsonFiles) {
    if (Test-Path $jsonPath) {
        $fileInfo = Get-Item $jsonPath
        if ($fileInfo.Length -eq 0) {
            Write-Fail "EMPTY JSON: $jsonPath"
            Add-Issue "Empty JSON config: $jsonPath"
        } else {
            try {
                $content = Get-Content $jsonPath -Raw -ErrorAction Stop
                $null    = $content | ConvertFrom-Json -ErrorAction Stop
                Write-OK  "Valid JSON: $(Split-Path $jsonPath -Leaf) ($([math]::Round($fileInfo.Length/1KB,1)) KB)"
                Add-Health "JSON OK: $(Split-Path $jsonPath -Leaf)"
            } catch {
                Write-Fail "INVALID JSON syntax: $jsonPath"
                Add-Issue "Corrupt JSON file: $jsonPath — $($_.Exception.Message)"
            }
        }
    } else {
        Write-Info "Not found (skip): $(Split-Path $jsonPath -Leaf)"
    }
}

# ════════════════════════════════════════════════════════════
#  CHECK 4 — LevelDB / IndexedDB Integrity
# ════════════════════════════════════════════════════════════
Write-Header "Check 4 — LevelDB / IndexedDB Integrity"
Write-Info "Teams uses LevelDB for real-time data — CURRENT and MANIFEST files must exist"

$levelDbPaths = @()
if (Test-Path $newCachePath) {
    $levelDbPaths += Get-ChildItem -Path $newCachePath -Recurse -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match "IndexedDB|LevelDB|Local Storage" }
}
if (Test-Path $classicPath) {
    $levelDbPaths += Get-ChildItem -Path $classicPath -Recurse -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match "IndexedDB|LevelDB|Local Storage" }
}

if (-not $levelDbPaths) {
    Write-Info "No LevelDB folders found — may be clean install"
} else {
    foreach ($ldb in $levelDbPaths) {
        Write-Info "Checking: $($ldb.FullName)"

        $currentFile = Join-Path $ldb.FullName "CURRENT"
        if (Test-Path $currentFile) {
            $currentSize = (Get-Item $currentFile).Length
            if ($currentSize -eq 0) {
                Write-Fail "CORRUPT: CURRENT file is 0 bytes in $($ldb.Name)"
                Add-Issue "LevelDB CURRENT file empty: $($ldb.FullName)"
            } else {
                Write-OK  "CURRENT file OK in $($ldb.Name)"
                Add-Health "LevelDB CURRENT OK: $($ldb.Name)"
            }
        } else {
            Write-Fail "MISSING: CURRENT file not found in $($ldb.Name)"
            Add-Issue "LevelDB CURRENT missing: $($ldb.FullName)"
        }

        $manifest = Get-ChildItem -Path $ldb.FullName -Filter "MANIFEST-*" -ErrorAction SilentlyContinue |
                    Select-Object -First 1
        if ($manifest) {
            if ($manifest.Length -eq 0) {
                Write-Fail "CORRUPT: MANIFEST is 0 bytes in $($ldb.Name)"
                Add-Issue "LevelDB MANIFEST empty: $($ldb.FullName)"
            } else {
                Write-OK  "MANIFEST OK in $($ldb.Name) ($($manifest.Length) bytes)"
                Add-Health "LevelDB MANIFEST OK: $($ldb.Name)"
            }
        } else {
            Write-Warn "MANIFEST file not found in $($ldb.Name)"
            Add-Issue "LevelDB MANIFEST missing: $($ldb.FullName)"
        }

        $zeroLdb = Get-ChildItem -Path $ldb.FullName -Filter "*.ldb" -ErrorAction SilentlyContinue |
                   Where-Object { $_.Length -eq 0 }
        if ($zeroLdb) {
            Write-Fail "$($zeroLdb.Count) zero-byte .ldb file(s) in $($ldb.Name)"
            $zeroLdb | ForEach-Object { Add-Issue "Zero-byte LDB: $($_.FullName)" }
        } else {
            Write-OK  "All .ldb files have content in $($ldb.Name)"
        }
    }
}

# ════════════════════════════════════════════════════════════
#  CHECK 5 — Abnormal File Timestamps
# ════════════════════════════════════════════════════════════
Write-Header "Check 5 — Abnormal File Timestamps"
Write-Info "Future dates or 1970 epoch dates = corrupt file metadata"

$now       = Get-Date
$epochDate = Get-Date "1970-01-01"
$future    = $now.AddDays(1)

foreach ($cachePath in $cachesToCheck) {
    $weirdDates = Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue |
                  Where-Object {
                      $_.LastWriteTime -lt $epochDate.AddDays(30) -or
                      $_.LastWriteTime -gt $future
                  }

    if ($weirdDates) {
        Write-Fail "Found $($weirdDates.Count) file(s) with abnormal timestamps:"
        $weirdDates | Select-Object -First 10 | ForEach-Object {
            Write-Fail "    $($_.LastWriteTime.ToString('dd-MMM-yyyy HH:mm')) → $($_.Name)"
            Add-Issue "Abnormal timestamp: $($_.FullName) — $($_.LastWriteTime)"
        }
    } else {
        Write-OK "All file timestamps look normal"
        Add-Health "Timestamp check passed: $cachePath"
    }
}

# ════════════════════════════════════════════════════════════
#  CHECK 6 — Locked Files (ghost process holding files)
# ════════════════════════════════════════════════════════════
Write-Header "Check 6 — Locked Cache Files"
Write-Info "Files locked when Teams is not running = ghost process or corruption"

$teamsRunning = Get-Process -Name "ms-teams" -ErrorAction SilentlyContinue

if ($teamsRunning) {
    Write-Info "Teams is currently running — locked files are expected. Close Teams and rerun for accurate results."
} else {
    Write-Info "Teams is not running — checking for unexpectedly locked files..."

    foreach ($cachePath in $cachesToCheck) {
        $dbFilesCheck = Get-ChildItem -Path $cachePath -Recurse -Filter "*.db" -ErrorAction SilentlyContinue |
                        Select-Object -First 10

        $lockedCount = 0
        foreach ($f in $dbFilesCheck) {
            try {
                $stream = [System.IO.File]::Open($f.FullName, 'Open', 'ReadWrite', 'None')
                $stream.Close()
            } catch {
                Write-Fail "LOCKED: $($f.Name) — $($_.Exception.Message)"
                Add-Issue "File locked without Teams running: $($f.FullName)"
                $lockedCount++
            }
        }

        if ($lockedCount -eq 0) {
            Write-OK "No unexpectedly locked files found"
            Add-Health "Lock check passed: $cachePath"
        }
    }
}

# ════════════════════════════════════════════════════════════
#  CHECK 7 — GPU Cache
# ════════════════════════════════════════════════════════════
Write-Header "Check 7 — GPU Cache"
Write-Info "Corrupt GPU cache causes black screens and rendering issues in Teams"

$gpuPaths = @(
    "$env:APPDATA\Microsoft\Teams\GPUCache",
    "$newCachePath\GPUCache"
)

foreach ($gpuPath in $gpuPaths) {
    if (Test-Path $gpuPath) {
        $indexFile = Join-Path $gpuPath "index"

        if (-not (Test-Path $indexFile)) {
            Write-Fail "GPU Cache index file MISSING: $gpuPath"
            Add-Issue "GPU Cache index missing: $gpuPath"
        } else {
            $indexSize = (Get-Item $indexFile).Length
            if ($indexSize -eq 0) {
                Write-Fail "GPU Cache index is 0 bytes: $gpuPath"
                Add-Issue "GPU Cache index empty: $gpuPath"
            } else {
                Write-OK  "GPU Cache index OK ($indexSize bytes)"
                Add-Health "GPU Cache OK: $gpuPath"
            }
        }

        $zeroGPU = Get-ChildItem -Path $gpuPath -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Length -eq 0 }
        if ($zeroGPU) {
            Write-Warn "$($zeroGPU.Count) zero-byte GPU cache file(s) found"
            Add-Issue "Zero-byte GPU cache files: $gpuPath ($($zeroGPU.Count) files)"
        }
    } else {
        Write-Info "GPU Cache not found at: $gpuPath (may be clean install)"
    }
}

# ════════════════════════════════════════════════════════════
#  CHECK 8 — Cache Size Sanity Check
# ════════════════════════════════════════════════════════════
Write-Header "Check 8 — Cache Size Sanity"
Write-Info "Extremely small cache on active install = files were wiped/corrupted"

foreach ($cachePath in $cachesToCheck) {
    if (Test-Path $cachePath) {
        $totalSize = (Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue |
                      Measure-Object -Property Length -Sum).Sum

        $sizeMB = [math]::Round($totalSize / 1MB, 2)
        Write-Info "Cache size: $sizeMB MB at $cachePath"

        if ($sizeMB -lt 1) {
            Write-Fail "Cache is suspiciously small ($sizeMB MB) — possible corruption or wipe"
            Add-Issue "Suspiciously small cache: $sizeMB MB at $cachePath"
        } elseif ($sizeMB -gt 2000) {
            Write-Warn "Cache is very large ($sizeMB MB) — consider clearing"
            Add-Issue "Oversized cache: $sizeMB MB — may cause performance issues"
        } else {
            Write-OK  "Cache size looks normal: $sizeMB MB"
            Add-Health "Cache size OK: $sizeMB MB"
        }
    }
}

# ════════════════════════════════════════════════════════════
#  FINAL REPORT
# ════════════════════════════════════════════════════════════
Write-Host ""
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║          TEAMS CACHE HEALTH REPORT                       ║" -ForegroundColor Cyan
Write-Host "  ║          $(Get-Date -Format 'dd-MMM-yyyy HH:mm:ss')                          ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($Issues.Count -eq 0) {
    Write-Host "  ✔  Cache looks healthy — No corruption detected" -ForegroundColor Green
    Write-Host ""
    Write-Host "  If Teams is still misbehaving, the issue is likely:" -ForegroundColor White
    Write-Host "   • Network / proxy related" -ForegroundColor White
    Write-Host "   • Authentication / token expiry" -ForegroundColor White
    Write-Host "   • Server-side Microsoft 365 issue" -ForegroundColor White
} else {
    Write-Host "  ✘  $($Issues.Count) corruption issue(s) found:" -ForegroundColor Red
    Write-Host ""
    $i = 1
    $Issues | ForEach-Object {
        Write-Host "   $i. $_" -ForegroundColor Red
        $i++
    }

    Write-Host ""
    Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "   RECOMMENDED ACTION" -ForegroundColor Cyan
    Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "   1. Close Teams completely" -ForegroundColor Yellow
    Write-Host "   2. Run the Teams Repair script" -ForegroundColor Yellow
    Write-Host "   3. If repair doesn't fix it, clear the cache manually" -ForegroundColor Yellow
    Write-Host "   4. Relaunch Teams" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Healthy checks : $($Healthy.Count)" -ForegroundColor Green
Write-Host "  Issues found   : $($Issues.Count)" -ForegroundColor $(if ($Issues.Count -gt 0) { "Red" } else { "Green" })
Write-Host ""
Read-Host "  Press Enter to close"
