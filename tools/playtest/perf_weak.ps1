# Weak-GPU proxy capture for AV-05 / D-07 (05-07).
# Usage: powershell -NoProfile -File tools/playtest/perf_weak.ps1 [-Scenarios perf,versus] [-ProbeScenario a]
#
# Tries to run the perf and versus playtest scenarios on the Ryzen integrated GPU ("AMD Radeon(TM) Graphics")
# as a stand-in for a friend's weaker PC, then applies the D-07 gate to the Low-effects numbers:
#   solo  frame_ms_p95_low <= 16.7 ms and frame_ms_p99_low <= 20 ms
#   versus versus_perf_attribution.low_effects.p95 <= 16.7 ms and .p99 <= 20 ms
# Full-effects numbers on the proxy are printed as informative only.
#
# This script writes no registry or OS setting; only CLI flags and child-process env vars (orchestrator policy,
# overrides the D-07/A5 GPU-preference idea). Every attempt goes through tools/playtest/run_all.ps1, which keeps the
# player's user data backup/restore and SHA proof.
#
# The GPU actually used is read from the scenario JSON written by THIS attempt (stale JSON = no data) before any
# verdict. If no process-scoped option reaches the iGPU, the verdict is UNMEASURED. UNMEASURED is never a pass.
# Exit codes: 0 PASS, 4 FAIL, 3 UNMEASURED, 2 setup error.
param([string[]]$Scenarios = @("perf", "versus"), [string]$ProbeScenario = "a")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runAll = Join-Path $PSScriptRoot "run_all.ps1"
$outDir = Join-Path $root "build\playtest"
$weakDir = Join-Path $outDir "weak"
$IGPU = 'Radeon\(TM\) Graphics'
$DGPU = 'RX 9070'

# Attempts, in order. (c) a child-env adapter selector is only used if a documented, process-scoped variable exists.
# None is known: ANGLE's D3D11 adapter choice is an EGL attribute (EGL_PLATFORM_ANGLE_DEVICE_ID_*), not an env var;
# DXGI has no adapter-preference env var; and the Godot Windows exe exports AmdPowerXpressRequestHighPerformance /
# NvOptimusEnablement, which ask the driver for the high-performance GPU. So (c) is skipped.
$attempts = @(
    @{ Name = "a: ANGLE --gpu-index 1"; RenderingDriver = "opengl3_angle"; GpuIndex = 1; ChildEnv = @{} },
    @{ Name = "b: ANGLE --gpu-index 0"; RenderingDriver = "opengl3_angle"; GpuIndex = 0; ChildEnv = @{} }
)
Write-Host "[note] attempt c (child env adapter selector) skipped: no documented process-scoped variable selects the low-power adapter"

function Read-FreshJson([string]$scenario, [datetime]$since) {
    $p = Join-Path $outDir "$scenario.json"
    if (-not (Test-Path $p)) { return $null }
    if ((Get-Item $p).LastWriteTime -lt $since) { return $null }  # stale = no data
    try { return (Get-Content $p -Raw | ConvertFrom-Json) } catch { return $null }
}
function Get-Gpu($j) {
    if ($null -eq $j) { return "" }
    if ($j.metrics -and $j.metrics.gpu) { return [string]$j.metrics.gpu }
    if ($j.env -and $j.env.gpu) { return [string]$j.env.gpu }
    return ""
}
function Get-Driver($j) {
    if ($null -eq $j -or -not $j.env) { return "" }
    return [string]$j.env.render_driver
}
function Invoke-RunAll($a, [string[]]$scen) {
    # In-process call so -ChildEnv can pass a hashtable; Write-Host (stream 6) is folded in and filtered tersely.
    & $runAll -Scenarios $scen -RenderingDriver $a.RenderingDriver -GpuIndex $a.GpuIndex -ChildEnv $a.ChildEnv 6>&1 |
        ForEach-Object { "$_" } |
        Select-String -Pattern "^\[note\] switch|real user data|Scenarios failed|killed after" | ForEach-Object { $_.Line }
}

