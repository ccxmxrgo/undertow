# Builds the friend playtest zip (D-07 / D-09): debug export with embedded pck -> staging folder -> .zip.
# Usage: powershell -NoProfile -File tools/dist.ps1   (Windows)
#        pwsh -NoProfile -File tools/dist.ps1         (PowerShell 7, Windows or Linux; GODOT_BIN must be set)
#        powershell -NoProfile -File tools/dist.ps1 -WithPack off   (no Autocharter pack in the zip)
# The version comes from project.godot (config/version, e.g. "0.7.0" -> "v0.7.0"), the same string the
# online handshake compares (D-21), so the zip name and the in-game VERSION never drift apart.
# Output: build/dist/UNDERTOW-playtest-<version>.zip (zip only; no other archive formats are produced).
# Allow-list: UNDERTOW.exe (pck embedded), README.txt, TESTER-CHECKLIST.txt, ONLINE_SETUP.md (from docs/).
# No .pck, no console exe. The bundled songs live inside the exe. After zipping, the zip is asserted to
# hold exactly those 4 files, then expanded to build/dist/<version>_final_check and the unzipped exe
# must print BUNDLED_OK 20. Older version folders/zips are left alone.
# -WithPack (default on, friend builds): the Autocharter pack parts from
# build/release/<PackSpec.TAG>/ (undertow-ac-v1-*.zip + SHA256SUMS.txt) go into the zip under
# "<top folder>/Autocharter Pack/", where Chart a Song finds and installs them by itself
# (AutochartBundle). Every part is checked against the size and SHA-256 pinned in
# src/autocharter/pack_spec.gd first, and again after the unzip; any mismatch fails the build.
# The unzipped exe must then also print AC_PACK_FOUND. With the pack the zip uses Fastest
# compression (the parts are already zips).
# Paths use forward slashes: Windows PowerShell accepts them, and on Linux a backslash would be part
# of the file name.
param([string]$WithPack = "on")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$withPackOn = @("off", "false", "`$false", "0", "no") -notcontains $WithPack.Trim().ToLowerInvariant()
$projectFile = Join-Path $root "project.godot"
if (-not (Test-Path $projectFile)) { Write-Error "project.godot not found at $projectFile"; exit 1 }
$verMatch = Select-String -Path $projectFile -Pattern 'config/version="([^"]+)"' | Select-Object -First 1
if (-not $verMatch) {
    Write-Error 'project.godot has no config/version="x.y.z" line; cannot name the zip'
    exit 1
}
$version = "v" + $verMatch.Matches[0].Groups[1].Value
Write-Host "Building friend zip $version (from project.godot config/version)"
$name = "UNDERTOW-playtest-$version"
$distDir = Join-Path $root "build/dist"
$stage = Join-Path $distDir $name
$zip = Join-Path $distDir "$name.zip"
$check = Join-Path $distDir "${version}_final_check"
$allowed = @("README.txt", "TESTER-CHECKLIST.txt", "UNDERTOW.exe", "ONLINE_SETUP.md")
$packFolder = "Autocharter Pack"
# Staging allow-list for the text files: source path -> name inside the zip.
$docs = [ordered]@{
    (Join-Path $root "tools/dist/README.txt") = "README.txt"
    (Join-Path $root "tools/dist/TESTER-CHECKLIST.txt") = "TESTER-CHECKLIST.txt"
    (Join-Path $root "docs/ONLINE_SETUP.md") = "ONLINE_SETUP.md"
}

# The pinned Autocharter pack parts (name, size, sha256) from pack_spec.gd: the same pins the game
# installer trusts, so the zip can only ship parts the game accepts.
function Get-PackPins {
    $specFile = Join-Path $root "src/autocharter/pack_spec.gd"
    if (-not (Test-Path $specFile)) { Write-Error "pack_spec.gd not found at $specFile"; exit 1 }
    $spec = Get-Content $specFile -Raw
    $tagMatch = [regex]::Match($spec, 'const TAG := "([^"]+)"')
    if (-not $tagMatch.Success) { Write-Error "pack_spec.gd has no TAG"; exit 1 }
    $pins = @()
    foreach ($m in [regex]::Matches($spec, '\{"name": "([^"]+)", "size": (\d+), "sha256": "([0-9a-fA-F]{64})"')) {
        $pins += [pscustomobject]@{ Name = $m.Groups[1].Value; Size = [int64]$m.Groups[2].Value
            Sha = $m.Groups[3].Value.ToLowerInvariant() }
    }
    if ($pins.Count -eq 0) { Write-Error "pack_spec.gd pins no parts; cannot bundle the pack"; exit 1 }
    return @{ Tag = $tagMatch.Groups[1].Value; Parts = $pins }
}

