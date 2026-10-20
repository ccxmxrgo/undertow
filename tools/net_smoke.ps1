# Online smoke test (04-17, D-24 layer 4): real headless Godot processes over real ENet on 127.0.0.1.
# Usage: powershell -NoProfile -File tools/net_smoke.ps1 [-Scenario full|drop|both] [-Port 47591] [-Seconds 30] [-Lossy 0.05]
#
# -Lossy p (IN-03, 0..0.2): client C1 runs with --net-lossy=p (ENetTransport emulates a lossy link: a lost
# reliable packet is held 50-150 ms with head-of-line blocking, then bursts; unreliable packets drop). The
# digests must still match and no peer may be strike-kicked; late inputs are then expected and only noted.
#
# Scenarios:
#   full  1 host + 3 clients. The host waits for 4 seats, picks the first bundled song (easy), the clients
#         Ready up, and the match runs with every human on autoplay for -Seconds (max_song_s) to results.
#   drop  the same, but client C3 is killed (taskkill /T /F) mid-song: Seconds/3 after its "[autotest] playing"
#         line. The host's results must mark that seat LEFT and the other clients' digests must still match.
# Each process runs NetAutotest (src/net/net_autotest.gd) with `-- --net-autotest=host|client ...` and writes
# a JSON report. PASS rules (same as NetAutotest.compare_reports): no report error and one game version;
# every client's received_sha == the host's host_log_sha (canonical SHA-256 of the event stream); the
# start_unix_ms spread <= 20 ms; host late_inputs == 0; no strike disconnect; every results table has
# 4 rows; for drop, the dropped seat is LEFT in the host results.
#
# Outputs: build/net_smoke/<scenario>/{host,c1,c2,c3}.json, <NAME>.out.txt / <NAME>.err.txt (stdout/stderr
# per process), lib_<name>/ (each process's private bundled-song scan and cache). build/ is gitignored.
#
# Player data proof (T-04-50): each process uses its own settings file via --net-profile=71..74
# (user://settings_net7x.cfg, removed afterwards) and --no-boot-scan, so the real Songs folder and song cache
# are never scanned or written. SHA-256 of the real settings.cfg, scores.cfg, drift_log.csv and
# song_cache.json (plus a listing of the real songs/ folder) is taken before and after; any change is a FAIL.
#
# Audio: processes run --headless with --audio-driver WASAPI (default; -AudioDriver Dummy to override) and
# --mute (Master bus muted, so nothing is heard). Under the headless Dummy driver the Conductor locks onto a
# playback position that steps each process's song clock by a different 20-160 ms, which shows up as late
# inputs; the real driver is the path friends use (measured skew within +-16 ms of the schedule).
#
# Watchdogs: every process gets --net-timeout=Seconds+60 (it writes an error report and exits 3); the script
# waits at most Seconds+90 s per scenario, kills stragglers with taskkill /T /F ([FAIL]), and its finally
# block kills every process it started plus any leftover process whose command line has --net-autotest.
param([ValidateSet("full", "drop", "both")][string]$Scenario = "both", [int]$Port = 47591, [int]$Seconds = 30, [ValidateSet("WASAPI", "Dummy")][string]$AudioDriver = "WASAPI", [double]$Lossy = 0.0)

$godot = $env:GODOT_BIN
if (-not $godot) { $godot = [Environment]::GetEnvironmentVariable("GODOT_BIN", "User") }
if (-not $godot -or -not (Test-Path $godot)) {
    Write-Error "GODOT_BIN is not set or does not exist. Point it at Godot_v4.7.2-stable_win64_console.exe"
    exit 2
}
$root = Split-Path -Parent $PSScriptRoot
$userDir = Join-Path $env:APPDATA "Godot\app_userdata\UNDERTOW"
$protected = @("settings.cfg", "scores.cfg", "drift_log.csv", "song_cache.json")
$realSongs = Join-Path $userDir "songs"
$names = @("HOST", "C1", "C2", "C3")
$profiles = @(71, 72, 73, 74)
$players = 4
$maxSpreadMs = 20.0

function Get-UserDataProof {
    $lines = @()
    foreach ($f in $protected) {
        $p = Join-Path $userDir $f
        if (Test-Path $p) { $lines += "$f " + (Get-FileHash -Algorithm SHA256 $p).Hash } else { $lines += "$f absent" }
    }
    if (Test-Path $realSongs) {
        $items = @(Get-ChildItem -Recurse -Force $realSongs | ForEach-Object { "{0}|{1}|{2}" -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks })
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((($items | Sort-Object) -join ";"))
        $lines += "songs/ entries=$($items.Count) " + [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "")
    } else { $lines += "songs/ absent" }
    return $lines
}

function Stop-Tree([System.Diagnostics.Process]$p) {
    if ($null -ne $p -and -not $p.HasExited) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null }
}

