# Idempotent bootstrap of the autochart Python environments (Phase 2.1 D-01, Phase 2.2.2 Wave 0).
# Usage (from anywhere): powershell -NoProfile -File tools/autochart/setup_venv.ps1
#
# No system Python is needed or touched. uv 0.12.24 comes from its pinned GitHub release zip
# (SHA-256 checked before extraction). Everything lands under build/autochart (gitignored):
#   build/autochart/boot/uv     uv.exe from uv-x86_64-pc-windows-msvc.zip (0.12.24)
#   build/autochart/pythons     uv-managed CPython 3.12.15 and 3.10.22
#   build/autochart/uvcache     uv package cache
#   build/autochart/venvA       Python 3.12: torch/torchaudio 2.11 cpu, demucs, beat_this, librosa 1.0 (requirements-a.txt)
#   build/autochart/venvB       Python 3.10: basic-pitch 0.4.0 + onnxruntime (requirements-b.txt)
#   build/autochart/cache       model cache (HF_HOME and TORCH_HOME point here for every tool run)
#   build/autochart/pack_models models in the layout the runtime pack ships (HF_HOME=<models>/hf, TORCH_HOME=<models>/torch)
#
# Every autochart command must run with these env vars (the tools set them themselves too):
#   HF_HOME=build/autochart/cache  TORCH_HOME=build/autochart/cache  HF_HUB_DISABLE_SYMLINKS_WARNING=1
# They are honoured under `python -I` (verified in research). Always run Python as `python -I -B`.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ac = Join-Path $root "build/autochart"
$boot = Join-Path $ac "boot"
$uvDir = Join-Path $boot "uv"
$uvZip = Join-Path $boot "dl/uv-0.12.24.zip"
$uvUrl = "https://github.com/astral-sh/uv/releases/download/0.12.24/uv-x86_64-pc-windows-msvc.zip"
$uvSha = "7c38608c8a18ee137d748a1773053b07ec8f3a30fab49aebaa6f4e4efeceb019"
$uv = Join-Path $uvDir "uv.exe"
$venvA = Join-Path $ac "venvA"
$venvB = Join-Path $ac "venvB"
$pyA = Join-Path $venvA "Scripts/python.exe"
$pyB = Join-Path $venvB "Scripts/python.exe"
$cache = Join-Path $ac "cache"
$packModels = Join-Path $ac "pack_models"
$reqA = Join-Path $root "tools/autochart/requirements-a.txt"
$reqB = Join-Path $root "tools/autochart/requirements-b.txt"
$indexArgs = @("--index-url", "https://download.pytorch.org/whl/cpu",
    "--extra-index-url", "https://pypi.org/simple",
    "--index-strategy", "unsafe-best-match")

# Model pins (README.txt MODEL HASHES)
$hdSha = "d9fa14133cfcc034a6758923bb3a8ca9f8dfd0b582134643bbf83f72c17576dd"
$ckSha = "8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331"
$hdRepo = "models--adefossez--HTDemucs"
$hdSnap = "cbc8a9b1a87023b7fd74e7b3412e6321c0eab003"

# Run a native command without letting its stderr progress output become a terminating error.
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

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

New-Item -ItemType Directory -Force -Path $ac | Out-Null

# (1) bootstrap uv from the pinned GitHub release zip (no system Python; RESEARCH Pitfall 7).
#     The zip hash is checked BEFORE extraction; uv.exe only runs after the check (T-02.2.2-01).
if (-not (Test-Path $uv)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $uvZip) | Out-Null
    if (Test-Path $uvZip) { Remove-Item -Force $uvZip }
    Invoke-Native "curl.exe" @("-L", "--fail", "--silent", "--show-error", "-o", $uvZip, $uvUrl)
    $got = Get-Sha256 $uvZip
    if ($got -ne $uvSha.ToLowerInvariant()) {
        Remove-Item -Force $uvZip
        throw "uv download hash mismatch (got $got, want $uvSha)"
    }
    $tmp = Join-Path $boot "uv_extract"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive -LiteralPath $uvZip -DestinationPath $tmp -Force
    $found = Get-ChildItem -LiteralPath $tmp -Recurse -Filter "uv.exe" | Select-Object -First 1
    if ($null -eq $found) { throw "uv.exe not found in $uvZip" }
    if (Test-Path $uvDir) { Remove-Item -Recurse -Force $uvDir }
    Move-Item -LiteralPath $found.Directory.FullName -Destination $uvDir
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Write-Host "uv 0.12.24 bootstrapped from the pinned zip (sha256 ok)"
}

