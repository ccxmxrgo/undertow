# Build the Autocharter pack (Phase 2.2.2 plan 06; D-03, D-04, D-08, D-14, D-15, D-16).
# Usage (from anywhere):
#   powershell -NoProfile -File tools/autochart/build_pack.ps1                 full build -> build/pack/out
#   powershell -NoProfile -File tools/autochart/build_pack.ps1 -OutDir build/pack/out2   reproducibility build
#   powershell -NoProfile -File tools/autochart/build_pack.ps1 -AppOnly        rebuild only the app part
#
# Needs setup_venv.ps1 first (uv in build/autochart/boot/uv, venvA, build/autochart/pack_models).
# Steps: pinned standalone CPython (SHA-256 checked BEFORE extraction) -> rt/, hash-locked wheels
# (--no-deps --require-hashes, requirements-pack.txt) into rt/, VC++ runtime DLLs into rt/ (D-15),
# models (hashes re-checked) -> models/, then pack_build.py (prune, app, NOTICES, part zips, SHA256SUMS,
# PackSpec). Smoke: every part is extracted with Python zipfile into one fresh tree and the extracted
# pack must pass `app/autochart.py selftest` with its own interpreter.
#
# Only the default OutDir (build/pack/out) writes the game's src/autocharter/pack_spec.gd. Any other
# OutDir writes <OutDir>/pack_spec.gd, so a reproducibility build never changes the pins (D-16).
# Everything lands under build/pack (gitignored). Nothing is uploaded.

