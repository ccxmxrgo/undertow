---
phase: 04-online-play
plan: 07
subsystem: ui
tags: [ui, online, overlay, dialog, keep-out, effects]
requires: [04-04]
provides:
  - StartSyncOverlay (src/ui/online/start_sync_overlay.gd)
  - LeaveOverlay (src/ui/online/leave_overlay.gd)
  - HostLeftDialog (src/ui/online/host_left_dialog.gd) + HostLeftDialog.rows_from_status
affects: [04-14 online gameplay wiring]
tech-stack:
  added: []
  patterns: [self-drawn in-game overlay with step(dt) animation and UiKit effect contract]
key-files:
  created:
    - src/ui/online/start_sync_overlay.gd
    - src/ui/online/leave_overlay.gd
    - src/ui/online/host_left_dialog.gd
    - tests/test_online_overlays.gd
  modified:
    - tests/test_overlay_layout.gd
    - tests/test_layout_keepout.gd
    - tests/test_effect_settings.gd
decisions:
  - "LeaveOverlay ui_left / ui_right both move focus to the other button (wrapping). With two buttons, the plan's 'ui_right then ui_accept = Leave' and the spatial layout (Leave on the left) both hold"
  - "LeaveOverlay swallows the pause / ui_cancel press in the frame it was opened, so the Esc that opens it does not close it at once"
  - "lane_1..4 and target_cycle are checked first and never consumed, even if rebound onto a ui_* input"
  - "All three widgets animate through step(dt) (driven by _process), so tests and gameplay can advance them deterministically"
  - "rows_from_status: a seat with left=true counts as down (after the alive subs) and is ordered with the wrecks by depth"
metrics:
  duration: ~35 min
  completed: 2026-10-20
requirements: [NET-03, NET-05, NET-06]
---

# Phase 4 Plan 07: In-match online overlays Summary

This plan adds three standalone, data-driven online overlays for gameplay to wire in 04-14:

- **StartSyncOverlay** shows the LOADING SONG / LINKING SUBS state and a per-sub roster. It fades out over DUR_BASE.
- **LeaveOverlay** never pauses. It sits in the top band, above the note-path keep-out.
- **HostLeftDialog** shows HOST LEFT or CONNECTION LOST, the last known standings and a Back to Menu button.

Each overlay has layout, keep-out, input, effect and has_char tests.

## Tasks

| # | Task | Commit |
|---|------|--------|
| 1 | StartSyncOverlay, LeaveOverlay, HostLeftDialog + tests/test_online_overlays.gd | 37e5546 |
| 2 | Layout, keep-out and effect contracts (test_overlay_layout, test_layout_keepout, test_effect_settings) | 2a8966e |

## APIs for 04-14

### StartSyncOverlay (`extends Control`; the node IS the rect (600, 340, 720, 400))
- `setup(rows: Array)`: each row is `{seat, name, is_you}`. At most 4 rows; all start as LOADING.
- `set_stage("loading"|"linking")`, `set_loaded(seat, on)`, `set_pad(bool)` (gameplay has no last-device helper, so the caller sets this).
- `dismiss()` fades out over `Palette.DUR_BASE`, emits **`dismissed`** and then `queue_free()`s. `is_dismissing()`.
- `title_text()`, `body_text()`, `hint_text()`, `line_texts()`. `debug_state()` returns `{title, body, lines:[{name,status}], hint, dismissing}`.
- `step(dt)` is driven by `_process`. `effect_counts()` returns `{fade_out: true, glow}`.
- Mouse filter is IGNORE. Add it on the gameplay overlay layer (after VersusHud). The keep-out exception proof ("gone by conductor.begin + DUR_BASE") belongs to 04-14.

