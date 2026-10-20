---
phase: 04-online-play
plan: 14
subsystem: ui/gameplay
tags: [online, gameplay, synced-start, countdown, leave-overlay, host-left, results, NET-03, NET-04, NET-05, NET-06]
requires: ["04-07", "04-08", "04-10", "04-12", "04-13"]
provides:
  - "Gameplay online branch: launch from NetSession.pending_match(), setup_online + bind_*_match"
  - "_begin_online(lead): the second and last Conductor.begin call site, on start_scheduled"
  - "per-frame pre_tick, update, net_tick, pump_match (NAN before START); client link chip"
  - "Leave overlay instead of PauseMenu; F4 off; fire blocked while it is open"
  - "HOST LEFT / CONNECTION LOST dialog from the last STATUS standings"
  - "DONE at min(chart end + pad, max_song_s), WAITING FOR RESULTS, host results_due -> finish -> host_send_results, online results, back to lobby"
  - "test seams: Gameplay.session (injectable), Gameplay.navigate (scene change Callable), fire_count, last_status(), online_end_time()"
affects: ["04-15 (lobby navigates here and back)", "04-17 (autotest drives max_song_s / autoplay)"]
tech-stack:
  added: []
  patterns: ["online branch gated on online_spec; offline code paths unchanged", "session signals wired by method Callables, calls made dynamically so a fake Node can stand in"]
key-files:
  created: [tests/test_online_gameplay.gd]
  modified: [src/ui/gameplay.gd]
decisions:
  - "The overlay shows LOADING SONG for the build frame. LINKING SUBS and report_loaded() run deferred (next idle step). The chart itself is built by the lobby before navigating"
  - "lead < 0 (late or unsynced START) never begins anything. Gameplay waits for match_aborted_to_lobby, which navigates to the lobby"
  - "Leave Match confirmed and HOST LEFT Back to Menu go to the main menu (UI-SPEC 11.4 / 11.6). A client's Leave Lobby on results goes to Play Online (UI-SPEC decision 15)"
  - "Host results Back to Menu (CLOSE LOBBY confirmed) calls session.leave() and goes to the MAIN menu, matching the button label. The plan text said the online menu"
  - "host_left or left_lobby while the results screen is up calls versus_results.set_lobby_closed() instead of opening the HOST LEFT dialog"
  - "After the HOST LEFT dialog opens, pump_match stops (the session is already OFFLINE)"
  - "The lobby scene is referenced by path. Until it exists, lobby navigation falls back to the Play Online scene"
metrics:
  duration: "~40 min"
  completed: 2026-10-20
  tasks: 2
  files: 2
---

# Phase 4 Plan 14: Gameplay online flow Summary

Gameplay now runs a full online match:
- **Launch.** An online match launches from `NetSession.pending_match()` with no goggles intro. The StartSyncOverlay goes LOADING SONG, then LINKING SUBS, then LOADED.
- **Synced start.** START begins the conductor with the scheduled lead-in, so song_time 0 lands on the host instant. The banner counts DIVE IN 3/2/1, then DIVE, from song time.
- **Per frame.** The network link is pumped every frame. A client shows NO HOST SIGNAL after 1 s without host packets.
- **Leaving.** Esc/Start opens the non-pausing Leave overlay. A lost host stops the song and shows the HOST LEFT / CONNECTION LOST standings.
- **End of song.** The song end reports DONE and shows WAITING FOR RESULTS. The host builds results once and sends them, and every PC shows the online results with Back to Lobby / Leave Lobby.

Offline solo, Solo Dive and versus are unchanged.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 (+ Task 2 gameplay code) | f8b758d | feat(04-14): online gameplay branch (scheduled begin, sync overlay, countdown, pump, leave, host-left, DONE/results) |
| 2 tests | 6fdd1f0 | test(04-14): online gameplay suite over a fake NetSession |

The Task 2 gameplay changes (end of song, results, back to lobby) landed in the Task 1 commit, because both tasks edit the same new online section of gameplay.gd.

## How the online branch hangs together (src/ui/gameplay.gd)

- **`_ready`:**
  - `session` comes from `/root/NetSession` unless a test already set it.
  - A non-empty `pending_match()` sets `online_spec`, clears match_setup and practice, and connects the session signals.
  - It then calls `start(c, false, NONE)`.
- **`start()`, online:**
  - Builds a `VersusController` with `net_send = Callable(session, "send_to_host")` (clients, set before setup) and `setup_online(self, chart, cfg, spec + song_len)`.
  - Calls `bind_host_match(queue, host_channel, n, len)` or `bind_client_match(remote, client_channel, n, len)`.
  - Connects `channel.received` to `_on_net_event` (last-status tracking).
  - Then `_build_online_overlays()` instead of the count-in. The NONE branch is `elif intro_mode == NONE and online_spec.is_empty(): _begin_count_in()`.
