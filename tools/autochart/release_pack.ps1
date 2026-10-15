# Stage and verify the Autocharter pack release assets (Phase 2.2.2 plan 10; D-09, D-10, D-16).
# Usage (from anywhere):
#   powershell -NoProfile -File tools/autochart/release_pack.ps1                   stage + archive
#   powershell -NoProfile -File tools/autochart/release_pack.ps1 -VerifyPublished  check the live release
#
# Default mode:
#   1. reads the pinned parts (name, size, SHA-256), TAG and BASE_URL from src/autocharter/pack_spec.gd
#   2. checks build/pack/out/SHA256SUMS.txt against those pins
#   3. creates a fresh build/release/autocharter-pack-v1/ with every part zip, re-hashes each copy and
#      requires size + SHA-256 equality with pack_spec.gd (mismatch -> throw "... rebuild")
#   4. writes SHA256SUMS.txt ("<hex>  <name>", sorted by name, LF) and RELEASE_NOTES.md
#   5. D-16: copies the staged folder (+ pack_manifest.json, PACK-RELEASE.txt) to
#      C:\Users\User\UNDERTOW-release-archive\autocharter-pack-v1 (outside the repo). An existing archive
#      with a different SHA256SUMS.txt is an error, never overwritten. The archive copy is re-hashed.
#   6. prints the publish command and RELEASE_STAGE_OK
# -VerifyPublished: downloads every part from BASE_URL + name with curl.exe into build/release/verify/,
#   checks size + SHA-256 against pack_spec.gd and prints RELEASE_LIVE_OK (or the failing part).
#
# This script NEVER uploads or publishes anything. Publishing is the user's action (PACK-RELEASE.txt).

