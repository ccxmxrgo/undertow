# Builds the friend playtest zip (D-10 / D-12): debug export -> fresh staging folder -> .zip.
# Usage: powershell -NoProfile -File tools/dist.ps1   (Windows)
#        pwsh -NoProfile -File tools/dist.ps1         (PowerShell 7, Windows or Linux; GODOT_BIN must be set)
# Output: build/dist/UNDERTOW-playtest-v0.5.1.zip (zip only; no other archive formats are produced).
# Only the exe(s), the pck, the README and the tester checklist are staged (T-1.1-16, T-02-28, T-02.2-46).
# The bundled songs live inside the pck (export include_filter adds *.chart,*.ini). Older version
# folders/zips are left alone.
# Paths use forward slashes: Windows PowerShell accepts them, and on Linux a backslash would be part
# of the file name.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$version = "v0.5.1"
$name = "UNDERTOW-playtest-$version"
$distDir = Join-Path $root "build/dist"
$stage = Join-Path $distDir $name
$zip = Join-Path $distDir "$name.zip"
# Staging allow-list for the text files: source path -> name inside the zip.
$docs = [ordered]@{
    (Join-Path $root "tools/dist/README.txt") = "README.txt"
    (Join-Path $root "tools/dist/TESTER-CHECKLIST.txt") = "TESTER-CHECKLIST.txt"
}

# Windows PowerShell is "powershell"; PowerShell 7 (and Linux) only has "pwsh".
$shell = "powershell"
if (-not (Get-Command $shell -ErrorAction SilentlyContinue)) { $shell = "pwsh" }

Push-Location $root
try {
    & $shell -NoProfile -File (Join-Path $root "tools/export.ps1")
    if ($LASTEXITCODE -ne 0) {
        Write-Error "export.ps1 failed (exit code $LASTEXITCODE)"
        exit 1
    }
    $exe = Join-Path $root "build/undertow-debug.exe"
    $pck = Join-Path $root "build/undertow-debug.pck"
    $consoleExe = Join-Path $root "build/undertow-debug.console.exe"
    foreach ($f in @($exe, $pck) + @($docs.Keys)) {
        if (-not (Test-Path $f)) { Write-Error "Missing build artifact: $f"; exit 1 }
    }

    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    foreach ($src in $docs.Keys) { Copy-Item $src (Join-Path $stage $docs[$src]) }
    Copy-Item $exe (Join-Path $stage "undertow-debug.exe")
    Copy-Item $pck (Join-Path $stage "undertow-debug.pck")
    if (Test-Path $consoleExe) { Copy-Item $consoleExe (Join-Path $stage "undertow-debug.console.exe") }

    if (Test-Path $zip) { Remove-Item $zip -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
        Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal -Force
    }
    else {
        # Same layout as Compress-Archive -Path <folder>: one top-level folder holding the files.
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip,
            [System.IO.Compression.CompressionLevel]::Optimal, $true)
    }
    if (-not (Test-Path $zip)) { Write-Error "Zip was not created: $zip"; exit 1 }

    $mb = (Get-Item $zip).Length / 1MB
    Write-Host ("Zip OK: {0} ({1:N2} MB)" -f $zip, $mb)
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