$seen = @()
$chosen = $null
foreach ($a in $attempts) {
    $t0 = Get-Date
    Write-Host "[note] probe $($a.Name) (scenario $ProbeScenario)"
    Invoke-RunAll $a @($ProbeScenario)
    $j = Read-FreshJson $ProbeScenario $t0
    $gpu = Get-Gpu $j
    $drv = Get-Driver $j
    if ($gpu -eq "") { $gpu = "<no fresh JSON>" }
    Write-Host ("[note] probe {0}: gpu='{1}' driver='{2}'" -f $a.Name, $gpu, $drv)
    $seen += "$gpu ($($a.Name), $drv)"
    if ($gpu -match $IGPU -and $gpu -notmatch $DGPU) { $chosen = $a; break }
}

if ($null -eq $chosen) {
    Write-Host ("WEAK PROXY UNAVAILABLE: integrated GPU not selectable with process-scoped flags ({0})" -f ($seen -join ", "))
    Write-Host "WEAK VERDICT: UNMEASURED"
    exit 3
}

Write-Host "[note] iGPU reached with $($chosen.Name); running $($Scenarios -join ',')"
$t1 = Get-Date
Invoke-RunAll $chosen $Scenarios   # run_all's exit code is ignored: the dGPU 4.35 ms gates fail on a weak GPU by design
New-Item -ItemType Directory -Force -Path $weakDir | Out-Null
$res = @{}
foreach ($s in $Scenarios) {
    $j = Read-FreshJson $s $t1
    if ($null -ne $j) {
        Copy-Item (Join-Path $outDir "$s.json") (Join-Path $weakDir "$s.json") -Force
        $res[$s] = $j
    }
}
# Every measured scenario must itself report the iGPU, or the run is not evidence.
foreach ($s in $Scenarios) {
    $g = Get-Gpu $res[$s]
    if (-not ($g -match $IGPU -and $g -notmatch $DGPU)) {
        Write-Host ("WEAK PROXY UNAVAILABLE: scenario {0} did not run on the integrated GPU (gpu='{1}')" -f $s, $g)
        Write-Host "WEAK VERDICT: UNMEASURED"
        exit 3
    }
}

$ok = $true
if ($res.ContainsKey("perf")) {
    $m = $res["perf"].metrics
    $p95 = [double]$m.frame_ms_p95_low; $p99 = [double]$m.frame_ms_p99_low
    Write-Host ("weak solo Low p95 {0:N3} ms (gate 16.7)" -f $p95)
    Write-Host ("weak solo Low p99 {0:N3} ms (gate 20.0)" -f $p99)
    Write-Host ("weak solo Full p95 {0:N3} p99 {1:N3} ms (informative)" -f [double]$m.frame_ms_p95_full, [double]$m.frame_ms_p99_full)
    if (-not ($p95 -le 16.7 -and $p99 -le 20.0)) { $ok = $false }
}
if ($res.ContainsKey("versus")) {
    $m = $res["versus"].metrics
    $le = $m.versus_perf_attribution.low_effects
    $p95 = [double]$le.p95; $p99 = [double]$le.p99
    Write-Host ("weak versus Low p95 {0:N3} ms (gate 16.7)" -f $p95)
    Write-Host ("weak versus Low p99 {0:N3} ms (gate 20.0)" -f $p99)
    Write-Host ("weak versus Full p95 {0:N3} p99 {1:N3} ms (informative)" -f [double]$m.versus_frame_ms_p95, [double]$m.versus_frame_ms_p99)
    if (-not ($p95 -le 16.7 -and $p99 -le 20.0)) { $ok = $false }
}
Write-Host ("[note] weak JSONs: {0}" -f $weakDir)
if ($ok) { Write-Host "WEAK VERDICT: PASS"; exit 0 }
Write-Host "WEAK VERDICT: FAIL"
exit 4
