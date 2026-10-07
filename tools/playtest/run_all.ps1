# Runs every playtest scenario windowed on the real audio device and prints a summary.
# Usage: powershell -NoProfile -File tools/playtest/run_all.ps1 [-Scenarios a,b,c] [-SkipDrift]
# Results: build/playtest/<scenario>.json and PNG screenshots. The drift scenario takes ~5 min.
param([string[]]$Scenarios = @("a", "b", "c", "d", "e", "f", "g", "h", "i", "layout", "drift"), [switch]$SkipDrift)

$godot = $env:GODOT_BIN
if (-not $godot) { $godot = [Environment]::GetEnvironmentVariable("GODOT_BIN", "User") }
if (-not $godot -or -not (Test-Path $godot)) { Write-Error "GODOT_BIN is not set"; exit 2 }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
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
finally { Pop-Location }
