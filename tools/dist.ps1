# Builds the friend playtest zip (D-10 / D-12): debug export -> fresh staging folder -> .zip.
# Usage: powershell -NoProfile -File tools/dist.ps1
# Output: build/dist/UNDERTOW-playtest-v0.4.zip (zip only; no other archive formats are produced).
# Only the exe(s), the pck and the README are staged (T-1.1-16, T-02-28). The bundled songs live inside
# the pck (export include_filter adds *.chart,*.ini). Older version folders/zips are left alone.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$version = "v0.4"
$name = "UNDERTOW-playtest-$version"
$distDir = Join-Path $root "build\dist"
$stage = Join-Path $distDir $name
$zip = Join-Path $distDir "$name.zip"
$readme = Join-Path $root "tools\dist\README.txt"

Push-Location $root
try {
    & powershell -NoProfile -File (Join-Path $root "tools\export.ps1")
    if ($LASTEXITCODE -ne 0) {
        Write-Error "export.ps1 failed (exit code $LASTEXITCODE)"
        exit 1
    }
    $exe = Join-Path $root "build\undertow-debug.exe"
    $pck = Join-Path $root "build\undertow-debug.pck"
    $consoleExe = Join-Path $root "build\undertow-debug.console.exe"
    foreach ($f in @($exe, $pck, $readme)) {
        if (-not (Test-Path $f)) { Write-Error "Missing build artifact: $f"; exit 1 }
    }

    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Copy-Item $readme (Join-Path $stage "README.txt")
    Copy-Item $exe (Join-Path $stage "undertow-debug.exe")
    Copy-Item $pck (Join-Path $stage "undertow-debug.pck")
    if (Test-Path $consoleExe) { Copy-Item $consoleExe (Join-Path $stage "undertow-debug.console.exe") }

    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal -Force
    if (-not (Test-Path $zip)) { Write-Error "Zip was not created: $zip"; exit 1 }

    $mb = (Get-Item $zip).Length / 1MB
    Write-Host ("Zip OK: {0} ({1:N2} MB)" -f $zip, $mb)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($e in $archive.Entries) { Write-Host ("  {0}  {1:N2} MB" -f $e.FullName, ($e.Length / 1MB)) }
    }
    finally { $archive.Dispose() }
    exit 0
}
finally {
    Pop-Location
}
