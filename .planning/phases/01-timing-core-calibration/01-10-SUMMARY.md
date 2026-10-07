---
phase: 01-timing-core-calibration
plan: 10
subsystem: playtest-verification
status: complete
gap_closure: true
tags: [godot, playtest, hardware, verification, gap-closure]
requires:
  - phase: 01-08
    provides: UiLayout.fill_rect overlays, ClockModel slew_tau_s 0.4 s, injectable drift log
  - phase: 01-09
    provides: AudioDeviceInfo snapshot/signature, System default readout, Previously saved caption, button widths
provides:
  - Harness assertions that would have caught gaps 1-6 (layout, device snapshot, smooth-clock D-30)
  - Real-hardware before/after numbers in 01-HARDWARE-PLAYTEST.md
  - Export that no longer packs build/playtest evidence
affects: [phase-01-verification]
key-files:
  created: []
  modified:
    - tools/playtest/playtest_driver.gd
    - tools/playtest/playtest.gd
    - tools/playtest/run_all.ps1
    - tools/export.ps1
    - export_presets.cfg
    - .planning/phases/01-timing-core-calibration/01-HARDWARE-PLAYTEST.md
key-decisions:
  - "clock_slew_tau_s stays 0.4 s: real-device drift-run p99 0.48 ms, no retune needed"
  - "D-30 harness reference is the smooth (fitted) audio clock; the instantaneous mix-chunk target is a recorded metric only"
  - "build/* excluded from export and build/.gdignore created, so playtest evidence never ships"
requirements-completed: []
metrics:
  tasks: "2 of 3 (Task 3 is a human checkpoint)"
  duration: ~35 min
  completed: 2026-10-07
---

# Phase 1 Plan 10: Gap closure re-verification on real hardware Summary

On the same 240 Hz WASAPI PC that found the gaps, all six playtest gaps are verified closed. Overlays are 1920x1080, dimmed and modal. Jitter between song_time and the smooth audio clock dropped from p99 3.84 to 0.48 ms (max 4.58 to 1.14 ms) over 5 minutes with no drift. The wizard reads "System default" with signature-based change detection. One shipping defect was found and fixed: the export was packing the playtest evidence.

## Tasks and commits

| Task | Commit | Result |
|------|--------|--------|
| 1 Harness assertions, unit suite, non-drift scenarios | 006ecf0 | 179/179 unit tests, 10/10 scenarios (191 checks) |
| (deviation) Export packs build/playtest | 801f007 | pck 29.6 MB -> 181 KB |
| 2 5-minute drift run and report update | 1db57ab | drift 10/10, report with Before/After and gap status |
| 3 Human-only checks | - | **awaiting checkpoint** |

## Final numbers (same PC as the original run)

| Measure | Before | After |
|---------|--------|-------|
| Overlay global rects (pause, fail, results, 3 confirms) | 0x0 | 1920x1080, dim alpha 0.70 (results 0.85), click at (5,5) blocked |
| Wizard readout | "Output device: Default" | "Output device: System default" + recalibration note |
| Saved device data | name "Default" only | name + signature equal to live snapshot (`...\|48000\|10\|8`) |
| drift_log.csv after unit suite | overwritten | marker survives |
| Jitter, scenario c (song_time - smooth audio clock) | std 1.84 / p99 3.85 / max 4.51 ms | std 0.19 / p99 0.46 / max 0.95 ms |
| Jitter, 5-min drift run | std 1.87 / p99 3.84 / max 4.58 ms | std 0.20 / p99 0.48 / max 1.14 ms (window p99 0.52/0.48/0.50/0.45/0.43) |
| Drift trend / clock rate | +0.04 ms/min / 0.38 ppm | -0.012 ms/min / -0.32 ppm |
| Pause resume landing (d / i) | +3.67 / +3.57 ms | +0.86 / +4.14 ms (within one 4.17 ms frame) |
| Wizard buttons | 1760 px | 280-320 px |
| Re-run display | "+40 MS" only (checklist said "near 0") | "+41 MS" with "Previously saved: +41 MS" (residual +0.77 ms) |

