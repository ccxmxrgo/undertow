# Timing-core gate (Phase 2.2, T-02.2-02). Proves the five timing-core files are byte-identical to
# commit 72e21ce (the last commit that touched them before the visual phase) and have no uncommitted
# edits. Every 02.2 plan runs it in its verification.
# Usage: powershell -NoProfile -File tools/check_timing_gate.ps1
# Exit 0 + "TIMING GATE OK" when untouched; exit 1 + the diff + "TIMING GATE FAILED" otherwise.
$root = Split-Path -Parent $PSScriptRoot
$base = "72e21ce"
$paths = @(
    "src/core/conductor.gd",
    "src/core/clock_model.gd",
    "src/core/input_judge.gd",
    "src/core/judge_config.gd",
    "src/core/hull_score.gd"
)
Push-Location $root
try {
    $diff = (& git --no-pager diff --stat $base -- @paths) | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Host $diff; Write-Host "TIMING GATE FAILED (git diff error)"; exit 1 }
    $status = (& git status --porcelain -- @paths) | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Host $status; Write-Host "TIMING GATE FAILED (git status error)"; exit 1 }
    if ($diff.Trim() -eq "" -and $status.Trim() -eq "") {
        Write-Host "TIMING GATE OK"
        exit 0
    }
    if ($diff.Trim() -ne "") { Write-Host $diff.TrimEnd() }
    if ($status.Trim() -ne "") { Write-Host $status.TrimEnd() }
    Write-Host "TIMING GATE FAILED"
    exit 1
}
finally {
    Pop-Location
}
