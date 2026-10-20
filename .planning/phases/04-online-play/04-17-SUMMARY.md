---
phase: 04-online-play
plan: 17
subsystem: net-autotest
tags: [networking, smoke, autotest, enet, multi-process, drop, NET-01, NET-03, NET-04, NET-05]
requires: [NetSession match half (04-10), gameplay online branch (04-14), lobby hand-off pattern (04-15), --net-profile (04-03)]
provides:
  - "NetAutotest (src/net/net_autotest.gd): --net-autotest=host|client driver, parse_args, log_digest, compare_reports, JSON report"
  - "NetSession: autotest hook in _ready, debug_stats start_unix_ms + strike_kicks, match_channel(), last_results()"
  - "tools/net_smoke.ps1: 4 headless processes on 127.0.0.1, full + drop scenarios, PASS/FAIL summary, user-data SHA proof"
affects: [04-18]
tech-stack:
  added: []
  patterns: [one canonical SHA-256 per event stream (var_to_bytes of bytes_to_var(var_to_bytes(e))), report verdict shared between GDScript (unit tested) and PowerShell, process-tree kill plus command-line sweep for leftovers]
key-files:
  created:
    - src/net/net_autotest.gd
    - tests/test_net_autotest.gd
    - tools/net_smoke.ps1
  modified:
    - src/autoload/net_session.gd
decisions:
  - "The smoke processes run --headless with --audio-driver WASAPI and --mute (Master bus muted). Under the headless Dummy driver the Conductor locks onto a playback position that steps each process's song clock by a different 17-160 ms. That produced 188 late inputs. With WASAPI each song clock stays within +-13 ms of the schedule. The timing core is pinned, so the Dummy behaviour is documented, not changed. -AudioDriver Dummy is still available"
  - "Headless SongLibrary lists only the calibration chart, with or without --no-boot-scan (rescan() only runs with a display). NetAutotest rescans into a private songs root and cache under build/net_smoke/<scenario>/lib_<name>/. That root holds only the bundled songs. --no-boot-scan is kept so the real Songs folder and song_cache.json are never read or written"
  - "Profiles 71..74 (user://settings_net7x.cfg) instead of 1..4, so a player's own manual --net-profile files are never overwritten. The script deletes them afterwards"
  - "Settings are changed in memory only (player_name, calibration_done true so the first-launch wizard never starts, menu_music false). Nothing is saved"
  - "Host results come from NetSession.last_results() (what host_send_results sent). Client results come from the received RESULTS. Clients snapshot 1 s after RESULTS so the EVENTS that went out before RESULTS are drained into received_log. The host waits 2 s, then until every client has left (6 s at most)"
  - "The drop victim is found by name (C3), not by assumed seat. Clients start 0.4 s apart, so in practice C3 gets seat 3"
metrics:
  duration: "~1h15m"
  completed: 2026-10-20
  tasks: 2
  files: 4
requirements: [NET-01, NET-03, NET-04, NET-05]
---

# Phase 4 Plan 17: Autotest driver + 4-process localhost smoke Summary

A command-line driver, `--net-autotest=host|client`, plays a whole online match without the lobby UI: host, join, song pick, Ready, LOAD, gameplay with autoplay humans, DONE and RESULTS. It then writes a JSON report. `tools/net_smoke.ps1` runs 4 real headless Godot processes over real ENet on 127.0.0.1, plus a drop variant that kills one client mid-song. Both scenarios print **NET SMOKE OK**, repeatably (three consecutive green runs).

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | 8ea4c74 | feat(04-17): NetAutotest driver, NetSession autotest hook, report compare tests |
| 2 | 3fd60cd | feat(04-17): tools/net_smoke.ps1 4-process localhost smoke with drop scenario |

## Smoke results (last run, `powershell -NoProfile -File tools/net_smoke.ps1`, Seconds 30, easy, synth_wave_april)

**full** (HOST + C1..C3, 40.9 s wall):