The 0.4 s clock time constant did not hurt pause resume (scenarios d and i pass; countdown 1.801 s vs 1.800 s).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, harness] The drift D-30 check used the instantaneous audio target as its reference**
- **Found during:** Task 1 (reading scenario j)
- **Issue:** The old checks compared song_time with the per-frame audio target, which itself steps in 10.67 ms mix chunks (std 3.1 ms, max 17 ms). So ±2 ms could never pass, whatever the smoothing.
- **Fix:** The reference is now the fitted smooth audio clock, as in analyze_probe.py and as the plan specifies. The threshold is unchanged at 2.0 ms, and the strict max check is kept against that reference. Added per-window p99, trend (<= 0.5 ms/min) and ppm (<= 100) checks. The instantaneous figure is still recorded as a metric. No tolerance was loosened.
- **Commit:** 006ecf0

**2. [Rule 2 - Missing critical, T-10-01] run_all.ps1 now backs up and restores the real settings.cfg and drift_log.csv**
- The drift scenario writes the real `user://drift_log.csv` through the shipped harness. The real file (header only) was also backed up by hand to the scratchpad and is restored and unchanged.
- **Commit:** 006ecf0

**3. [Rule 1 - Bug, shipping] The exported build packed the playtest evidence**
- **Found during:** Task 2 re-export for scenario k
- **Issue:** The pck grew from 176 KB to 29.6 MB. `include_filter="*.json"` and `all_resources` picked up 79 files from `build/playtest`: JSON with the env and device list, probe CSVs that Godot had auto-imported as translations, and screenshots. Friends would have received this data.
- **Fix:** `exclude_filter` now includes `build/*`. `tools/export.ps1` and the playtest driver create `build/.gdignore`. The stale `.import`/`.translation` files in build/playtest (gitignored) were deleted. Re-export: pck 181 KB, 0 `build/` files, boots into the wizard with clean stdout.
- **Files:** export_presets.cfg, tools/export.ps1, tools/playtest/playtest_driver.gd
- **Commit:** 801f007

No product code in src/ was changed. `clock_slew_tau_s` and judge_config were not touched.

## Verification

- `tools/run_tests.ps1`: 179 test cases, 0 failures, 0 orphans, exit 0. A marker line in the real drift_log.csv survived.
- `tools/playtest/run_all.ps1 -SkipDrift`: `Scenarios failed: 0` (a 40, b 14, c 9, d 24, e 12, f 7, g 18, h 15, i 13, layout 39). Scenario f was re-run after the .gdignore edit and passed again.
- `run_all.ps1 -Scenarios drift`: 10/10; `analyze_probe.py` song_time - smooth audio clock p99_abs 0.477 ms.
- `grep -n "AudioServer.output_device" tools/playtest/playtest_driver.gd`: only the env_info line (112).
- Real `user://settings.cfg` still absent; real `user://drift_log.csv` restored (header only, as before).
- Report greps: 15 "CLOSED", checklist row 1 mentions "Previously saved" and does not contain "near 0", 3.84 and 0x0 appear in the Before column.

## Human checkpoint (Task 3) - pending

Remaining human-only items: feel and on-beat after calibration on this PC, full-size overlays by eye, the Windows default-output switch (documented limitation, no prompt expected), a physical gamepad, the second-PC export (D-31), and optionally by-eye drift. The reply will be appended to 01-HARDWARE-PLAYTEST.md under "Human results".

## Known Stubs

None.

## Deferred / notes

- `.planning/config.json` (`_auto_chain_active` true -> false) was already modified before this plan and was left alone.

## Self-Check: PASSED

Commits 006ecf0, 801f007 and 1db57ab exist. The files tools/playtest/playtest_driver.gd, tools/playtest/run_all.ps1, export_presets.cfg and 01-HARDWARE-PLAYTEST.md exist and were modified. The evidence files build/playtest/layout.json, a.json, drift.json, drift_before.json and k_01_export_boot_desktop.png are present (build/ is gitignored).

## Human Results (Task 3)

2026-10-07: the user replied "approved" to the hands-on checklist (feel on the dev PC, gamepad, second PC, output switch). No issues were reported. No specific numbers were given (audio offset, second-PC device line).
