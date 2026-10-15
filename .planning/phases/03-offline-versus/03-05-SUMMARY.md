---
phase: 03-offline-versus
plan: 05
subsystem: menus
tags: [main-menu, song-select, solo-dive, training, versus-pick, copy]
requires: ["03-01 MatchSetup + Settings [versus]", "03-02 UiIcons versus / chevrons / reward glyphs"]
provides:
  - "MainMenu: 9 items, versus_button, launch_versus(), MATCH_SETUP_SCENE"
  - "SongSelect: run_pick, MATCH_SETUP_SCENE, training_value(), training_row_visible(), cycle_training(), footer_hint()"
  - "Solo Dive copy across menu, Song Select and results"
affects: [03-09, 03-13, 03-14, 03-15]
tech-stack:
  added: []
  patterns: ["edge-triggered trigger axes (press > 0.5, release < 0.4)", "mode-dependent footer_hint() test seam"]
key-files:
  created: []
  modified:
    - src/ui/main_menu.gd
    - src/ui/song_select.gd
    - src/ui/results_screen.gd
    - src/ui/palette.gd
    - src/ui/gameplay.gd
    - tests/test_menu_flow.gd
    - tests/test_gamepad_menus.gd
    - tests/test_song_select.gd
    - tests/test_overlay_layout.gd
    - tests/test_gameplay_smoke.gd
    - tests/test_intro_flow.gd
decisions:
  - "Palette.STAGGER_MENU changed in place to 0.035 (only main_menu.gd uses it)"
  - "launch_versus() builds MatchSetup.pending from Settings but does not save; launch/launch_practice clear pending first"
  - "Pick mode writes Settings.versus_song_id / versus_difficulty (and MatchSetup.pending when set) and saves Settings; Esc keeps the existing filter-clear-first rule, then returns to match setup"
  - "An audio-load error still shows on the visualizer row in Solo Dive mode (it takes precedence over the training row)"
metrics:
  duration: "~40 min"
  completed: 2026-10-15
---

# Phase 3 Plan 05: Solo Dive rename, Versus Bots menu entry, training stepper and pick mode Summary

Player-facing "Practice Dive" is now "Solo Dive" everywhere. The main menu has 9 items (Versus Bots added as item 2, which opens match setup with `MatchSetup.pending` filled from Settings). Song Select gains the TRAINING TORPEDOES stepper (F3 / Shift+F3, RT / LT, saved to Settings) and a versus pick mode that sends the chosen song back to match setup.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 | 122d204 | feat(03-05): Solo Dive rename and 9-item main menu with Versus Bots |
| 2 | 92bae2d | feat(03-05): Song Select training stepper, versus pick mode and Solo Dive copy |

## What was built

- **main_menu.gd**: items in this order: Start Dive, Versus Bots (`versus` icon), Solo Dive (No-Fail), Chart a Song, Calibrate Sonar, Settings, Autoplay Dive (test), Open Songs Folder, Quit Game. Layout constants: ITEM_TOP 392, DESC_BASELINE 1000, STATUS_BASELINE 1040. Descriptions match UI-SPEC 9.1 / 14 word for word. `launch_versus()` clears the run flags, sets `MatchSetup.pending = MatchSetup.from_settings()` and calls `_go(MATCH_SETUP_SCENE)`. `launch()` (Start Dive and Autoplay) and `launch_practice()` set `MatchSetup.pending = null` before they do anything else.
- **palette.gd**: STAGGER_MENU 0.04 -> 0.035 (8 gaps x 35 ms = 280 ms).
- **results_screen.gd**: flag "SOLO DIVE"; NOT_RECORDED_TEXT now reads "Not recorded. Solo, Autoplay and No-Fail dives do not set records."
- **gameplay.gd**: only the line-26 doc comment changed.
- **song_select.gd**:
  - Copy: header chip "SOLO DIVE"; the start button reads "Start Solo Dive" in practice mode and "Pick Song" in pick mode.
  - Training row (when `run_practice and not run_pick`): caption at (1080, 760). The 48 px compact stepper uses the button "normal" style with the CUT_SM chamfer. Chevrons sit at x 1096 / 1792 and the value is Body 28 TEXT_HI centred at x 1456. A single payload also gets its reward glyph, 24 px wide, placed SP_SM to the left of the value text.
  - Cycling: values follow `MatchSetup.TRAINING_VALUES` and wrap at both ends. Each change saves Settings and plays the `move` blip. For 3 s afterwards the description replaces the section names line at baseline 736.
  - `footer_hint()` returns the Solo Dive hints from the spec and pick-mode hints (see Deviations).
  - `debug_state()` now includes `training` ("" when the row is hidden) and `pick`.
  - `press_key_for_test` gained an optional `shift` argument.
  - Pick mode: `static var run_pick` and `const MATCH_SETUP_SCENE`. It shows an info chip "VERSUS", right edge at x 744, centred on y 88. Enter, A, a click on the start button or a double-click calls `_pick()`, which is guarded against double presses. Esc / B goes to MATCH_SETUP_SCENE. The training row stays hidden. `run_pick` resets in `_exit_tree`.