# Fails the build unless every pinned part is in $dir with its pinned size and SHA-256.
function Assert-PackParts([string]$dir, $parts) {
    foreach ($p in $parts) {
        $f = Join-Path $dir $p.Name
        if (-not (Test-Path -LiteralPath $f)) { Write-Error "Autocharter pack part missing: $f"; exit 1 }
        $len = (Get-Item -LiteralPath $f).Length
        if ($len -ne $p.Size) {
            Write-Error ("Autocharter pack part {0}: size {1}, pack_spec.gd pins {2}" -f $p.Name, $len, $p.Size); exit 1
        }
        $sha = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sha -ne $p.Sha) {
            Write-Error ("Autocharter pack part {0}: sha256 {1}, pack_spec.gd pins {2}" -f $p.Name, $sha, $p.Sha); exit 1
        }
        Write-Host ("  pack part OK: {0} ({1:N1} MB)" -f $p.Name, ($len / 1MB))
    }
}

$pack = $null
$packSrc = ""
if ($withPackOn) {
    $pack = Get-PackPins
    $packSrc = Join-Path $root ("build/release/" + $pack.Tag)
    Write-Host "Checking the Autocharter pack in $packSrc against pack_spec.gd"
    Assert-PackParts $packSrc $pack.Parts
    $sums = Join-Path $packSrc "SHA256SUMS.txt"
    if (-not (Test-Path -LiteralPath $sums)) { Write-Error "SHA256SUMS.txt missing in $packSrc"; exit 1 }
    # SHA256SUMS.txt ships too, so it must agree with the pins.
    $listed = @{}
    foreach ($line in (Get-Content -LiteralPath $sums)) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(\S.*)$') { $listed[$Matches[2].Trim()] = $Matches[1].ToLowerInvariant() }
    }
    foreach ($p in $pack.Parts) {
        if ($listed[$p.Name] -ne $p.Sha) { Write-Error "SHA256SUMS.txt does not match pack_spec.gd for $($p.Name)"; exit 1 }
    }
    if ($listed.Count -ne $pack.Parts.Count) { Write-Error "SHA256SUMS.txt lists files that pack_spec.gd does not pin"; exit 1 }
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
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # Expected entries (top folder / relative path).
    $expected = @($allowed | ForEach-Object { "$name/$_" })
    $level = [System.IO.Compression.CompressionLevel]::Optimal
    if ($withPackOn) {
        $stagePack = Join-Path $stage $packFolder
        New-Item -ItemType Directory -Force -Path $stagePack | Out-Null
        foreach ($p in $pack.Parts) {
            Copy-Item -LiteralPath (Join-Path $packSrc $p.Name) -Destination (Join-Path $stagePack $p.Name)
            $expected += "$name/$packFolder/$($p.Name)"
        }
        Copy-Item -LiteralPath (Join-Path $packSrc "SHA256SUMS.txt") -Destination (Join-Path $stagePack "SHA256SUMS.txt")
        $expected += "$name/$packFolder/SHA256SUMS.txt"
        $level = [System.IO.Compression.CompressionLevel]::Fastest
    }

    if (Test-Path $zip) { Remove-Item $zip -Force }
    # One top-level folder holding the four files (and the Autocharter Pack folder).
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, $level, $true)
    if (-not (Test-Path $zip)) { Write-Error "Zip was not created: $zip"; exit 1 }

    $mb = (Get-Item $zip).Length / 1MB
    Write-Host ("Zip OK: {0} ({1:N2} MB)" -f $zip, $mb)
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $files = @($archive.Entries | Where-Object { $_.Name -ne "" })
        foreach ($e in $files) { Write-Host ("  {0}  {1:N2} MB" -f $e.FullName, ($e.Length / 1MB)) }
        $names = @($files | ForEach-Object { $_.FullName.Replace("\", "/") } | Sort-Object)
        if (($names -join ",") -ne (($expected | Sort-Object) -join ",")) {
            Write-Error ("Zip must hold exactly: {0}; found: {1}" -f ($expected -join ", "), ($names -join ", "))
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
    if ($withPackOn) {
        Write-Host "Checking the unzipped Autocharter pack"
        Assert-PackParts (Join-Path $uexe.DirectoryName $packFolder) $pack.Parts
    }
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
    # The unzipped game itself must find the shipped pack folder (Chart a Song installs from it).
    if ($withPackOn -and $out -notmatch "AC_PACK_FOUND") {
        Write-Error "Unzipped game did not find its Autocharter Pack folder (no AC_PACK_FOUND)"; exit 1
    }
    exit 0
}
finally {
    Pop-Location
}
