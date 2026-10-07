---
phase: 01-timing-core-calibration
fixed_at: 2026-10-07T00:00:00Z
review_path: .planning/phases/01-timing-core-calibration/01-REVIEW.md
iteration: 1
findings_in_scope: 10
fixed: 10
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-10-07
**Source review:** .planning/phases/01-timing-core-calibration/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 10 (CR-01, WR-01..WR-09)
- Fixed: 10
- Skipped: 0

Full suite: `tools/run_tests.ps1` exits 0 (188 test cases, 0 failures, 0 orphans). Regression tests for the behavioural fixes are in `tests/test_review_fixes.gd`. The work ran directly on `master` in the main working tree (no separate worktree).

## Fixed Issues

### CR-01: Pausing during the lead-in resumes audio from a negative position
**Files modified:** `src/core/conductor.gd`, `tests/test_review_fixes.gd`
**Commit:** 99f9d82
**Applied fix:** `resume()` clamps the stream start position to >= 0. When resumed from a negative position it enters a deferred-start pre-roll: after the countdown the audio is scheduled so position 0 is heard at song_time 0. Fixed: requires human verification (timing logic; only the no-early-start/no-negative-seek behaviour is headless-tested).

### WR-01: Monotonic clamp turns "audio is behind" into a clock freeze
**Files modified:** `src/core/clock_model.gd`, `tests/test_review_fixes.gd`
**Commit:** e59cd93
**Applied fix:** When audio is behind by more than the snap threshold, the clock advances at half rate (`dt * 0.5`) instead of being clamped flat. Fixed: requires human verification (logic change).

### WR-02: Visual calibration measured against the old saved audio offset
**Files modified:** `src/core/conductor.gd`, `src/ui/calibration_wizard.gd`, `tests/test_review_fixes.gd`
**Commit:** 224222a
**Applied fix:** Added `Conductor.offset_override` and `audio_offset()`. The wizard sets the override to `pending_audio` for the visual step and resets it in `show_step`.

### WR-03: A new hold can overwrite an active hold without emitting sustain_end
**Files modified:** `src/core/input_judge.gd`, `tests/test_review_fixes.gd`
**Commit:** abf8413
**Applied fix:** `_resolve` closes any active hold in the lane (emitting its ticks and `sustain_end`) before starting the new one. Fixed: requires human verification (logic).

### WR-04: One _held flag shared by a lane's key and trigger axis
**Files modified:** `src/input/lane_input.gd`, `tests/test_review_fixes.gd`
**Commit:** 4b66524
**Applied fix:** Separate `_key_held` and `_axis_held` per lane; press and release fire only on the union's edges. Fixed: requires human verification (logic).

### WR-05: Modal dialogs leave the screen behind them focusable
**Files modified:** `src/ui/confirm_dialog.gd`, `tests/test_review_fixes.gd`
**Commit:** 967c181
**Applied fix:** All four focus neighbours plus next/previous on both buttons now point inside the dialog. The review's part (b), why the Restart button showed no highlight, is not explained by the code and was not addressed; it needs a runtime check.

### WR-06: Fail screen buttons active while the panel is invisible
**Files modified:** `src/ui/fail_screen.gd`, `src/ui/gameplay.gd`, `tests/test_review_fixes.gd`
**Commit:** c04f164
**Applied fix:** Buttons are disabled until the fade-in finishes, then enabled and Retry takes focus. The fail tween in Gameplay is stored and killed in `_teardown`.

### WR-07: export.ps1 can report success for a failed export
**Files modified:** `tools/export.ps1`
**Commit:** b11caae
**Applied fix:** Deletes the stale exe and pck before exporting, and fails on a nonzero Godot exit code as well as a missing exe. Not run (no export templates exercised) and has no test; the script parses.

### WR-08: Settings saved non-atomically, save failures ignored
**Files modified:** `src/autoload/settings.gd`, `tests/test_review_fixes.gd`
**Commit:** 2d40438
**Applied fix:** `save_to` writes `path.tmp` then `DirAccess.rename_absolute` over the target, and calls `push_warning` and cleans up the temp file on failure. The error code is still returned; callers do not check it individually, the warning is logged centrally.

### WR-09: Remaining set_anchors_preset(PRESET_FULL_RECT) calls
**Files modified:** `src/ui/calibration_wizard.gd`, `src/ui/drift_harness.gd`, `src/ui/feedback.gd`, `src/ui/gameplay.gd`, `src/ui/hud.gd`, `src/ui/main_menu.gd`, `src/ui/settings_screen.gd`, `tests/test_review_fixes.gd`
**Commit:** dcc91e4
**Applied fix:** Every remaining `PRESET_FULL_RECT` use in `src/ui` now calls `UiLayout.fill_rect`. A source-scan test guards against reintroduction. A real-window check of pause -> Settings is still advisable.

---

_Fixed: 2026-10-07_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
