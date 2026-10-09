# Runs every playtest scenario windowed on the real audio device and prints a summary.
# Usage: powershell -NoProfile -File tools/playtest/run_all.ps1 [-Scenarios a,b,c] [-SkipDrift]
# Results: build/playtest/<scenario>.json and PNG screenshots. The drift scenario takes ~5 min.
# The player's real user://settings.cfg, user://scores.cfg and user://drift_log.csv are backed up before the run and
# restored afterwards (T-10-01); the drift scenario's own log is kept in build/playtest/drift_log_copy.csv.
# Every scenario runs with the user arg --no-boot-scan, so SongLibrary never scans the real Songs folder
# (the driver points it at user://playtest_library). SHA-256 of the protected files and a listing of the
# real Songs folder are taken before and after the run and compared (T-02-26).
param([string[]]$Scenarios = @("a", "b", "c", "d", "e", "f", "g", "h", "i", "layout", "polish", "immersion", "songs", "drift"), [switch]$SkipDrift)

$godot = $env:GODOT_BIN
if (-not $godot) { $godot = [Environment]::GetEnvironmentVariable("GODOT_BIN", "User") }
if (-not $godot -or -not (Test-Path $godot)) { Write-Error "GODOT_BIN is not set"; exit 2 }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$userDir = Join-Path $env:APPDATA "Godot\app_userdata\UNDERTOW"
$backupDir = Join-Path $root "build\playtest\userdata_backup"
$protected = @("settings.cfg", "drift_log.csv", "scores.cfg")
$realSongs = Join-Path $userDir "songs"
function Get-UserDataProof {
    $lines = @()
    foreach ($f in $protected) {
        $p = Join-Path $userDir $f
        if (Test-Path $p) { $lines += "$f " + (Get-FileHash -Algorithm SHA256 $p).Hash } else { $lines += "$f absent" }
    }
    if (Test-Path $realSongs) {
        $items = @(Get-ChildItem -Recurse -Force $realSongs | ForEach-Object { "{0}|{1}|{2}" -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks })
        $lines += "songs/ entries=$($items.Count) " + (($items | Sort-Object) -join ";").GetHashCode()
    } else { $lines += "songs/ absent" }
    return $lines
}
$proofBefore = Get-UserDataProof
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
foreach ($f in $protected) {
    $src = Join-Path $userDir $f
    $bak = Join-Path $backupDir $f
    if (Test-Path $bak) { Remove-Item $bak -Force }
    if (Test-Path $src) { Copy-Item $src $bak -Force }
}
Push-Location $root
try {
    $failed = 0
    foreach ($s in $Scenarios) {
        if ($SkipDrift -and $s -eq "drift") { continue }
        # Hard external watchdog on top of the driver's own TIMEOUTS: a hung Godot is killed, not waited on.
        $limit = if ($s -eq "drift") { 600 } elseif ($s -eq "songs") { 420 } else { 300 }
        $log = Join-Path $root "build\playtest\${s}_stdout.txt"
        $err = Join-Path $root "build\playtest\${s}_stderr.txt"
        $p = Start-Process -FilePath $godot -ArgumentList @("--path", ".", "res://tools/playtest/playtest.tscn", "--", $s, "--no-boot-scan") `
            -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
        $null = $p.Handle
        if (-not $p.WaitForExit($limit * 1000)) {
            Write-Host "[FAIL] scenario $s killed after $limit s (stalled)"
            & taskkill.exe /T /F /PID $p.Id | Out-Null  # whole tree: the console exe wraps the GUI exe
            $failed++
            continue
        }
        Select-String -Path $log -Pattern "^\[(PASS|FAIL|note)\]|result=" | ForEach-Object { $_.Line }
        if ($p.ExitCode -ne 0) { $failed++ }
    }
    Write-Host "Scenarios failed: $failed"
    exit $failed
}
finally {
    foreach ($f in $protected) {
        $dst = Join-Path $userDir $f
        $bak = Join-Path $backupDir $f
        if (Test-Path $bak) { Copy-Item $bak $dst -Force }
        elseif (Test-Path $dst) { Remove-Item $dst -Force }
    }
    $proofAfter = Get-UserDataProof
    for ($i = 0; $i -lt $proofBefore.Count; $i++) {
        $same = $proofBefore[$i] -eq $proofAfter[$i]
        Write-Host ("[{0}] real user data unchanged: {1}" -f $(if ($same) { "PASS" } else { "FAIL" }), $proofAfter[$i])
    }
    Pop-Location
}