### LeaveOverlay (`extends Control`; the node IS the rect (640, 120, 640, 152); hidden until opened)
- `open(is_host: bool, ping_ms: int = -1)` (ping < 0 shows "PING -- MS"; the host has no ping readout), `set_ping(ms)`, `close()`, `is_open()`, `focus_name()` ("stay" or "leave").
- Signals: **`leave_confirmed`** and **`stayed`**. The overlay closes itself before it emits either one.
- Input: `_input` calls `handle_event(event) -> bool` and marks the event handled when it returns true. It consumes only pressed ui_left/ui_right/ui_accept/ui_cancel/pause; lane_1..4, target_cycle and `fire` (on its own) pass through. Space and pad A are ui_accept, so they pick the focused button and do not fire.
- It never touches `get_tree().paused` or the conductor. process_mode is ALWAYS.
- **Wiring note:** gameplay's pause handler must open this overlay online instead of PauseMenu, and must not also act on that press (mark it handled). The overlay ignores pause/ui_cancel in its opening frame. Gameplay's fire handler should run in `_unhandled_input`, or check `leave_overlay.is_open()`, so that the consumed Space really does not fire.
- `debug_state()` returns `{open, focus, body, body_role ("mid" client / "warning" host), ping, title}`. `effect_counts()` returns `{slide, glow}`.

### HostLeftDialog (`extends Control`, full screen via UiLayout.fill_rect, process_mode ALWAYS)
- `setup(kind: "host_left"|"connection_lost", host_name: String, rows: Array)`. Rows are `{place, name, is_you, is_host, status: "hull"|"wreck"|"left", hull_pct}`, at most 4, already ordered.
- `static rows_from_status(statuses: Dictionary, names: PackedStringArray, local_seat, host_seat) -> Array`. `statuses` maps seat to `{hull, depth, alive, left}`. Alive subs come first, by hull and then depth (both descending); wrecks and leavers follow, by depth; seat breaks ties. Places run 1..n and at most 4 rows come back. Each row also carries `seat` and `depth`. The result goes straight into `setup()`.
- Signal **`back_to_menu`** (emitted once). It fires on Accept, Esc or B (or pause), handled in `_input`, or on a click of the button.
- `set_pad(bool)` for the hint. Public nodes: `panel`, `button`, `dim`. `debug_state()` returns `{title, body, rows, focus, hint}`. `effect_counts()` returns `{rise, glow}`. Static helpers: `place_text`, `status_of`.
- Gameplay stops the conductor and disables lane input before it shows the dialog (UI-SPEC 11.6).

## Tests

| Suite | Result |
|-------|--------|
| test_online_overlays (new) | 18/18 |
| test_overlay_layout | 32/32 (+1) |
| test_layout_keepout | 8/8 (+1) |
| test_effect_settings | 14/14 (+1, `online_overlays` context) |
| test_color_literals | 7/7 |
| tools/check_timing_gate.ps1 | TIMING GATE OK |

`grep -c PRESET_FULL_RECT src/ui/online/*.gd` returns 0 for every file.

## Deviations from Plan

**1. [Ordering] HostLeftDialog landed in the Task 1 commit.** `tests/test_online_overlays.gd` covers all three widgets. Committing the dialog with it keeps every commit parseable. Task 2's commit holds the layout, keep-out and effect contract tests.

**2. [Design] Left/right focus wraps.** The plan's test reads "ui_right then ui_accept emits leave_confirmed", but UI-SPEC 11.4 puts Leave Match on the left of Stay. Because each direction moves to the other button, both statements hold.

**3. [Spec reading] The check glyph sits 4 px (SP_XS, the glyph-to-text gap) left of LOADED.** I read the spec's "16 px" as the glyph size.

## Known Stubs

None. The widgets are complete; wiring them into gameplay is the planned work of 04-14.

## Threat mitigations

- T-04-23: the overlays render only names that NetCodec has already validated. The has_char test covers every constant string, with headings checked against the Oxanium file itself.
- T-04-24: a test proves that lane_1/lane_4/target_cycle actions and real 1 / H key presses pass through while the overlay is open, and that Space is consumed.

## Self-Check: PASSED

- All four created files exist, and commits 37e5546 and 2a8966e are on origin/main.
