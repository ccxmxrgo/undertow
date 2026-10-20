---
phase: 04-online-play
plan: 15
subsystem: online-ui
tags: [ui, lobby, song-select, roster, start-gate, net, tests]
requires: [NetSession lobby + match half (04-06, 04-10), LobbyState / NetAddress (04-03), online glyphs + danger chip (04-04), Play Online screen (04-11)]
provides:
  - "LobbyScreen (src/ui/online/lobby_screen.gd) + scenes/lobby.tscn"
  - "SongSelect.pick_online (ONLINE chip, Pick / Back return to the lobby) + SongSelect.LOBBY_SCENE, pick_return_scene(), pick_chip_text()"
affects: [04-14 gameplay (lobby scene now exists; chart hand-off), 04-17 autotest (LobbyScreen.start_opts)]
tech-stack:
  added: []
  patterns: [OnlineMenu / MatchSetupScreen structure (rect consts, injectables, gui_input row handling, debug_state seams), LogCarry node under the session to carry lobby log lines across scenes]
key-files:
  created:
    - src/ui/online/lobby_screen.gd
    - scenes/lobby.tscn
    - tests/test_lobby_screen.gd
  modified:
    - src/ui/song_select.gd
    - tests/test_song_select.gd
decisions:
  - "Lobby log carry: a 'LobbyLogCarry' child node is added under the session (no net_session.gd edit). It listens to match_aborted_to_lobby / returned_to_lobby and holds those lines until the next lobby screen opens. It also keeps the whole log across the host's Song Select round trip, and clears on left_lobby / host_left / Leave."
  - "Online pick hand-off: the lobby sets MatchSetup.pending = MatchSetup.new() with an empty song_id and sets carry.from_pick. Song Select's Pick stores song_id / difficulty there, and Back leaves song_id empty, which means no change. An online pick never writes Settings.versus_song_id / versus_difficulty."
  - "Song key fp is the library entry's stored fingerprint for that difficulty (the value NetSession._find_entry matches on). sig is the VersusSig of the chart, which is built once."
  - "The client 'Host picked ...' line waits until lobby_song() has a new key, because the NOTICE can arrive before the LOBBY that carries the title."
  - "A local load failure on match_loading shows the status-line audio error (SongSelect.AUDIO_ERR_*) and calls report_load_failed(). The log line itself comes from the host's ABORT_TO_LOBBY through the carry, so it is never written twice."
  - "High latency per row uses LobbyState.is_high_latency(D, row ping), where D comes from the 04-10 formula applied to the worst client ping in the roster. The log line is the session's own high_latency notice."
  - "When there is no LAN address, the Tailscale invite second line is just 'Tailscale address.' (the UI-SPEC line needs {lan}). When there is no address at all, the host subtitle shows the 'No network address found...' copy and Copy Address is disabled and skipped in focus."
  - "Two or more subs with CHANGED fall back to the plural missing copy, because UI-SPEC 15 has no plural for 'changed'."
metrics:
  duration: "~1h"
  completed: 2026-10-20
  tasks: 2
  files: 6
requirements: [NET-01, NET-02]
---

# Phase 4 Plan 15: Lobby screen + Song Select online pick mode Summary

The online lobby screen is in place. It shows the shared roster (PING with signal bars and high-latency red, SONG chips, READY, open seats, your row highlighted). The host has Song / Difficulty / Torpedo flight controls, the invite address with Copy Address, and the start gate reason line. Start Match goes through `session.start_match`, clients toggle Ready, and there are kick, CLOSE LOBBY and LEAVE LOBBY confirms. A 6-line lobby log carries abort and "Match ended" lines across scenes. On `match_loading` the lobby builds the chart by fingerprint and hands off to gameplay. Song Select gained an ONLINE pick mode that returns to the lobby.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | c7906c7 | feat(04-15): Song Select online pick mode (ONLINE chip, return to lobby) |
| 2 | ac6b2cb | feat(04-15): Lobby screen (roster, start gate, ready, kick, log, hand-off to gameplay) |

## What was built

**SongSelect online pick mode**
- `static var pick_online` is reset together with `run_pick` in `_exit_tree`.
- The header chip reads "ONLINE" through `pick_chip_text()`.
- Pick and Back both navigate to `LOBBY_SCENE` ("res://scenes/lobby.tscn") through `pick_return_scene()`.
- The picked song is handed off through `MatchSetup.pending.song_id / difficulty`, the same fields versus uses.
- Versus pick behaviour is unchanged. `debug_state()` gained `pick_chip`.

