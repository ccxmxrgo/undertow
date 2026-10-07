# Runs every playtest scenario windowed on the real audio device and prints a summary.
# Usage: powershell -NoProfile -File tools/playtest/run_all.ps1 [-Scenarios a,b,c] [-SkipDrift]
# Results: build/playtest/<scenario>.json and PNG screenshots. The drift scenario takes ~5 min.
# The player's real user://settings.cfg and user://drift_log.csv are backed up before the run and
# restored afterwards (T-10-01); the drift scenario's own log is kept in build/playtest/drift_log_copy.csv.
param([string[]]$Scenarios = @("a", "b", "c", "d", "e", "f", "g", "h", "i", "layout", "drift"), [switch]$SkipDrift)

$godot = $env:GODOT_BIN
if (-not $godot) { $godot = [Environment]::GetEnvironmentVariable("GODOT_BIN", "User") }
if (-not $godot -or -not (Test-Path $godot)) { Write-Error "GODOT_BIN is not set"; exit 2 }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$userDir = Join-Path $env:APPDATA "Godot\app_userdata\UNDERTOW"
$backupDir = Join-Path $root "build\playtest\userdata_backup"
$protected = @("settings.cfg", "drift_log.csv")
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
        & $godot --path . res://tools/playtest/playtest.tscn -- $s | Select-String -Pattern "^\[(PASS|FAIL|note)\]|result="
        if ($LASTEXITCODE -ne 0) { $failed++ }
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
    Pop-Location
}