```
[PASS] digest host == client C1 (364db79bf3e3f2ac, 142 events)
[PASS] digest host == client C2 (364db79bf3e3f2ac, 142 events)
[PASS] digest host == client C3 (364db79bf3e3f2ac, 142 events)
[PASS] start spread 3.270 ms <= 20      (offsets vs host: C1 +1.18, C2 +3.27, C3 +1.90 ms)
[PASS] late inputs 0
[PASS] no strike disconnects (ping overflow dropped: 0)
[PASS] results 4 rows (HOST, C1, C2, C3)
[note] HOST seat 0: RTT p50 0 p90 0, D 62 ms, landed_late_max 0.0, net skew 9.8 ms, song clock vs wall max 12.7 ms, WASAPI
[note] C1 seat 1: RTT p50 7 p90 7, D 62 ms, landed_late_max 0.0, net skew -4.4 ms, clock max 5.7 ms
[note] C2 seat 2: RTT p50 7 p90 7, D 62 ms, landed_late_max 0.0, net skew 2.3 ms, clock max 5.0 ms
[note] C3 seat 3: RTT p50 7 p90 7, D 62 ms, landed_late_max 0.0, net skew -2.9 ms, clock max 3.1 ms
```

**drop** (C3 killed with taskkill /T /F 14.4 s after launch, about 7 s into the song; 40.8 s wall):

```
[PASS] digest host == client C1 (d06218580e47c25f, 127 events)
[PASS] digest host == client C2 (d06218580e47c25f, 127 events)
[PASS] start spread 2.630 ms <= 20
[PASS] late inputs 0
[PASS] no strike disconnects
[PASS] results 4 rows (HOST, C1, C2)
[PASS] seat 3 LEFT (C3)                 (host left_seats: 3)
[note] C1: net skew -12.5 ms, clock max 13.2 ms; C2: net skew 0.9 ms, clock max 2.5 ms; D 62 ms
```

**Cleanup and data proof:**

```
[PASS] no leftover Godot processes
[PASS] real user data unchanged: settings.cfg ADF89140..., scores.cfg absent, drift_log.csv absent,
       song_cache.json 0DF16554..., songs/ entries=8 1CA38923...
NET SMOKE OK
```

Across 3 green runs the start spread was 2.1-3.4 ms. Each song clock stayed within 13.2 ms of the wall-clock schedule under WASAPI. Windows Firewall did not prompt for 127.0.0.1.

## What was built

**NetAutotest (`class_name NetAutotest`)**
- `has_arg`, `parse_args` (validated: role, address via Settings.clean_address, port 1024-65535, players 2-4, seconds 1-1200, diff, name, seed, timeout 10-3600, `--mute`). Defaults are HOST / C<profile-1> / CLIENT.
- `report_path` (T-04-49): the path must end in .json and contain no `..`, `.` or control characters. It must be either an absolute OS path or under `build/net_smoke/`. user:// and other schemes are rejected.
- `log_digest(events)`: one SHA-256 over `var_to_bytes(bytes_to_var(var_to_bytes(e)))` for each event, in order.
- `compare_reports(reports, {players, dropped_seat | dropped_name, max_spread_ms})`. Its rules are mirrored line for line in net_smoke.ps1.
- Flow:
  - **Host:** host(port) at once, then scan.
  - **Client:** scan, then join (5 retries on an early connect error), then Ready once the song is ok.
  - **Both:** match_loading builds the chart by fingerprint, sets `Gameplay.pending_chart` and changes to the gameplay scene. RESULTS, then report, then quit.
  - **Watchdog:** a report with `error: "timeout"`, then exit 3.
  - **Errors:** abort, host_left and left_lobby write a report with the error and exit 4.
- Report keys:
  - Required by the plan: role, seat, name, version, start_unix_ms, host_log_sha / received_sha, events, late_inputs, landed_late_max_ms, skew_ms, results_rows [{seat, name, left}], left_seats, error.
  - Extra: rtt_p50/p90_ms, horizon_ms, strike_kicks, ping_dropped, rejected_packets, clock_skew_max/last_ms, audio_driver.
- Prints `[autotest] ...` stage lines and a 1 Hz `clock t / wall / skew` line while playing.

**NetSession** (additive only)
- `_ready()` adds the driver only when `--net-autotest=` is present (T-04-51).
- `start_unix_ms` is set on the first decisive `lead_in_for_start` call (lead >= MIN_LEAD_S) and exposed in debug_stats. Cleared with the match.
- `strike_kicks` in `_stats` / debug_stats counts peers disconnected for strikes.
- `match_channel()` returns the bound NetHostChannel or NetClientChannel. `last_results()` returns the sent or received RESULTS.

