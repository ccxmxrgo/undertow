# Single documented test command for UNDERTOW.
# Usage: powershell -NoProfile -File tools/run_tests.ps1 [-Path res://tests]
param([string]$Path = "res://tests")

$ErrorActionPreference = "Stop"
$godot = $env:GODOT_BIN
if (-not $godot) { $godot = [Environment]::GetEnvironmentVariable("GODOT_BIN", "User") }
if (-not $godot -or -not (Test-Path $godot)) {
    Write-Error "GODOT_BIN is not set or does not exist. Point it at Godot_v4.7.2-stable_win64_console.exe"
    exit 2
}

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not (Test-Path ".godot")) {
        & $godot --headless --path . --import
    }
    & $godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a $Path
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
