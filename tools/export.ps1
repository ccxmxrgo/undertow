# Windows debug export for the second-PC smoke test (D-31).
# Usage: powershell -NoProfile -File tools/export.ps1
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
    New-Item -ItemType Directory -Force -Path build | Out-Null
    # build/ holds playtest evidence (JSON, CSV, PNG). Keep Godot from importing it and the export
    # from packing it (export_presets.cfg also excludes build/*).
    if (-not (Test-Path "build/.gdignore")) { New-Item -ItemType File -Path "build/.gdignore" | Out-Null }
    if (-not (Test-Path ".godot")) {
        & $godot --headless --path . --import
    }
    # Drop stale artifacts so a failed export cannot be mistaken for a fresh build (WR-07).
    Remove-Item build/undertow-debug.exe, build/undertow-debug.pck -ErrorAction SilentlyContinue
    & $godot --headless --path . --export-debug "Windows Desktop" build/undertow-debug.exe
    $code = $LASTEXITCODE
    if ($code -ne 0 -or -not (Test-Path "build/undertow-debug.exe")) {
        Write-Error "Export failed: build/undertow-debug.exe is missing (godot exit code $code)"
        exit 1
    }
    Write-Host "Export OK: build/undertow-debug.exe"
    exit 0
}
finally {
    Pop-Location
}