## Tests

- test_net_autotest: 11/11.
  - parse_args: valid input, defaults, 9 rejected report paths including `../x.json` and `C:/Windows/x.txt`, 10 bad values.
  - log_digest: round trip gives the same digest; a changed int or float gives a different one.
  - compare_reports: all-match PASS; digest mismatch, 35 ms spread, late_inputs 2, error, strike, missing rows and missing report all FAIL; drop PASSes with left true and FAILs with left false; a partial dropped report is ignored.
- Regression: test_net_session_match 22/22, test_boot_smoke 1/1, test_net_session_lobby 26/26, test_online_gameplay 14/14, test_net_debug_rows 8/8.
- `tools/check_timing_gate.ps1`: TIMING GATE OK. No pinned timing file was touched.

## Deviations from Plan

1. **[Rule 3 - Blocking] The smoke uses `--audio-driver WASAPI` (muted).**
   - First run on the headless Dummy driver: digests matched and the start spread was 3.3 ms, but late_inputs was 188.
   - Per-process clock sampling showed each song clock jumps by a constant 17-160 ms (different per process) once the Conductor locks onto the Dummy driver's playback position.
   - The plan's rule (late_inputs == 0) was kept. The fix runs the real audio path instead: `-AudioDriver` defaults to WASAPI.
   - Every report records `audio_driver`, and the script notes any process that fell back to a different driver.
2. **[Rule 3] Library scan.** The plan asked to check whether bundled songs are listed under `--no-boot-scan`. In headless they are not listed, with or without the flag, because `rescan()` needs a display. NetAutotest scans into a private root under build/ (see decisions).
3. **[Rule 2] Extra safety and reporting:**
   - Profiles 71-74, removed after the run.
   - The leftover sweep: any process whose command line contains `--net-autotest=` is killed in `finally`.
   - song_cache.json and drift_log.csv were added to the SHA proof.
   - The strike_kicks counter backs the "any strike disconnect is a FAIL" rule.
   - The drop kill is timed from the victim's `[autotest] playing` line (Seconds/3 later) instead of a fixed Seconds/2 + 5 s from launch, so it always lands mid-song whatever the scan/join time.
4. **[Addition] `--net-seed`** (default 1717) makes the smoke match reproducible.

## Notes for 04-18

- `powershell -NoProfile -File tools/net_smoke.ps1` takes about 82 s for both scenarios. `-Scenario full|drop`, `-Seconds`, `-Port` and `-AudioDriver` are available. Reports are in build/net_smoke/<scenario>/*.json, and stdout per process is in <NAME>.out.txt (grep `[autotest] clock` for per-second skew).
- The smoke needs a working Windows audio endpoint (WASAPI). On a machine with no output device Godot falls back to Dummy, and late inputs will FAIL. Check the `audio` column of the [note] lines first.
- `landed_late_max_ms` was 0.0 on every client. On localhost with D 62 ms, LANDED events arrive before their landing time. The 30 s easy autoplay match yields 142 events (127 with the drop).
- RTT shows 7 ms on localhost. That is the frame-pumped ping (one process frame on each side), not ENet itself.
- Untracked `tests/test_lobby_screen.gd.uid` appeared after the import. It belongs to 04-15 and was not committed here.
- Ideas not done: a lossy-link variant (clumsy) and a 2-player LAN profile run. The 4 s watchdog path is covered by unit tests only (the drop here is a client loss, detected through the ENet peer timeout, 4-10 s).

## Known Stubs
None.

## Threat Flags
None beyond the register:
- T-04-49: report_path is validated and tested.
- T-04-50: per-process profiles, `--no-boot-scan`, a private library root under build/, and the SHA-256 before/after proof (PASS).
- T-04-51: the driver is instantiated only with `--net-autotest=`.

## Self-Check: PASSED
- src/net/net_autotest.gd (+ .uid), tests/test_net_autotest.gd (+ .uid), tools/net_smoke.ps1 and src/autoload/net_session.gd exist.
- Commits 8ea4c74 and 3fd60cd are on origin/main.