# (2) keep uv's cache and interpreters inside build/autochart
$env:UV_CACHE_DIR = Join-Path $ac "uvcache"
$env:UV_PYTHON_INSTALL_DIR = Join-Path $ac "pythons"

# (3) pinned interpreters (no-op when already installed). --no-bin: do not put python3.x.exe shims
#     into the user's ~/.local/bin (nothing outside build/autochart is touched)
Invoke-Native $uv @("python", "install", "--no-bin", "3.12.15", "3.10.22")

# (4) venvs: create only when missing, then sync the exact pins (fast no-op when satisfied)
if (-not (Test-Path $pyA)) {
    Invoke-Native $uv @("venv", "-p", "3.12.15", $venvA)
}
Invoke-Native $uv (@("pip", "install", "-p", $pyA, "-r", $reqA) + $indexArgs)

if (-not (Test-Path $pyB)) {
    Invoke-Native $uv @("venv", "-p", "3.10.22", $venvB)
}
Invoke-Native $uv @("pip", "install", "-p", $pyB, "-r", $reqB)

# (5b) model cache: reuse the hash-verified research copy of beat_this final0 when present.
#      htdemucs comes from the HF hub on the first analyze (it needs htdemucs.yaml + 955717e8.json +
#      the safetensors in the HF snapshot layout).
$ckDir = Join-Path $cache "hub/checkpoints"
$ck = Join-Path $ckDir "beat_this-final0.ckpt"
New-Item -ItemType Directory -Force -Path $ckDir | Out-Null
if (-not (Test-Path $ck)) {
    $rck = Join-Path $root "build/research-02.2.2/models/final0.ckpt"
    if ((Test-Path $rck) -and ((Get-Sha256 $rck) -eq $ckSha)) {
        Copy-Item -Force -LiteralPath $rck -Destination $ck
        Write-Host "copied beat_this final0 checkpoint from build/research-02.2.2/models (sha256 ok)"
    }
}

# (6) pack model layout: build/autochart/pack_models/{hf/hub/<htdemucs repo>, torch/hub/checkpoints/beat_this-final0.ckpt}
#     Both model hashes are checked against the README pins before the copy (T-02.2.2-03).
$hdCache = Join-Path $cache "hub/$hdRepo"
$hdFile = Join-Path $hdCache "snapshots/$hdSnap/955717e8.safetensors"
if ((Test-Path $hdFile) -and (Test-Path $ck)) {
    $h1 = Get-Sha256 $hdFile
    if ($h1 -ne $hdSha) { throw "htdemucs model hash mismatch (got $h1, want $hdSha)" }
    $h2 = Get-Sha256 $ck
    if ($h2 -ne $ckSha) { throw "beat_this final0 hash mismatch (got $h2, want $ckSha)" }
    if (Test-Path $packModels) { Remove-Item -Recurse -Force $packModels }
    $pmHub = Join-Path $packModels "hf/hub"
    $pmCk = Join-Path $packModels "torch/hub/checkpoints"
    New-Item -ItemType Directory -Force -Path $pmHub, $pmCk | Out-Null
    Copy-Item -Recurse -Force -LiteralPath $hdCache -Destination $pmHub
    Copy-Item -Force -LiteralPath $ck -Destination (Join-Path $pmCk "beat_this-final0.ckpt")
    $p1 = Get-Sha256 (Join-Path $pmHub "$hdRepo/snapshots/$hdSnap/955717e8.safetensors")
    $p2 = Get-Sha256 (Join-Path $pmCk "beat_this-final0.ckpt")
    if (($p1 -ne $hdSha) -or ($p2 -ne $ckSha)) { throw "pack_models copy hash mismatch" }
    if (-not (Test-Path (Join-Path $pmHub "$hdRepo/refs/main"))) { throw "pack_models: htdemucs refs/main missing" }
    Write-Output "PACK_MODELS_OK"
}
else {
    Write-Output "PACK_MODELS_PENDING (run one analyze first)"
}

# (7) report
Write-Host "uv: $uv"
Write-Host "venvA python: $pyA"
Write-Host "venvB python: $pyB"
Write-Output "AUTOCHART_ENV_OK"
