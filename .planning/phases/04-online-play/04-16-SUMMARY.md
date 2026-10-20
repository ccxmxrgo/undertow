---
phase: 04-online-play
plan: 16
subsystem: ui
tags: [settings, online, debug-overlay, net-stats]
requires: ["04-03", "04-04", "04-10"]
provides:
  - "Settings ONLINE section (Player name, Online port SonarTextFields) between AUDIO and LIBRARY"
  - "NetDebugRows.format(stats) -> 5 F3 lines"
  - "DebugOverlay net rows while NetSession.pending_match() is non-empty (panel 360 x 580)"
affects: [04 human UAT (D-10 measure-first numbers), Play Online name/port defaults]
tech-stack:
  added: []
  patterns: [test seam net_session on DebugOverlay, screen ui_cancel guard while a SonarTextField edits]
key-files:
  created:
    - src/ui/online/net_debug_rows.gd
    - tests/test_settings_online.gd
    - tests/test_net_debug_rows.gd
  modified:
    - src/ui/settings_screen.gd
    - src/ui/debug_overlay.gd
decisions:
  - "Net rows live in a second Label at y 430 (under the hit-error rows), so the graph and the original label never move and offline text is byte-identical"
  - "Net lines (~500 px at Label 20) are wider than the 360 px panel; _draw extends the ABYSS_900 70% shade to the right behind the net block only"
  - "NetDebugRows prints ints as %d, finite floats with one decimal, and anything else as --"
  - "Settings: no setters added; commits assign the var, save_to(save_path) and emit settings_changed (04-03 convention)"
metrics:
  duration: "~40 min (including two interruptions)"
  completed: 2026-10-20
  tasks: 2
  files: 5
requirements: [NET-01, NET-04]
---

# Phase 4 Plan 16: Settings ONLINE section and F3 net rows Summary

Settings now has an ONLINE section. Its Player name field (x 440..952) and Online port field (x 440..600) save through Settings. In debug builds, during an online match, F3 adds five NetDebugRows lines under the timing block: role, seat, peers, RTT, offset, horizon D, late inputs, skew, landed-late and packets/event seq.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | c20fd4f | feat(04-16): Settings ONLINE section with Player name and Online port fields |
| 2 | 7a2567f | feat(04-16): F3 net debug rows (NetDebugRows) in the DebugOverlay |

## What was built

- **SettingsScreen**
  - `_build_online` sits between AUDIO and LIBRARY. It has two rows, "Player name" and "Online port", each with a hint (`HINT_PLAYER_NAME`, `HINT_ONLINE_PORT`), plus a WARNING_RED `online_message` line.
  - `commit_player_name(v)` cleans the value with `Settings.clean_player_name` (upper-case), then sets `player_name` and `player_name_set = true`, saves and emits.
  - `commit_port(v)` checks the range again; on failure it reverts and shows `ERR_PORT_RANGE`. The field's `invalid("port_range")` shows "! Port must be between 1024 and 65535.", and the line clears when editing starts again.
  - `online_editing()` guards `_unhandled_input` ui_cancel, so Esc while editing reverts in the field and Settings stays open. `back_pressed()` cancels an open edit.
  - `_refresh_all` re-reads idle fields.
- **Focus.** The generic `focus_rows()` / `link_focus_rows()` picked up both fields automatically, giving SFX -> Player name -> Online port -> Open Songs Folder. test_gamepad_settings needed no edit because its walk is derived from the live rows.
- **NetDebugRows** (`class_name`, RefCounted) provides `format(stats)` and `num(d, key)`. On the host, line 2 shows the per-peer p90 by name for up to 3 peers, two spaces apart. If the host has no per-peer list, line 2 falls back to the client p50/p90/offset form.
- **DebugOverlay**
  - `PANEL_SIZE` is (360, 580). The `NetRows` Label sits at y 430.
  - `refresh_net_rows()` runs only in the visible branch of `_process`, so the session is not polled while the overlay is hidden. The existing `OS.is_debug_build()` toggle gate still applies (T-04-47).
  - New seam and accessors: the `net_session` seam (default `/root/NetSession`), plus `timing_text()` and `net_text()`.

## Verification

- test_settings_online: 9/9
- test_net_debug_rows: 8/8
- test_gamepad_settings: 19/19
- test_library_settings: 12/12
- test_pause_overlay: 8/8. The first run hit a song_time > 0 timing flake under parallel load; the rerun was clean.
- test_color_literals: 7/7
- test_effect_settings: 14/14
- tools/check_timing_gate.ps1: TIMING GATE OK
- No existing test references DebugOverlay (grep), so the plan's "existing overlay tests" step had no suites to run.

## Deviations from Plan

1. **[Rule 2 - Layout] Net-row shade wider than the panel.** At Label 20 the UI-SPEC 11.8 lines are about 500 px wide, which does not fit the 360 px panel. The panel keeps the spec size, and `_draw` extends the same shade to the right behind the net block only. Visible during online matches only.
2. **[Design] Second Label instead of appending to the timing label.** The plan allowed either option. This choice keeps the graph origin and the offline text unchanged.
3. **[Rule 2] Test seam.** Added `DebugOverlay.net_session` (and accessors) so tests use a FakeSession instead of the autoload.

## Notes

- During the test runs, parse errors from the in-progress gameplay.gd (plan 04-14, running concurrently) showed up in the logs. They do not involve this plan's files, and every suite above passed.

## Known Stubs

None.

## Threat mitigations

- T-04-47: the rows render only inside the visible F3 overlay, which only debug builds can toggle on.
- T-04-48: SonarTextField reverts an out-of-range port. `commit_port` checks the range again, and `Settings._load_net` clamps on load.

## Self-Check: PASSED

- All 5 files exist. Commits c20fd4f and 7a2567f are on origin/main.