param(
    [switch]$VerifyPublished,
    [string]$ArchiveRoot = "C:\Users\User\UNDERTOW-release-archive"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$specPath = Join-Path $root "src/autocharter/pack_spec.gd"
$outDir = Join-Path $root "build/pack/out"
$utf8 = New-Object System.Text.UTF8Encoding($false)

# ---- pins from pack_spec.gd ----
$specText = [System.IO.File]::ReadAllText($specPath)
$tag = [regex]::Match($specText, 'const TAG := "([^"]+)"').Groups[1].Value
$baseUrl = [regex]::Match($specText, 'const BASE_URL := "([^"]+)"').Groups[1].Value
$parts = @()
foreach ($m in [regex]::Matches($specText, '\{"name": "([^"]+)", "size": (\d+), "sha256": "([0-9a-f]{64})"')) {
    $parts += [pscustomobject]@{ Name = $m.Groups[1].Value; Size = [int64]$m.Groups[2].Value; Sha = $m.Groups[3].Value }
}
if ($tag -eq "" -or $baseUrl -eq "" -or $parts.Count -eq 0) {
    throw "could not read TAG, BASE_URL and PARTS from $specPath"
}
if (-not $baseUrl.StartsWith("https://") -or -not $baseUrl.Contains("/$tag/")) {
    throw "BASE_URL $baseUrl does not point at tag $tag"
}
foreach ($p in $parts) {
    if ($p.Name -notmatch '^[A-Za-z0-9._-]+\.zip$') { throw "unsafe part name $($p.Name)" }
}
$total = ($parts | Measure-Object -Property Size -Sum).Sum
Write-Host ("pack_spec.gd: tag {0}, {1} parts, {2:N1} MB" -f $tag, $parts.Count, ($total / 1e6))

function Get-Sha([string]$path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
}

# Throws unless every part in $dir has the pinned size and SHA-256.
function Assert-Parts([string]$dir, [string]$what) {
    foreach ($p in $parts) {
        $f = Join-Path $dir $p.Name
        if (-not (Test-Path -LiteralPath $f)) { throw "$what is missing $($p.Name)" }
        $len = (Get-Item -LiteralPath $f).Length
        $sha = Get-Sha $f
        if ($len -ne $p.Size -or $sha -ne $p.Sha) {
            throw "pack_spec.gd and $what differ: $($p.Name) is $len bytes sha256 $sha, pinned $($p.Size) bytes sha256 $($p.Sha): rebuild"
        }
        Write-Host ("  ok {0,-30} {1,11} {2}" -f $p.Name, $len, $sha)
    }
}

function Get-SumsText {
    $lines = $parts | Sort-Object -Property Name | ForEach-Object { "$($_.Sha)  $($_.Name)" }
    return (($lines -join "`n") + "`n")
}

$names = ($parts | ForEach-Object { $_.Name })

if ($VerifyPublished) {
    $vdir = Join-Path $root "build/release/verify"
    if (Test-Path -LiteralPath $vdir) { Remove-Item -LiteralPath $vdir -Recurse -Force }
    New-Item -ItemType Directory -Path $vdir | Out-Null
    foreach ($p in $parts) {
        $url = $baseUrl + $p.Name
        $dest = Join-Path $vdir $p.Name
        Write-Host "GET $url"
        & curl.exe -L --fail -sS -o $dest $url
        if ($LASTEXITCODE -ne 0) {
            Write-Host "RELEASE_LIVE_FAIL $($p.Name) curl exit $LASTEXITCODE (not published yet, or the name differs)"
            exit 1
        }
        $len = (Get-Item -LiteralPath $dest).Length
        $sha = Get-Sha $dest
        if ($len -ne $p.Size -or $sha -ne $p.Sha) {
            Write-Host "RELEASE_LIVE_FAIL $($p.Name) is $len bytes sha256 $sha, pinned $($p.Size) bytes sha256 $($p.Sha)"
            exit 1
        }
        Write-Host ("  ok {0,-30} {1,11} {2}" -f $p.Name, $len, $sha)
    }
    Remove-Item -LiteralPath $vdir -Recurse -Force
    Write-Host "RELEASE_LIVE_OK $($parts.Count) parts at $baseUrl"
    exit 0
}

# ---- 1. build/pack/out must match the pins ----
Write-Host "checking build/pack/out against pack_spec.gd"
Assert-Parts $outDir "build/pack/out"
$sumsText = Get-SumsText
$outSums = Join-Path $outDir "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $outSums)) { throw "build/pack/out/SHA256SUMS.txt is missing: rebuild" }
if ([System.IO.File]::ReadAllText($outSums).Replace("`r`n", "`n") -ne $sumsText) {
    throw "pack_spec.gd and build/pack/out/SHA256SUMS.txt differ: rebuild"
}
Write-Host "build/pack/out/SHA256SUMS.txt matches pack_spec.gd"

# ---- 2. fresh staging folder ----
$stage = Join-Path $root "build/release/$tag"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
foreach ($p in $parts) { Copy-Item -LiteralPath (Join-Path $outDir $p.Name) -Destination $stage }
Write-Host "re-hashing the staged copies"
Assert-Parts $stage "build/release/$tag"
[System.IO.File]::WriteAllText((Join-Path $stage "SHA256SUMS.txt"), $sumsText, $utf8)

$rows = ($parts | ForEach-Object { "| {0} | {1:N0} | {2:N1} MB | ``{3}`` |" -f $_.Name, $_.Size, ($_.Size / 1e6), $_.Sha }) -join "`n"
$notes = @"
# UNDERTOW Autocharter pack v1

This is the optional download behind **Chart a Song** in UNDERTOW (v0.5.4 and later). The game downloads
these files itself the first time you use Chart a Song, checks every file against the size and SHA-256
built into the game, and installs them to ``%LOCALAPPDATA%\UNDERTOW\ac``. It holds a private Python
runtime, the charting app and its models (stem separation, beat tracking, pitch detection).

**Do not download these by hand unless the in-game download fails.** If it does: download every
``.zip`` below into one folder, then use **Chart a Song > Install from Folder...** and pick that folder.

| File | Bytes | Size | SHA-256 |
|------|-------|------|---------|
$rows

Total download: {0:N1} MB ({1:N0} bytes). About 0.94 GB on disk after installing.

Licences: see ``NOTICES/THIRD_PARTY.txt`` inside the app part (``undertow-ac-v1-app.zip``).
This pack contains no audio. Your music never leaves your PC.
"@ -f ($total / 1e6), $total
[System.IO.File]::WriteAllText((Join-Path $stage "RELEASE_NOTES.md"), $notes.Replace("`r`n", "`n") + "`n", $utf8)
Write-Host "staged $stage"

# ---- 3. D-16 durable archive outside the repo ----
$archive = Join-Path $ArchiveRoot $tag
$archSums = Join-Path $archive "SHA256SUMS.txt"
if (Test-Path -LiteralPath $archive) {
    if (Test-Path -LiteralPath $archSums) {
        if ([System.IO.File]::ReadAllText($archSums).Replace("`r`n", "`n") -ne $sumsText) {
            throw "$archive already holds a different SHA256SUMS.txt: refusing to overwrite the archived release (D-16)"
        }
        Write-Host "archive exists with the same SHA256SUMS.txt: refreshing and re-verifying"
    }
    elseif ((Get-ChildItem -LiteralPath $archive -Force | Measure-Object).Count -gt 0) {
        throw "$archive exists without SHA256SUMS.txt but is not empty: refusing to overwrite (D-16)"
    }
}
else {
    New-Item -ItemType Directory -Path $archive -Force | Out-Null
}
foreach ($p in $parts) {
    $dst = Join-Path $archive $p.Name
    if (-not (Test-Path -LiteralPath $dst) -or (Get-Item -LiteralPath $dst).Length -ne $p.Size -or (Get-Sha $dst) -ne $p.Sha) {
        Copy-Item -LiteralPath (Join-Path $stage $p.Name) -Destination $archive -Force
    }
}
Copy-Item -LiteralPath (Join-Path $stage "SHA256SUMS.txt") -Destination $archive -Force
Copy-Item -LiteralPath (Join-Path $stage "RELEASE_NOTES.md") -Destination $archive -Force
$manifest = Join-Path $outDir "pack_manifest.json"
if (Test-Path -LiteralPath $manifest) { Copy-Item -LiteralPath $manifest -Destination $archive -Force }
# The publish instructions travel with the archived bytes (not uploaded: kept out of the staging folder).
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "PACK-RELEASE.txt") -Destination $archive -Force
Write-Host "re-hashing the archive copy"
Assert-Parts $archive "the archive $archive"
if ([System.IO.File]::ReadAllText($archSums).Replace("`r`n", "`n") -ne $sumsText) {
    throw "archive SHA256SUMS.txt differs after copying"
}
Write-Host "archived $archive"

# ---- 4. publish command (printed only; nothing is uploaded) ----
$rel = "build/release/$tag"
$assets = (($names | ForEach-Object { "$rel/$_" }) + "$rel/SHA256SUMS.txt") -join " "
Write-Host ""
Write-Host "Publish (user action, see tools/autochart/PACK-RELEASE.txt):"
Write-Host "  gh release create $tag $assets --repo ccxmxrgo/undertow --title `"UNDERTOW Autocharter pack v1`" --notes-file $rel/RELEASE_NOTES.md --latest=false"
Write-Host "Then: powershell -NoProfile -File tools/autochart/release_pack.ps1 -VerifyPublished"
Write-Host ("RELEASE_STAGE_OK {0} parts {1:N1} MB" -f $parts.Count, ($total / 1e6))