param(
    [switch]$AppOnly,
    [string]$OutDir = "build/pack/out"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pack = Join-Path $root "build/pack"
$stage = Join-Path $pack "stage"
$dl = Join-Path $pack "dl"
if ([System.IO.Path]::IsPathRooted($OutDir)) { $out = $OutDir } else { $out = Join-Path $root $OutDir }
$out = [System.IO.Path]::GetFullPath($out)
$defaultOut = [System.IO.Path]::GetFullPath((Join-Path $root "build/pack/out"))
$isDefault = ($out.TrimEnd('\', '/') -ieq $defaultOut.TrimEnd('\', '/'))
if ($isDefault) {
    $spec = Join-Path $root "src/autocharter/pack_spec.gd"
    $verifyRoot = Join-Path $pack "verify"
}
else {
    $spec = Join-Path $out "pack_spec.gd"
    $verifyRoot = Join-Path $pack ("verify-" + (Split-Path -Leaf $out))
}
$verify = Join-Path $verifyRoot "v1"

$ac = Join-Path $root "build/autochart"
$uv = Join-Path $ac "boot/uv/uv.exe"
$pyA = Join-Path $ac "venvA/Scripts/python.exe"
$packModels = Join-Path $ac "pack_models"
$reqP = Join-Path $root "tools/autochart/requirements-pack.txt"
$packBuild = Join-Path $root "tools/autochart/pack_build.py"
$parity = Join-Path $root "tools/autochart/reports/pack_bp_parity.json"
$indexArgs = @("--index-url", "https://download.pytorch.org/whl/cpu",
    "--extra-index-url", "https://pypi.org/simple",
    "--index-strategy", "unsafe-best-match")

# Pinned interpreter (RESEARCH Standard Stack, verified): python-build-standalone 20261009
$pyVersion = "3.12.15"
$pyUrl = "https://github.com/astral-sh/python-build-standalone/releases/download/20261009/cpython-3.12.15+20261009-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
$pySha = "11ed9f8a6ac64fb1b5a55e40e305a6744a3f77a70863c8f8197a6e4349abc64a"
$pyTar = Join-Path $dl "cpython-3.12.15+20261009-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"

# Model pins (README.txt MODEL HASHES)
$hdSha = "d9fa14133cfcc034a6758923bb3a8ca9f8dfd0b582134643bbf83f72c17576dd"
$ckSha = "8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331"
$hdRel = "hf/hub/models--adefossez--HTDemucs/snapshots/cbc8a9b1a87023b7fd74e7b3412e6321c0eab003/955717e8.safetensors"
$ckRel = "torch/hub/checkpoints/beat_this-final0.ckpt"

# VC++ 2015-2022 x64 runtime (D-15)
$vcDlls = @("msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll", "vcruntime140.dll", "vcruntime140_1.dll", "concrt140.dll")

$maxMB1 = 470
$maxMB2 = 600

function Invoke-Native {
    param([string]$Exe, [string[]]$ArgList)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Exe @ArgList 2>&1 | ForEach-Object { Write-Host "$_" }
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $old
    }
    if ($code -ne 0) { throw "command failed ($code): $Exe $($ArgList -join ' ')" }
}

# Same as Invoke-Native but returns stdout lines (stderr goes to the host).
function Invoke-Capture {
    param([string]$Exe, [string[]]$ArgList)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $lines = & $Exe @ArgList 2>$null
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $old
    }
    return @{ code = $code; lines = @($lines) }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Remove-Tree([string]$Path) {
    if (Test-Path -LiteralPath $Path) { Remove-Item -Recurse -Force -LiteralPath $Path }
}

foreach ($p in @($uv, $pyA, $reqP, $packBuild)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "missing $p (run tools/autochart/setup_venv.ps1 first)" }
}

$decision = (Get-Content -Raw -LiteralPath $parity | ConvertFrom-Json).decision
if ($decision -eq "merged") { $interpreters = 1 }
elseif ($decision -eq "two") { $interpreters = 2 }
else { throw "unknown interpreter decision '$decision' in $parity" }
if ($interpreters -eq 2) {
    # The parity spike (plan 01) decided "merged"; the 3.10 fallback interpreter is not pinned yet.
    throw "two-interpreter build requested by $parity but no rt310 pin exists in build_pack.ps1"
}
Write-Host "interpreter decision: $decision ($interpreters)"

New-Item -ItemType Directory -Force -Path $pack, $out | Out-Null
$env:UV_CACHE_DIR = Join-Path $ac "uvcache"

if ($AppOnly) {
    Invoke-Native $pyA @("-I", "-B", $packBuild, "--stage", $stage, "--out", $out, "--spec", $spec, "--app-only")
}
else {
    # (1) interpreter: hash BEFORE extraction (T-02.2.2-29)
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    if ((Test-Path -LiteralPath $pyTar) -and ((Get-Sha256 $pyTar) -ne $pySha)) { Remove-Item -Force -LiteralPath $pyTar }
    if (-not (Test-Path -LiteralPath $pyTar)) {
        Invoke-Native "curl.exe" @("-L", "--fail", "--silent", "--show-error", "-o", $pyTar, $pyUrl)
    }
    $got = Get-Sha256 $pyTar
    if ($got -ne $pySha) {
        Remove-Item -Force -LiteralPath $pyTar
        throw "CPython download hash mismatch (got $got, want $pySha)"
    }
    Write-Host "CPython $pyVersion archive sha256 ok"
    Remove-Tree $stage
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Invoke-Native (Join-Path $env:SystemRoot "System32/tar.exe") @("-xzf", $pyTar, "-C", $stage)
    $pyDir = Join-Path $stage "python"
    if (-not (Test-Path -LiteralPath (Join-Path $pyDir "python.exe"))) { throw "python/python.exe missing in $pyTar" }
    Rename-Item -LiteralPath $pyDir -NewName "rt"
    $rt = Join-Path $stage "rt"
    $rtPy = Join-Path $rt "python.exe"
    $v = Invoke-Capture $rtPy @("-I", "-c", "import sys; print(sys.version.split()[0])")
    if ($v.code -ne 0 -or ($v.lines -join "").Trim() -ne $pyVersion) { throw "stage interpreter reports '$($v.lines -join ' ')', want $pyVersion" }
    Write-Host "stage interpreter: $pyVersion"

    # (2) hash-locked wheels (T-02.2.2-30). --link-mode copy: the stage never hard-links into the uv cache.
    Invoke-Native $uv (@("pip", "install", "--python", $rtPy, "--no-deps", "--require-hashes", "--link-mode", "copy",
            "-r", $reqP) + $indexArgs)

    # (3) VC++ runtime (D-15). All six come from the ONE installed x64 redistributable, so rt/ never mixes
    #     versions (python-build-standalone ships an older vcruntime140*.dll pair; the newer redistributable
    #     files are backward compatible, which is how a system-wide redist install works too).
    foreach ($d in $vcDlls) {
        $src = Join-Path $env:SystemRoot "System32/$d"
        $dst = Join-Path $rt $d
        if (-not (Test-Path -LiteralPath $src)) { throw "VC++ runtime $d missing in System32 (install the VC++ 2015-2022 x64 redistributable)" }
        if (Test-Path -LiteralPath $dst) {
            Write-Host ("vcredist: replacing bundled {0} {1}" -f $d, (Get-Item -LiteralPath $dst).VersionInfo.FileVersion)
        }
        Copy-Item -Force -LiteralPath $src -Destination $dst
        Write-Host "vcredist: copied $d from System32"
    }
    foreach ($d in $vcDlls) {
        $f = Join-Path $rt $d
        Write-Host ("VCRT {0} {1} {2}" -f $d, (Get-Item -LiteralPath $f).VersionInfo.FileVersion, (Get-Sha256 $f))
    }

    # (4) models, hashes re-checked against the README pins (T-02.2.2-31)
    $h1 = Get-Sha256 (Join-Path $packModels $hdRel)
    if ($h1 -ne $hdSha) { throw "htdemucs model hash mismatch (got $h1, want $hdSha)" }
    $h2 = Get-Sha256 (Join-Path $packModels $ckRel)
    if ($h2 -ne $ckSha) { throw "beat_this final0 hash mismatch (got $h2, want $ckSha)" }
    Copy-Item -Recurse -LiteralPath $packModels -Destination (Join-Path $stage "models")
    if ((Get-Sha256 (Join-Path $stage "models/$hdRel")) -ne $hdSha -or (Get-Sha256 (Join-Path $stage "models/$ckRel")) -ne $ckSha) {
        throw "staged model hash mismatch"
    }
    Write-Host "models sha256 ok"

    # (5) prune, app, NOTICES, part zips, SHA256SUMS, PackSpec
    Invoke-Native $pyA @("-I", "-B", $packBuild, "--stage", $stage, "--out", $out, "--spec", $spec,
        "--interpreters", "$interpreters")
}

# (6) smoke: extract every part like the game does (one tree) and run the selftest with the pack interpreter
Remove-Tree $verifyRoot
New-Item -ItemType Directory -Force -Path $verify | Out-Null
$extract = @'
import json, sys, zipfile
from pathlib import Path
out, dest = Path(sys.argv[1]), Path(sys.argv[2])
m = json.loads((out / "pack_manifest.json").read_text(encoding="ascii"))
n = 0
for p in m["parts"]:
    with zipfile.ZipFile(out / p["name"]) as zf:
        for name in zf.namelist():
            if name.lower().endswith((".mp3", ".ogg", ".wav", ".flac", ".opus", ".m4a")):
                raise SystemExit("audio entry " + name)
        zf.extractall(dest)
        n += len(zf.namelist())
print("extracted", n, "files from", len(m["parts"]), "parts")
'@
$extractPy = Join-Path $pack "extract_parts.py"
[System.IO.File]::WriteAllText($extractPy, $extract)
Invoke-Native $pyA @("-I", "-B", $extractPy, $out, $verify)
foreach ($d in $vcDlls) {
    if (-not (Test-Path -LiteralPath (Join-Path $verify "rt/$d"))) { throw "extracted pack misses rt/$d (D-15)" }
}
$vPy = Join-Path $verify "rt/python.exe"
$vApp = Join-Path $verify "app/autochart.py"
$t0 = Get-Date
$st = Invoke-Capture $vPy @("-I", "-X", "utf8", "-u", $vApp, "selftest")
$secs = ((Get-Date) - $t0).TotalSeconds
$st.lines | ForEach-Object { Write-Host "selftest: $_" }
$ok = $false
foreach ($l in $st.lines) {
    try { $ev = $l | ConvertFrom-Json } catch { continue }
    if ($ev.ev -eq "selftest" -and $ev.ok -eq $true) { $ok = $true }
}
if ($st.code -ne 0 -or -not $ok) { throw ("extracted pack selftest failed (exit {0}); log {1}" -f $st.code, (Join-Path $verify "selftest_log.txt")) }
Write-Host ("SELFTEST_OK {0:N1} s (wall)" -f $secs)

# (7) size budget (D-14)
$m = Get-Content -Raw -LiteralPath (Join-Path $out "pack_manifest.json") | ConvertFrom-Json
$total = 0
foreach ($p in $m.parts) { $total += [int64]$p.size }
$totalMB = [math]::Round($total / 1e6, 1)
$limit = if ($m.interpreters -eq 2) { $maxMB2 } else { $maxMB1 }
Write-Host "total compressed: $totalMB MB (limit $limit MB), unpacked $([math]::Round([int64]$m.unpacked_bytes / 1e6, 1)) MB"
if ($totalMB -gt $limit) { throw "pack is $totalMB MB, over the $limit MB budget" }
Write-Host "SHA256SUMS: $(Join-Path $out 'SHA256SUMS.txt')"
Write-Host "spec: $spec"
Write-Output "PACK_BUILD_OK $totalMB"