## Tests

| Suite | Result |
|-------|--------|
| test_menu_flow | 0 failures (adds tests for the versus nav and pending record, clearing pending on start/solo/autoplay, wrap, and the constants) |
| test_gamepad_menus | 17/17 (D-pad order start -> versus -> practice -> chart; A-on-every-item includes versus -> MATCH_SETUP_SCENE) |
| test_overlay_layout | 31/31 |
| test_gameplay_smoke | 13/13 |
| test_song_select | 62/62 (10 new: label/hint, F3 / Shift+F3 cycle + wrap, persistence to file, descriptions, trigger edge behaviour, row hidden in normal and pick modes, pick Enter, pick Esc, drawing every value + pick chip, run_pick reset) |
| test_intro_flow | 12/12 |
| tools/check_timing_gate.ps1 | TIMING GATE OK |

`grep -rn "Practice Dive\|PRACTICE DIVE\|Practice, Autoplay" src tests` finds nothing.

The full suite was not run (parallel-wave rule). Untracked test files from 03-03 / 03-04 work in progress were present and were left alone.

## Deviations from Plan

**1. [Rule 2 - Correctness] test_song_select now points Settings.save_path at a temp file**
- **Found during:** Task 2. The stepper and pick mode call `Settings.save_to(Settings.save_path)`, and this suite had never redirected the save path, so the tests would have written to the real settings file.
- **Fix:** before_test/after_test redirect `Settings.save_path` to `user://test_song_select/settings.cfg`, then restore training_payload / versus_song_id / versus_difficulty and delete the temp files.
- **Commit:** 92bae2d

**2. [Rule 2] Pick-mode footer hint copy**
- UI-SPEC 9.3 does not give a pick-mode hint, and "ENTER DIVE" would be wrong there. I used "UP DOWN SONG  ·  LEFT RIGHT DIFFICULTY  ·  ENTER PICK  ·  ESC BACK" / "D-PAD SONG  ·  LEFT RIGHT DIFFICULTY  ·  A PICK  ·  B BACK", which follows the existing hint style. Swap in spec copy if the UI auditor wants different wording.

**3. [Rule 1] test_menu_flow had two more layout asserts than the plan listed**
- `test_item_order_and_focus_ring_include_open_songs_folder` and `test_best_label_not_focusable_and_after_practice` assumed Practice sits directly under Start. Both now include versus_button.

`test_overlay_layout` line ~664 (tops 416..632) belongs to the pause panel, not the main menu, so it is unchanged.

## Notes for later plans

- **03-13 (match setup screen):** create `res://scenes/match_setup.tscn` at exactly `MainMenu.MATCH_SETUP_SCENE` / `SongSelect.MATCH_SETUP_SCENE`. When it opens, `MatchSetup.pending` is already set by Versus Bots; re-read it, or use `MatchSetup.from_settings()` if it is null. To open song pick, set `SongSelect.run_pick = true` and navigate to `res://scenes/song_select.tscn`. Pick writes `Settings.versus_song_id` / `versus_difficulty`, updates `MatchSetup.pending.song_id` / `.difficulty` if pending is non-null, and saves Settings. Esc changes nothing. Song Select resets `run_pick` on exit. `test_gamepad_menus` expects A on Versus Bots to call `navigate` with MATCH_SETUP_SCENE, so do not change the path.
- **03-14 (gameplay wiring):** a Solo Dive reaches Gameplay with `pending_practice = true` and `MatchSetup.pending == null`. Read the training choice from `Settings.training_payload`, or build a record with `mode = MODE_TRAINING` and `training = Settings.training_payload`; `MatchSetup.training_reward(value)` maps it to -1 / -2 / Reward id. Song Select does not create a pending record for Solo Dive. gameplay.gd code was not touched.
- **03-09 (test_hud_gauges):** this is the seventh suite with old "PRACTICE DIVE" strings and it is still on 03-09. The grep found no remaining hits in tests/, so it may already be clean or assert something else. Check it when 03-09 changes the in-dive chip to "SOLO DIVE".
- **03-15:** UI checks: the menu item at 904..960 clears the description line (baseline 1000), and the status line now sits at baseline 1040.

## Known Stubs

None. MATCH_SETUP_SCENE does not exist on disk until 03-13 ships it. Tests use the navigate seam, so they do not need the scene.

## Self-Check: PASSED
