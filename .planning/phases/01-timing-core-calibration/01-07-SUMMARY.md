---
phase: 01-timing-core-calibration
plan: 07
subsystem: menus-calibration-settings
status: awaiting-checkpoint
tags: [godot, gdscript, calibration, settings, rebind, main-menu]
requires:
  - phase: 01-04
    provides: CalibrationMath, DeviceHeuristics, BindingStore, Settings
  - phase: 01-06
    provides: Gameplay launch params, PauseMenu settings overlay contract
provides:
  - scenes/main_menu.tscn (project main scene) with Start Dive, Autoplay Dive (test), Calibrate Sonar, Settings, Quit Game
  - scenes/calibration.tscn + CalibrationWizard (Intro, Audio, Visual, Summary)
  - scenes/settings.tscn + SettingsScreen (full scene and pause overlay)
  - RebindCell, StepSlider UI components
  - Settings.calibration_done, device_changed(), save_calibration()
affects: [phase-2]
tech-stack:
  added: []
  patterns: [injectable `navigate` Callable on screens so tests observe scene changes, StepSlider drawn from Palette]
key-files:
  created:
    - src/ui/settings_screen.gd
    - src/ui/rebind_cell.gd
    - src/ui/step_slider.gd
    - src/ui/calibration_wizard.gd
    - src/ui/main_menu.gd
    - scenes/settings.tscn
    - scenes/calibration.tscn
    - scenes/main_menu.tscn
    - tests/test_menu_flow.gd
    - tests/test_calibration_flow.gd
  modified:
    - src/autoload/settings.gd
    - project.godot
key-decisions:
  - "Screens take a `navigate` Callable (default SceneTree.change_scene_to_file) so tests assert routing without swapping the runner scene"
  - "First-launch redirect is once per session via static MainMenu.boot_handled; Skip/Save in the wizard sets it so the menu does not bounce back"
  - "Wizard stores taps in Conductor song time and converts with CalibrationMath.remove_applied_offset(Settings.audio_offset) at evaluation, so re-measuring after applying an offset yields the absolute value"
  - "Custom StepSlider instead of HSlider: deterministic 400 ms hold / 10 Hz repeat and Palette drawing without grabber textures"
  - "Re-run Calibration is disabled in overlay mode (a scene change would tear down the paused run)"
patterns-established:
  - "Esc/B (ui_cancel) acts as Skip in the wizard and Back in Settings; ConfirmDialog consumes it first when open"
requirements-completed: [CAL-01, CAL-02, CAL-03, CAL-04]
requirements-pending-hardware: [CAL-01, CAL-02, CAL-03, CAL-04]
completed: 2026-10-07
---

# Phase 1 Plan 07: Menus, Calibration Wizard and Settings Summary

Main menu with first-launch routing, a calibration wizard built on the tested CalibrationMath, and a Settings screen with a full rebind UI; automated work is done and the build is re-exported. The real-hardware human gate (task 3) is still open.

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Settings screen, rebind cells, sliders, toggles, calibration section | b6fdb6b |
| 2 | Calibration wizard, main menu, first-launch and device-change routing | cb248ac |
| 3 | Phase 1 human gate on real hardware | PENDING (checkpoint) |

## Verification

- `powershell -NoProfile -File tools/run_tests.ps1` exits 0: 146 test cases, 0 failures, 0 orphans (25 new: 13 menu flow, 12 calibration flow).
- Synthetic taps (clicks + 37 ms) measure 0.037 +-0.002 and persist to settings.cfg; re-measure with an applied 40 ms offset also returns 0.037 (offset removal works).
- Too few taps shows the exact error copy and hides Accept; Skip leaves offsets untouched.
- Rebind: free key binds, duplicate and Tab rejected with UI-SPEC copy and binding unchanged, Esc/B cancel, sticks and weak triggers ignored, Reset Controls restores D.
- Overlay mode: Back emits `closed`, makes no navigate call, current scene unchanged.
- Headless boots of main_menu.tscn (new main scene) and settings.tscn run without script errors.
- `tools/export.ps1` succeeds: build/undertow-debug.exe (+ .pck, console exe), 2026-10-07. Build output is gitignored.
- Acceptance greps: main_menu.tscn in project.godot = 1, "Autoplay Dive (test)" = 1, `signal closed` = 1, audio_offset_from_taps in wizard = 1.

## Deviations from Plan

**1. [Rule 3 - Blocking] Taps cannot exceed half a beat:** with 100 BPM clicks the nearest-click matching caps a measurable offset at 300 ms, so the "unusually large" branch (is_suspicious, > 300 ms) is unreachable from taps alone. The copy and check are implemented; the test covers a 280 ms offset instead of the plan's implied >300 ms case.

**2. Extra components:** `StepSlider` and `RebindCell` were added as separate scripts (rebind_cell.gd was in the plan; step_slider.gd was not). No new dependencies.

**3. Buffer readout:** shown from ProjectSettings `audio/driver/output_latency` (the configured mix buffer); Godot exposes no runtime buffer-size getter.

**4. Esc/B in the wizard = Skip for now** (not specified in the UI-SPEC).

## Known Stubs

None. Fire and Target rows are labelled "(Not active yet)" by design (later phases bind behavior).

## Threat Flags

None beyond the plan's register. T-06-01..03 mitigations: offsets clamped via Settings.save_calibration and load clamps, device name only compared to AudioServer.output_device, Tab/duplicates rejected and Reset Controls reachable by ui_* navigation.

## Human Gate (Task 3) - OPEN

Status: awaiting-checkpoint. This gate also absorbs the checkpoint deferred from 01-02 (dev-PC feel, clock-smoothness graph, second-PC export run); TIME-01..03 real-audio evidence stays pending until it passes. Drift harness numbers and the human reply are to be recorded here when the gate resolves.

| Item | Result |
|------|--------|
| Dev-PC feel / F3 clock smoothness | pending |
| 5-minute drift harness (user://drift_log.csv delta) | pending |
| Second PC export run | pending |
| Steps 1-11 of plan task 3 | pending |

## Self-Check: PASSED

Files and commits b6fdb6b, cb248ac verified present.
