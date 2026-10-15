# Timing-core gate (Phase 2.2, T-02.2-02, T-02.2-49). Proves the five timing-core files are
# byte-identical to their pinned baselines and have no uncommitted edits. Every 02.2 plan runs it
# in its verification.
#
# Two baselines:
#   1. conductor.gd, clock_model.gd, input_judge.gd, hull_score.gd -> $base = 72e21ce (the last
#      commit that touched them before the visual phase).
#   2. judge_config.gd -> $judgeBase (was fbcf994, now 2c2e54c). 02.2 UAT gap G1: on 2026-10-11 the user approved
#      widening the judge windows to Perfect 50 / Good 100 / early-miss 130 ms. Commit fbcf994
#      changes exactly those three defaults; the gate is re-baselined to it for that file only.
#      03-SPEC req 14 (D-29): on 2026-10-08 the user approved perfect_regen 1.0 -> 0.25. Commit
#      2c2e54c changes exactly that default; the judge windows (50/100/130 ms) are unchanged. The
#      gate is re-baselined to it for judge_config.gd only.
# Any further edit of any of the five files (committed or not) fails the gate again.
#
# Usage: powershell -NoProfile -File tools/check_timing_gate.ps1
# Exit 0 + "TIMING GATE OK" when untouched; exit 1 + the diff + "TIMING GATE FAILED" otherwise.
$root = Split-Path -Parent $PSScriptRoot
$base = "72e21ce"
$judgeBase = "2c2e54c"
$groups = @(
    @{ Base = $base; Paths = @(
        "src/core/conductor.gd",
        "src/core/clock_model.gd",
        "src/core/input_judge.gd",
        "src/core/hull_score.gd"
    ) },
    @{ Base = $judgeBase; Paths = @(
        "src/core/judge_config.gd"
    ) }
)
Push-Location $root
try {
    $failed = $false
    foreach ($g in $groups) {
        $paths = $g.Paths
        $diff = (& git --no-pager diff --stat $g.Base -- @paths) | Out-String
        if ($LASTEXITCODE -ne 0) { Write-Host $diff; Write-Host "TIMING GATE FAILED (git diff error)"; exit 1 }
        $status = (& git status --porcelain -- @paths) | Out-String
        if ($LASTEXITCODE -ne 0) { Write-Host $status; Write-Host "TIMING GATE FAILED (git status error)"; exit 1 }
        if ($diff.Trim() -ne "") { Write-Host ("vs " + $g.Base + ":"); Write-Host $diff.TrimEnd(); $failed = $true }
        if ($status.Trim() -ne "") { Write-Host $status.TrimEnd(); $failed = $true }
    }
    if (-not $failed) {
        Write-Host "TIMING GATE OK"
        exit 0
    }
    Write-Host "TIMING GATE FAILED"
    exit 1
}
finally {
    Pop-Location
}