function Stop-Leftovers {
    # Safety net: any Godot still running with --net-autotest (e.g. the GUI child of a killed wrapper).
    $left = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like "*--net-autotest=*" })
    foreach ($q in $left) { & taskkill.exe /T /F /PID $q.ProcessId 2>&1 | Out-Null }
    return $left.Count
}

$script:failed = 0
function Pass([string]$m) { Write-Host "[PASS] $m" }
function Fail([string]$m) { Write-Host "[FAIL] $m"; $script:failed++ }
function Note([string]$m) { Write-Host "[note] $m" }

function Test-Reports([string]$dir, [string]$droppedName) {
    $reports = @()
    foreach ($f in @(Get-ChildItem -Path $dir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        try { $reports += (Get-Content -Raw $f.FullName | ConvertFrom-Json) } catch { Fail "unreadable report $($f.Name)" }
    }
    $host_ = $null
    $clients = @()
    foreach ($r in $reports) {
        if ($droppedName -ne "" -and $r.role -ne "host" -and $r.name -eq $droppedName) { Note "dropped client report ignored ($($r.name))"; continue }
        if ($r.role -eq "host") { $host_ = $r } else { $clients += $r }
    }
    if ($null -eq $host_) { Fail "host report missing"; return }
    $want = $players - 1
    if ($droppedName -ne "") { $want-- }
    if ($clients.Count -ne $want) { Fail ("client reports {0} (want {1})" -f $clients.Count, $want) }
    $all = @($host_) + $clients
    foreach ($r in $all) {
        if ("$($r.error)" -ne "") { Fail "$($r.name) error: $($r.error)" }
        if ("$($r.version)" -ne "$($host_.version)") { Fail "$($r.name) version $($r.version) != host $($host_.version)" }
    }
    $hsha = "$($host_.host_log_sha)"
    foreach ($c in $clients) {
        if ($hsha -ne "" -and "$($c.received_sha)" -eq $hsha) {
            Pass ("digest host == client {0} ({1}, {2} events)" -f $c.name, $hsha.Substring(0, 16), $c.events)
        } else {
            Fail ("digest host {0} ({1} events) != client {2} {3} ({4} events)" -f $hsha, $host_.events, $c.name, $c.received_sha, $c.events)
        }
    }
    $starts = @()
    foreach ($r in $all) {
        $s = [double]$r.start_unix_ms
        if ($s -le 0) { Fail "$($r.name) has no start_unix_ms" } else { $starts += $s }
    }
    if ($starts.Count -gt 0) {
        $lo = ($starts | Measure-Object -Minimum).Minimum
        $hi = ($starts | Measure-Object -Maximum).Maximum
        $spread = $hi - $lo
        $msg = "start spread {0:N3} ms" -f $spread
        if ($spread -le $maxSpreadMs) { Pass "$msg <= 20" } else { Fail "$msg > 20" }
        foreach ($r in $all) { Note ("{0} start offset vs host {1:N3} ms" -f $r.name, ([double]$r.start_unix_ms - [double]$host_.start_unix_ms)) }
    }
    if ([int]$host_.late_inputs -eq 0) { Pass "late inputs 0" } elseif ($Lossy -gt 0) { Note "late inputs $($host_.late_inputs) (lossy link: clamped, expected)" } else { Fail "late inputs $($host_.late_inputs)" }
    if ([int]$host_.strike_kicks -ne 0) { Fail "strike disconnects $($host_.strike_kicks)" } else { Pass "no strike disconnects (ping overflow dropped: $($host_.ping_dropped))" }
    foreach ($r in $all) {
        $n = @($r.results_rows).Count
        if ($n -eq $players) { Pass "results $n rows ($($r.name))" } else { Fail "results $n rows ($($r.name)), want $players" }
    }
    if ($droppedName -ne "") {
        $row = @($host_.results_rows) | Where-Object { $_.name -eq $droppedName } | Select-Object -First 1
        if ($null -ne $row -and $row.left -eq $true) { Pass "seat $($row.seat) LEFT ($droppedName)" }
        else { Fail "dropped $droppedName not LEFT in the host results" }
        Note ("host left_seats: {0}" -f (@($host_.left_seats) -join ","))
    }
    foreach ($r in $all) {
        Note ("{0} seat {1}: RTT p50 {2} ms p90 {3} ms, D {4} ms, landed_late_max {5:N1} ms, net skew {6:N1} ms, song clock vs wall max {7:N1} ms, events {8}, rejected {9}, audio {10}" -f `
            $r.name, $r.seat, $r.rtt_p50_ms, $r.rtt_p90_ms, $r.horizon_ms, [double]$r.landed_late_max_ms, [double]$r.skew_ms,
            [double]$r.clock_skew_max_ms, $r.events, $r.rejected_packets, $r.audio_driver)
        # The Dummy driver's playback position steps the song clock 20-160 ms per process (headless artifact;
        # the timing core is pinned), so late_inputs is only meaningful on a real driver.
        if ("$($r.audio_driver)" -ne "" -and "$($r.audio_driver)" -ne "WASAPI") { Note "$($r.name) ran on audio driver '$($r.audio_driver)', not WASAPI" }
    }
}

$proofBefore = Get-UserDataProof
$started = New-Object System.Collections.ArrayList
Push-Location $root
try {
    if (-not (Test-Path ".godot")) { & $godot --headless --path . --import 2>&1 | Out-Null }
    $list = if ($Scenario -eq "both") { @("full", "drop") } else { @($Scenario) }
    $k = 0
    foreach ($sc in $list) {
        Write-Host "== scenario $sc =="
        $dir = Join-Path $root "build\net_smoke\$sc"
        if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $port = $Port + $k
        $k++
        $procs = @{}
        $t0 = Get-Date
        for ($i = 0; $i -lt $names.Count; $i++) {
            $name = $names[$i]
            $role = if ($i -eq 0) { "host" } else { "client" }
            $report = (Join-Path $dir ("{0}.json" -f $name.ToLower())).Replace("\", "/")
            $a = @("--headless", "--audio-driver", $AudioDriver, "--path", ".", "--", "--net-autotest=$role", "--net-players=$players", "--net-port=$port",
                "--net-seconds=$Seconds", "--net-profile=$($profiles[$i])", "--net-name=$name", "--net-timeout=$($Seconds + 60)",
                "--mute", "--no-boot-scan", "--net-report=$report")
            if ($role -eq "client") { $a += "--net-address=127.0.0.1" }
            if ($Lossy -gt 0 -and $name -eq "C1") { $a += ("--net-lossy={0}" -f $Lossy.ToString([Globalization.CultureInfo]::InvariantCulture)) }
            $p = Start-Process -FilePath $godot -ArgumentList $a -NoNewWindow -PassThru `
                -RedirectStandardOutput (Join-Path $dir "$name.out.txt") -RedirectStandardError (Join-Path $dir "$name.err.txt")
            $null = $p.Handle  # keeps ExitCode readable after exit
            $procs[$name] = $p
            [void]$started.Add($p)
            if ($i -eq 0) { Start-Sleep -Milliseconds 1500 } else { Start-Sleep -Milliseconds 400 }
        }
        $dropped = ""
        if ($sc -eq "drop") {
            $victim = $names[3]
            $out = Join-Path $dir "$victim.out.txt"
            $limit = (Get-Date).AddSeconds($Seconds + 60)
            $playing = $false
            while ((Get-Date) -lt $limit -and -not $procs[$victim].HasExited) {
                if ((Test-Path $out) -and (Select-String -Path $out -Pattern "\[autotest\] playing" -Quiet)) { $playing = $true; break }
                Start-Sleep -Milliseconds 250
            }
            if ($playing) {
                Start-Sleep -Milliseconds ([int]($Seconds * 1000 / 3))
                Stop-Tree $procs[$victim]
                $dropped = $victim
                Note ("killed {0} (pid {1}) {2:N1} s after start" -f $victim, $procs[$victim].Id, ((Get-Date) - $t0).TotalSeconds)
            } else {
                Fail "$victim never reached playing; not dropped"
            }
        }
        $deadline = $t0.AddSeconds($Seconds + 90)
        foreach ($name in $names) {
            $p = $procs[$name]
            if ($name -eq $dropped) { continue }
            $ms = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
            if (-not $p.WaitForExit($ms)) {
                Fail "$name stalled; killed after $($Seconds + 90) s"
                Stop-Tree $p
            } else {
                $p.WaitForExit()
                if ($p.ExitCode -ne 0) { Fail "$name exit code $($p.ExitCode)" }
            }
            Select-String -Path (Join-Path $dir "$name.out.txt") -Pattern "^\[autotest\] (FAIL|report|loading|playing)" -ErrorAction SilentlyContinue |
                ForEach-Object { Note ("{0}: {1}" -f $name, $_.Line) }
        }
        Note ("scenario {0} took {1:N1} s" -f $sc, ((Get-Date) - $t0).TotalSeconds)
        Test-Reports $dir $dropped
    }
}
finally {
    foreach ($p in $started) { Stop-Tree $p }
    $n = Stop-Leftovers
    if ($n -gt 0) { Fail "$n leftover --net-autotest process(es) killed" } else { Pass "no leftover Godot processes" }
    foreach ($pr in $profiles) {
        $f = Join-Path $userDir "settings_net$pr.cfg"
        if (Test-Path $f) { Remove-Item -Force $f }
    }
    $proofAfter = Get-UserDataProof
    for ($i = 0; $i -lt $proofBefore.Count; $i++) {
        if ($proofBefore[$i] -eq $proofAfter[$i]) { Pass "real user data unchanged: $($proofAfter[$i])" }
        else { Fail "real user data CHANGED: before '$($proofBefore[$i])' after '$($proofAfter[$i])'" }
    }
    Pop-Location
}
if ($script:failed -eq 0) { Write-Host "NET SMOKE OK" } else { Write-Host "NET SMOKE FAILED ($($script:failed))" }
exit $script:failed
