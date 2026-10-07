---
phase: 01-timing-core-calibration
plan: 06
subsystem: gameplay-screen
tags: [godot, gdscript, gameplay, pause, autoplay, debug-overlay, drift-harness]
requires:
  - phase: 01-03
    provides: Conductor (pause/resume/countdown), InputJudge, HullScore, Autoplay, hand chart
  - phase: 01-04
    provides: LaneInput.enabled, Settings
  - phase: 01-05
    provides: Highway, Hud, Feedback, SfxPool, Palette/theme
provides:
  - scenes/gameplay.tscn + Gameplay controller (static pending_chart / pending_autoplay launch params)
  - FailScreen (IMPLOSION), ResultsScreen (DIVE COMPLETE + NO-FAIL / AUTOPLAY USED flags)
  - PauseMenu (3-beat countdown, ConfirmDialog, Settings CanvasLayer overlay)
  - DebugOverlay (F3) and scenes/drift_harness.tscn (real-audio 5 min drift log)
  - F4 `debug_autoplay` restart with autoplay, HUD AUTOPLAY badge
affects: [01-07]
tech-stack:
  added: []
  patterns: [per-run _run_root rebuilt on restart, pause via Conductor not SceneTree, Settings overlay as CanvasLayer]
key-files:
  created:
    - src/ui/gameplay.gd
    - scenes/gameplay.tscn
    - src/ui/fail_screen.gd
    - src/ui/results_screen.gd
    - src/ui/confirm_dialog.gd
    - src/ui/pause_menu.gd
    - src/ui/debug_overlay.gd
    - src/ui/drift_harness.gd
    - scenes/drift_harness.tscn
    - tests/test_gameplay_smoke.gd
    - tests/test_pause_overlay.gd
  modified:
    - project.godot
    - src/content/test_charts.gd
    - src/ui/hud.gd
key-decisions:
  - "All run nodes live under one _run_root Control; restart/F4 removes and frees it and rebuilds, so no stale signal links"
  - "Autoplay runs disable LaneInput (and PauseMenu.restore_input=false) so stray player presses cannot spoil the all-Perfect run"
  - "Pause menu emits restart_confirmed / menu_confirmed; Gameplay owns restart and the scene change (pause_menu.gd has no change_scene)"
  - "Back to Menu falls back to skeleton.tscn until main_menu.tscn exists (plan 07)"
requirements-completed: [TIME-01, TIME-04, TIME-05, HULL-01, HULL-02, HULL-04]
duration: ~50min
completed: 2026-10-07
---

# Phase 1 Plan 06: Playable Solo Screen Summary

The hand chart now plays end to end: hull, combo, score, pause with countdown, IMPLOSION or DIVE COMPLETE, F3 timing overlay, F4 autoplay and a real-audio drift harness.

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Gameplay controller, fail/results screens, F4 autoplay | a0952f1 |
| 2 | Pause menu, 3-beat countdown, confirm dialogs, Settings overlay | 6ec0680 |
| 3 | F3 debug overlay and drift harness | 796d638 |

## Verification

- `powershell -NoProfile -File tools/run_tests.ps1` exits 0: 121 test cases, 0 failures (8 new).
- Autoplay run of short_chart: 0 Miss, 0 Good, every note Perfect, hull 100, results flagged AUTOPLAY USED.
- F4 injected as an InputEventAction on a manual run: restarts from chart start with autoplay on, AUTOPLAY badge shown, finishes all-Perfect.
- Pause: song_time frozen while real time advances, SceneTree not paused; Resume emits 3, 2, 1 then re-enables LaneInput; Settings stub overlay (CanvasLayer 100) freed on `closed` with the Conductor, score and song position unchanged and no scene change.
- Restart confirm dialog only when score > 0, with "Keep Playing" holding initial focus.

## Deviations from Plan

**1. [Rule 3 - Blocking] Back to Menu target:** main_menu.tscn does not exist until plan 07, so `Gameplay.go_to_menu()` uses it if present and otherwise falls back to skeleton.tscn.

**2. Pause menu delegates restart/menu to Gameplay via signals** rather than calling change_scene itself, so `pause_menu.gd` contains no change_scene at all (acceptance requires none in the Settings handler).

**3. Autoplay disables LaneInput** (not in plan): keeps the run all-Perfect regardless of stray key presses.

**4. Extra tests** for the F3 overlay (hidden by default, error buffer capped at 20) and for the drift harness scene booting and creating its CSV; added to test_gameplay_smoke.gd.

## Notes for plan 07

- Settings screen must expose `var overlay: bool` and `signal closed`; the pause menu sets `overlay = true` before adding it and connects `closed`.
- Menu sets `Gameplay.pending_chart` and `Gameplay.pending_autoplay` before `change_scene_to_file("res://scenes/gameplay.tscn")`.
- Human gate: run scenes/drift_harness.tscn non-headless for 5 minutes; log goes to user://drift_log.csv.

## Known Stubs

None. The Settings button is a no-op until scenes/settings.tscn exists (guarded by ResourceLoader.exists, T-06-03).

## Threat Flags

None. The only file write added is the fixed-name user://drift_log.csv (T-06-01).

## Self-Check: PASSED
