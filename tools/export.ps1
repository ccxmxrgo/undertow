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
    if (-not (Test-Path ".godot")) {
        & $godot --headless --path . --import
    }
    & $godot --headless --path . --export-debug "Windows Desktop" build/undertow-debug.exe
    $code = $LASTEXITCODE
    if (-not (Test-Path "build/undertow-debug.exe")) {
        Write-Error "Export failed: build/undertow-debug.exe is missing (godot exit code $code)"
        exit 1
    }
    Write-Host "Export OK: build/undertow-debug.exe"
    exit 0
}
finally {
    Pop-Location
}
