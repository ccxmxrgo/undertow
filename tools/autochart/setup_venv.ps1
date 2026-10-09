# Idempotent bootstrap of the autochart Python environments (Phase 2.1, D-01).
# Usage (from anywhere): powershell -NoProfile -File tools/autochart/setup_venv.ps1
#
# Everything lands under build/autochart (gitignored); system Python 3.14 is never modified:
#   build/autochart/boot     bootstrap venv holding uv 0.12.24
#   build/autochart/pythons  uv-managed CPython 3.12.15 and 3.10.22
#   build/autochart/uvcache  uv package cache
#   build/autochart/venvA    Python 3.12: torch/torchaudio 2.11 cpu, demucs, beat_this, librosa 1.0 (requirements-a.txt)
#   build/autochart/venvB    Python 3.10: basic-pitch 0.4.0 + onnxruntime (requirements-b.txt)
#   build/autochart/cache    model cache (HF_HOME and TORCH_HOME point here for every tool run)
#
# Every autochart command must run with these env vars (the tools set them themselves too):
#   HF_HOME=build/autochart/cache  TORCH_HOME=build/autochart/cache  HF_HUB_DISABLE_SYMLINKS_WARNING=1
# They are honoured under `python -I` (verified in research). Always run Python as `python -I -B`.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ac = Join-Path $root "build/autochart"
$boot = Join-Path $ac "boot"
$uv = Join-Path $boot "Scripts/uv.exe"
$venvA = Join-Path $ac "venvA"
$venvB = Join-Path $ac "venvB"
$pyA = Join-Path $venvA "Scripts/python.exe"
$pyB = Join-Path $venvB "Scripts/python.exe"
$cache = Join-Path $ac "cache"
$reqA = Join-Path $root "tools/autochart/requirements-a.txt"
$reqB = Join-Path $root "tools/autochart/requirements-b.txt"

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

New-Item -ItemType Directory -Force -Path $ac | Out-Null

# (1) bootstrap uv with the system Python, inside its own venv
if (-not (Test-Path $uv)) {
    $sysPy = "C:/Python314/python.exe"
    if (Test-Path $sysPy) {
        Invoke-Native $sysPy @("-m", "venv", $boot)
    }
    else {
        Invoke-Native "py" @("-3.14", "-m", "venv", $boot)
    }
    Invoke-Native (Join-Path $boot "Scripts/python.exe") @("-m", "pip", "install", "--disable-pip-version-check", "uv==0.12.24")
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
Invoke-Native $uv @("pip", "install", "-p", $pyA, "-r", $reqA,
    "--index-url", "https://download.pytorch.org/whl/cpu",
    "--extra-index-url", "https://pypi.org/simple",
    "--index-strategy", "unsafe-best-match")

if (-not (Test-Path $pyB)) {
    Invoke-Native $uv @("venv", "-p", "3.10.22", $venvB)
}
Invoke-Native $uv @("pip", "install", "-p", $pyB, "-r", $reqB)

# (5) model cache: reuse the research downloads when present (htdemucs + beat_this final0 only)
if (-not (Test-Path $cache)) {
    $rc = Join-Path $root "build/research/cache"
    New-Item -ItemType Directory -Force -Path (Join-Path $cache "hub/checkpoints") | Out-Null
    $hd = Join-Path $rc "hf/hub/models--adefossez--HTDemucs"
    if (Test-Path $hd) {
        Copy-Item -Recurse -Force $hd (Join-Path $cache "hub")
        Write-Host "copied htdemucs weights from build/research/cache"
    }
    $ck = Join-Path $rc "torch/hub/checkpoints/beat_this-final0.ckpt"
    if (Test-Path $ck) {
        Copy-Item -Force $ck (Join-Path $cache "hub/checkpoints")
        Write-Host "copied beat_this final0 checkpoint from build/research/cache"
    }
}

# (6) report
Write-Host "venvA python: $pyA"
Write-Host "venvB python: $pyB"
Write-Output "AUTOCHART_ENV_OK"
