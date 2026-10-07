---
phase: 01-timing-core-calibration
plan: 04
subsystem: input-settings-calibration
tags: [godot, gdscript, input-map, rebinding, analog-trigger, settings, calibration-math]
requires:
  - phase: 01-02
    provides: Settings autoload, LaneInput, InputJudge, Conductor
provides:
  - BindingStore (validated rebind, serialize, reset for 7 gameplay actions)
  - Default InputMap in project.godot (keyboard + gamepad, triggers axis_value 1.0, deadzone 0.5)
  - Settings: bindings, scroll snap, Master/Music/SFX volumes, early/late, no_fail, reduce_motion, settings_changed
  - Edge-detecting LaneInput (lane_pressed / lane_released, trigger hysteresis, enabled flag)
  - CalibrationMath (median tap offset), DeviceHeuristics (Bluetooth name check)
affects: [01-05, 01-06, 01-07]
tech-stack:
  added: []
  patterns: [InputMap as live truth with BindingStore (de)serializing it, hysteresis digitizing of analog triggers, pure static calibration math]
key-files:
  created:
    - src/input/binding_store.gd
    - src/core/calibration_math.gd
    - src/core/device_heuristics.gd
    - tests/test_bindings.gd
    - tests/test_settings.gd
    - tests/test_lane_input.gd
    - tests/test_calibration_math.gd
    - tests/test_bt_heuristic.gd
  modified:
    - project.godot
    - src/autoload/settings.gd
    - src/input/lane_input.gd
key-decisions:
  - "Bindings serialize per action as <action>_key (physical_keycode int) and <action>_pad (button int or [axis, 1] for triggers)"
  - "Invalid or duplicate file entries revert only that action to its default; any residual duplicate resets to defaults"
  - "Trigger lanes press at >= 0.5 and release at <= 0.4 (hysteresis)"
  - "remove_applied_offset(tap, applied) = tap + applied converts offset-adjusted song-time taps back to raw time"
  - "Settings.save_path member lets set_* mutators and tests persist to a non-default file"
requirements-completed: [CAL-01, CAL-02, CAL-03, CAL-04]
duration: ~35min
completed: 2026-10-07
---

# Phase 1 Plan 04: Input, Settings and Calibration Logic Summary

Tested engine for CAL-01..04: validated runtime rebinding persisted in settings.cfg, edge-detecting lane input that turns analog triggers into single press/release events, scroll and volume settings driving AudioServer buses, median-based calibration math and a Bluetooth name heuristic. UI is plan 07.

## Tasks

| Task | Name | Commits |
|------|------|---------|
| 1 | BindingStore, default input map, extended Settings | 41746d0 (RED), e62a519 (GREEN) |
| 2 | Edge-detecting LaneInput, CalibrationMath, DeviceHeuristics | 62da893 (RED), ed8365f (GREEN) |

## Verification

- `powershell -NoProfile -File tools/run_tests.ps1` exits 0: 102 test cases in 16 suites, 0 failures (includes the five new suites).
- Trigger stream 0.0, 0.3, 0.6, 0.8, 0.9, 0.4, 0.0 gives exactly one press and one release; noise around 0.5 does not chatter.
- +37 ms synthetic tapper recovered within 1 ms (16 clicks at 100 BPM, 4 discarded, median); outliers do not move it; fewer than 8 remaining taps returns NAN; re-measurement after applying returns about 0.
- `KEY_TAB` appears once in `binding_store.gd` (the RESERVED check) and never in `project.godot`; `linear_to_db` present in settings.gd.

## Deviations from Plan

**1. [Rule 1 - Bug] Keycode validity mask excluded KEY_SPECIAL**
- Found during: Task 1 GREEN run. First mask (0x3FFFFF) classed Tab/Escape as INVALID; corrected to KEY_CODE_MASK (0x7FFFFF).
- Commit: e62a519.

**2. [Rule 1 - Bug] `ConfigFile.get_value(..., null)` logs an error for absent keys**
- Switched to `has_section_key` guards in `BindingStore.from_config`. Commit: ed8365f.

**3. Additions beyond the file list:** `Settings.save_path` and `set_scroll_speed()` (needed for testable persistence and UI wiring); `LaneInput.lane_released` signal and `inject()` test seam; `.uid` files for new scripts.

**4. Lane deadzone changed 0.2 to 0.5** for all seven actions per D-19 (buttons and keys are unaffected).

## Known Stubs

None.

## Threat Flags

None. T-04-01 (typed/clamped/validated file values, per-action fallback), T-04-02 (rebind accepts only trigger axes >= 0.5; sticks ignored) and T-04-03 (Tab/Escape reserved, reset available) are implemented and tested.

## Notes for downstream plans

- The skeleton Highway still reads `LaneInput.ACTIONS`; plan 07 UI should use `BindingStore.display_name` for lane labels.
- Plan 06/07 should set `LaneInput.enabled = false` during countdown and pause.
- Real-device trigger behavior (controller trigger range 0..1 vs -1..1 on some drivers) is unverified headless; check at the plan 07 hardware gate.
- Bus volumes are applied on Settings `_ready`/`load_from`; the Music/SFX buses come from default_bus_layout.tres.

## Self-Check: PASSED

Created files and commits 41746d0, e62a519, 62da893, ed8365f verified present.