- **`_begin_online(lead)`:** `conductor.begin(stream, lead)` plus the same four flags as `_begin_count_in`. `grep -c "conductor.begin("` is 2.
- **Session signals:**
  - start_scheduled: `lead_in_for_start()`, then `_begin_online`, `start_countdown(-lead, flight)` and the sync overlay dismissed.
  - match_aborted_to_lobby: go to the lobby.
  - host_left: `_on_host_left`.
  - results_due: `_host_results`.
  - results_received: `_show_online_results`.
  - returned_to_lobby: go to the lobby.
  - left_lobby: `set_lobby_closed()` on results.
- **`_process_online`:**
  - Before START: `pump_match(NAN)`.
  - After START: `pre_tick`, `update`, `net_tick`, then `pump_match(t)`. Client link chip on change. Client ping on the open Leave overlay.
  - DONE at `online_end_time()`. Host still-diving count refreshed in place.
- **Render order:** VersusHud < StreakCounter < DebugOverlay < StartSyncOverlay < LeaveOverlay < PauseMenu < HostLeftDialog / results (appended).

## Tests

- **test_online_gameplay (new): 14/14.** The 9 plan cases, plus F4 disabled, the host never showing the link chip, CONNECTION LOST during sync, and returned_to_lobby.
  - The countdown case measures the sync overlay freed at begin + DUR_BASE (+0.1 s slack) and before `first_note - approach`.
  - The leave case uses real Esc/1/Space key events through the viewport. It shows that Space fires once the overlay is closed, so the "does not fire" check is meaningful.
- **Offline guards (unchanged and green):**

  | Suite | Result |
  |-------|--------|
  | test_gameplay_smoke | 13/13 |
  | test_versus_gameplay | 12/12 |
  | test_pause_resume | 5/5 |
  | test_pause_overlay | 8/8 |
  | test_intro_flow | 12/12 |
  | test_layout_keepout | 8/8 |

- **Phase 3 determinism:** test_versus_controller_determinism 5/5, test_match_determinism 4/4, test_match_sim_determinism 2/2.
- **Other:** test_online_controller 7/7, test_online_overlays 18/18.
- **tools/check_timing_gate.ps1:** TIMING GATE OK. No pinned timing file was touched.

## Deviations from Plan

1. **[Spec alignment] Host results "Back to Menu" goes to the main menu, not the online menu.** The UI-SPEC button label is "Back to Menu", and 11.4 / 11.6 send the other "menu" exits to the main menu. Only the client's Leave Lobby goes to Play Online (UI-SPEC decision 15).
2. **[Rule 2] Extra guards:**
   - The audio-load failure calls `report_load_failed()`.
   - A START after host loss is ignored.
   - results_due is idempotent.
   - The leave overlay closes when the results appear.
   - host_left during the results screen switches the screen to lobby-closed rather than stacking a dialog.
3. **[Test seam] `Gameplay.navigate` Callable.** Scene changes in the online paths go through `_goto(path)`, so tests can record the target without swapping the runner's scene. The offline `go_to_menu` is untouched. `fire_count` counts forwarded fire presses (both branches).

## Notes for 04-17 (autotest / smoke)

- `start_match({"seed", "max_song_s", "autoplay": true})`: gameplay ends the local song at `min(chart end + 0.5, max_song_s)` and reports DONE there. `spec.autoplay` makes the human autoplay through setup_online, and lane input stays enabled.
- The lobby must set `Gameplay.pending_chart` before navigating to `res://scenes/gameplay.tscn` on `match_loading`. Gameplay falls back to `TestCharts.hand_chart()` if it is missing.
- Gameplay exits:
  - Lobby (`res://scenes/lobby.tscn`, falling back to `online_menu.tscn` while missing): returned_to_lobby, match_aborted_to_lobby and the host's Back to Lobby.
  - Main menu: Leave Match, HOST LEFT and host CLOSE LOBBY.
  - Play Online: client Leave Lobby.
- Useful probes: `gp.is_online()`, `gp.is_began()`, `gp.versus_results.online_state()`, `gp.host_left_dialog`, `gp.last_status()`, `gp.versus.debug_net()`.

## Known Stubs
None.

## Threat Flags
None beyond the plan's register:
- T-04-41: lead < 0 never begins (tested).
- T-04-42: host loss stops the conductor and shows a dialog with a single exit (tested).
- T-04-43: the PauseMenu never opens online, and the Leave overlay never pauses (tested).

## Self-Check: PASSED
- src/ui/gameplay.gd, tests/test_online_gameplay.gd and tests/test_online_gameplay.gd.uid exist.
- Commits f8b758d and 6fdd1f0 are on origin/main.
