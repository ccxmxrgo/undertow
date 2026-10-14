# Builds the friend playtest zip (D-07 / D-09): debug export with embedded pck -> staging folder -> .zip.
# Usage: powershell -NoProfile -File tools/dist.ps1   (Windows)
#        pwsh -NoProfile -File tools/dist.ps1         (PowerShell 7, Windows or Linux; GODOT_BIN must be set)
# Output: build/dist/UNDERTOW-playtest-v0.5.3.zip (zip only; no other archive formats are produced).
# Allow-list: UNDERTOW.exe (pck embedded), README.txt, TESTER-CHECKLIST.txt. No .pck, no console exe.
# The bundled songs live inside the exe. After zipping, the zip is asserted to hold exactly those 3 files,
# then expanded to build/dist/v0.5.3_final_check and the unzipped exe must print BUNDLED_OK 20.
# Older version folders/zips are left alone.
# Paths use forward slashes: Windows PowerShell accepts them, and on Linux a backslash would be part
# of the file name.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$version = "v0.5.3"
$name = "UNDERTOW-playtest-$version"
$distDir = Join-Path $root "build/dist"
$stage = Join-Path $distDir $name
$zip = Join-Path $distDir "$name.zip"
$check = Join-Path $distDir "${version}_final_check"
$allowed = @("README.txt", "TESTER-CHECKLIST.txt", "UNDERTOW.exe")
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
    $exe = Join-Path $root "build/UNDERTOW.exe"
    foreach ($f in @($exe) + @($docs.Keys)) {
        if (-not (Test-Path $f)) { Write-Error "Missing build artifact: $f"; exit 1 }
    }

    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    foreach ($src in $docs.Keys) { Copy-Item $src (Join-Path $stage $docs[$src]) }
    Copy-Item $exe (Join-Path $stage "UNDERTOW.exe")

    if (Test-Path $zip) { Remove-Item $zip -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # One top-level folder holding the three files.
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip,
        [System.IO.Compression.CompressionLevel]::Optimal, $true)
    if (-not (Test-Path $zip)) { Write-Error "Zip was not created: $zip"; exit 1 }

    $mb = (Get-Item $zip).Length / 1MB
    Write-Host ("Zip OK: {0} ({1:N2} MB)" -f $zip, $mb)
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $files = @($archive.Entries | Where-Object { $_.Name -ne "" })
        foreach ($e in $files) { Write-Host ("  {0}  {1:N2} MB" -f $e.FullName, ($e.Length / 1MB)) }
        $names = @($files | ForEach-Object { $_.Name } | Sort-Object)
        if (($names -join ",") -ne (($allowed | Sort-Object) -join ",")) {
            Write-Error ("Zip must hold exactly: {0}; found: {1}" -f ($allowed -join ", "), ($names -join ", "))
            exit 1
        }
        if ($files | Where-Object { $_.Name -like "*.pck" -or $_.Name -like "*.console.exe" }) {
            Write-Error "Zip contains a .pck or console exe"; exit 1
        }
    }
    finally { $archive.Dispose() }

    # Prove the zip: unzip fresh and run the bundled-content selftest on the single exe.
    if (Test-Path $check) { Remove-Item $check -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $check)
    $uexe = Get-ChildItem $check -Recurse -Filter UNDERTOW.exe | Select-Object -First 1
    if (-not $uexe) { Write-Error "UNDERTOW.exe not found after unzip"; exit 1 }
    $outFile = Join-Path $check "selftest.out.txt"
    $errFile = Join-Path $check "selftest.err.txt"
    $p = Start-Process -FilePath $uexe.FullName -ArgumentList @("--headless", "--", "--selftest-bundled") `
        -WorkingDirectory $uexe.DirectoryName -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
        -PassThru -NoNewWindow
    $null = $p.Handle  # cache the handle so ExitCode survives WaitForExit
    if (-not $p.WaitForExit(120000)) {
        try { $p.Kill() } catch { }
        Write-Error "Unzipped selftest timed out after 120 s"; exit 1
    }
    $p.WaitForExit()
    $out = ""
    if (Test-Path $outFile) { $out = (Get-Content $outFile -Raw) }
    if ($null -eq $out) { $out = "" }
    Write-Host ("Selftest exit code {0}; output: {1}" -f $p.ExitCode, $out.Trim())
    if ($p.ExitCode -ne 0 -or $out -notmatch "BUNDLED_OK 20") {
        Write-Error "Unzipped selftest did not print BUNDLED_OK 20 with exit 0"; exit 1
    }
    exit 0
}
finally {
    Pop-Location
}