**LobbyScreen (`class_name LobbyScreen`)**
- Rects come from UI-SPEC 9 consts. Roster columns are NAME 1032, signal glyph 1320, PING right edge 1440, warning glyph 1296, SONG 1480, READY 1664, kick hint right edge 1808. Roster tops are 272/344/416/488 and log baselines run from 656 to 856.
- **Host focus** wraps through Song, Difficulty, Flight, Copy, Start, then the occupied client rows.
  - Left/Right changes Difficulty (it cycles the difficulties the local library entry has, rebuilds the chart to get the sig, then calls host_set_song) and Flight (calls host_set_flight and saves Settings.net_flight_beats).
  - A disabled Start Match stays focusable, and Accept on it plays the error blip.
  - Accept on a client row opens REMOVE {NAME} with Keep focused, and confirming calls session.kick(seat).
- **Client:** only the Ready button is focusable. It reads Ready Up or Cancel Ready (with the check icon) and is disabled unless this PC's SONG is OK. The client reason line follows the copy in UI-SPEC 15.
- **Esc:** the host gets CLOSE LOBBY and the client gets LEAVE LOBBY, both with Stay focused. Confirming calls session.leave() and goes to the online menu. `left_lobby(code)` also goes to the online menu, where the session's return message is shown.
- **Hand-off:** `match_loading` reads `pending_match()` and does a fingerprint lookup over local library entries (T-04-44). It then builds the chart and sets `Gameplay.pending_chart`, clears MatchSetup.pending and the SongSelect flags, stops menu music and navigates to gameplay. If the build fails, it shows the status error and calls `report_load_failed()`.
- **Refresh:** the screen redraws on lobby_changed and also re-reads at 1 Hz. Roster rows fade in and slide 16 px when someone joins (fade only under Reduce motion), the ready check pops, and log lines fade in. It follows the effect contract: `register_fx`, `apply_effect_settings`, `effect_counts`.
- **Injectables:** navigate, session, library, addrs_fn, clipboard_fn (setter), start_opts.
- **Test seams:** debug_state(), focus_row_for_test(id), press_key_for_test(key).

## Verification

- test_lobby_screen: 30/30, 0 orphans. It covers:
  - region rects and column positions
  - host vs client controls and focus order
  - the LAN-only invite line
  - the full start gate order with its copy and glyph
  - Start Match only when the gate passes, with opts passed through
  - Ready cleared on a difficulty change
  - chips, ping, SYNC and open seats
  - high latency (red, glyph, log line)
  - the kick confirm (Keep, then Remove)
  - the 6-line log with code mapping and fault flags
  - the deferred client "Host picked" line
  - abort and match-ended lines carried into the next lobby
  - the match_loading hand-off, a library miss, and a build failure
  - client Ready toggling, and staying disabled for missing or changed songs
  - the song pick round trip, and Back with no change
  - the flight tiles, including the Settings save to a temp path
  - Copy, then "Copied" for 1.6 s
  - the CLOSE and LEAVE confirms
  - left_lobby and an offline session on open
  - the effect contract
  - has_char for every constant string
  - no PRESET_FULL_RECT
- test_song_select: 68/68, including 6 new online pick cases.
- test_online_menu 26/26, test_color_literals 7/7, test_effect_settings 14/14.
- `tools/check_timing_gate.ps1`: TIMING GATE OK. No pinned timing file was touched.

## Deviations from Plan

**1. [Rule 2 - Correctness] Lobby log carry across scenes.** NetSession has no stored abort reason. The aborts happen while gameplay is the current scene, and 04-14 just navigates back. To show these lines without editing net_session.gd, a `LogCarry` node is attached under the session the first time a lobby opens.

**2. [Rule 1] The "Host picked" line is deferred on clients** (see decisions). Without this it would show the old or empty title.

**3. [Scope note] "Host is choosing a song." to clients while the host is in Song Select** is not sent. NetSession has no public call for it, and `_notice` is private. Clients see the line only at join time, from the session's own "choosing" emit. If wanted, a later plan can add a `host_choosing()` notice.

## Notes for 04-17

- To start an autotest match from the lobby, set `LobbyScreen.start_opts = {seed, max_song_s, autoplay}` on the screen instance before Start, or call `session.start_match(opts)` directly. The lobby still handles `match_loading` and the gameplay hand-off.
- The lobby scene is `res://scenes/lobby.tscn`. Gameplay's back-to-lobby and abort paths land there, and the carry adds the abort or "Match ended. Ready up for another." line.
- In headless smoke runs, inject `addrs_fn` or leave the default. If no address is found, Copy Address is disabled, which is harmless.

## Known Stubs
None.

## Threat Flags
None beyond the register:
- T-04-44: fingerprint lookup only.
- T-04-45: clients get FOCUS_NONE / MOUSE_FILTER_IGNORE on host rows, and the host-only calls are guarded by `_is_host`.
- T-04-46: confirms open with the safe button focused.

## Self-Check: PASSED
- src/ui/online/lobby_screen.gd, scenes/lobby.tscn, tests/test_lobby_screen.gd and src/ui/song_select.gd exist.
- Commits c7906c7 and ac6b2cb are on origin/main.
