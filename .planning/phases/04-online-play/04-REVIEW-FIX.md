---
phase: 04-online-play
fixed_at: 2026-10-20T18:00:00Z
review_path: .planning/phases/04-online-play/04-REVIEW.md
iteration: 1
findings_in_scope: 15
fixed: 15
skipped: 0
status: all_fixed
---

# Phase 4: Code Review Fix Report

**Fixed at:** 2026-10-20
**Source review:** .planning/phases/04-online-play/04-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 15. That is CR-01..03, WR-01..09, plus the cheap info items IN-03, IN-05 and IN-10.
- Fixed: 15
- Skipped: 0. The other info items were out of scope and are listed at the end.

Every fix has a regression test, and each one was checked to fail without its fix where that was practical (CR-02, WR-01, WR-04). None of the pinned timing files were touched: conductor, clock_model, input_judge and hull_score are still at 72e21ce, and judge_config is still at 2c2e54c. Offline behaviour is unchanged. Every change is either on an online-only path or guarded by `online` / `pending_online`. The Phase 3 determinism and versus suites pass in the full run.

## Fixed Issues

### CR-01: A seat gap in the roster creates a phantom, immortal player

**Files modified:** `src/ui/versus/versus_controller.gd`, `tests/test_online_controller.gd`
**Commit:** f04e75c
**Applied fix:** `setup_online` now builds PlayerStates only for roster seats, using the new static `VersusController.roster_seats(spec, names, local_seat)`. It uses `spec.seats` when present. Otherwise it uses the named seats plus the local seat. `names` stays indexable by seat, with "" in a gap.
**Test:** roster [0, 2]. It checks that there are exactly 2 players, that LAST_STANDING fires after seat 2 drops, and that the RESULTS built from `finish()` pass `NetCodec.validate` on the client side.

### CR-02: A client that leaves during LOADING after the bind is never eliminated

**Files modified:** `src/autoload/net_session.gd`, `tests/test_net_session_match.gd`
**Commit:** 6a02bfa
**Applied fix:** `_on_peer_left` now calls `_queue.drop_seat` in LOADING too, once the queue is bound. Before the bind it still defers through `_left_seats`.
**Test:** the host binds, a client drops in LOADING, then START. The test asserts PLAYER_LEFT is sent and the seat ends with `alive == false`. It fails without the fix.

### CR-03: RESULTS carries the unclipped title/artist

**Files modified:** `src/autoload/net_session.gd`, `tests/test_net_session_match.gd`
**Commit:** 74fdcd8
**Applied fix:** `host_send_results` passes title and artist through `_text()`, which drops control characters including C1 and clips to MAX_TEXT. `host_name` goes through `NetCodec.clean_name` and is dropped if it comes back empty.
**Test:** a 100-char title and an artist containing U+0085. The client receives RESULTS with a 64-char title and the artist "Artist".

### WR-01: The overlay margin cap of 0.3 s is below D + L + frames

**Files modified:** `src/versus/host_input_queue.gd`, `tests/test_host_input_queue.gd`, `tests/test_net_match_harness.gd`
**Commit:** 3d3d0d9
**Applied fix:** `MARGIN_EXTRA_S` went from 0.033 to 0.050, which covers two 60 Hz frames. The new `L_CAP_S` is 0.25, and `MARGIN_CAP_S = D_MAX_S + L_CAP_S + MARGIN_EXTRA_S` = 0.5 s. The HIGH LATENCY lobby warning is unchanged and still covers the case past L_CAP.
**Test:** a new NetMatchHarness case at RTT p90 300 ms (D 0.2, L 0.15, 60 fps clients, 4 seeds) asserts no overlay pop-in. Measured min slack is +0.279 s. With the old constants the same case measured -0.050 s and failed.

### WR-02: Scene changes are dropped while ScreenTransition is busy

**Files modified:** `src/ui/gameplay.gd`, `src/ui/online/lobby_screen.gd`, `src/net/net_autotest.gd`, `tests/test_online_gameplay.gd`
**Commit:** 9758db7
**Applied fix:**
- Gameplay `_goto` and LobbyScreen `_go` keep any refused target in `_nav_pending` and retry it from `_process` once `ScreenTransition.is_busy()` is false.
- A new one-shot `Gameplay.pending_online` is set by the lobby and by the autotest. If the match is gone by `_ready`, the run goes to the lobby, or to Play Online when the session is not in a lobby. It never falls through to an offline dive.
- The online audio-error timer now goes to the lobby or menu based on the session state, instead of always going to the main menu.

**Tests:** a launch with the match gone goes to the lobby or Play Online, and no conductor is built. A refused change made during a running wipe is retried after the wipe ends.

### WR-03: LOBBY_CLOSED while a client still dives leaves it stuck

**Files modified:** `src/ui/gameplay.gd`, `tests/test_online_gameplay.gd`
**Commit:** 8d50ad2
**Applied fix:** when no results screen is up, `_on_left_lobby` falls through to `_on_host_left`. The code "lost" maps to connection_lost and anything else maps to host_left. The existing guard prevents a second dialog.
**Test:** `left_lobby("closed")` mid-dive shows HOST LEFT and stops the conductor and lanes. A second signal does not add another dialog.

### WR-04: The DONE barrier can compute results before the final INPUTS

**Files modified:** `src/autoload/net_session.gd`, `tests/test_net_session_match.gd`
**Commit:** bedf038
**Applied fix:** a new `_drain_inbox()` moves validated INPUTS into the queue. `_host_pump` uses it, and `_check_results_due` calls it right before `results_due` is emitted.
**Test:** the client's last flush and its DONE arrive in the same poll, and all 3 items are in the queue when `results_due` fires. It fails without the drain.

### WR-05: The INPUTS rate limit drops post-stall bursts, and strikes never decay

**Files modified:** `src/autoload/net_session.gd`, `tests/test_net_session_match.gd`
**Commit:** dbf883e
**Applied fix:**
- The bucket is now `INPUT_BURST` = 4 x MAX_INPUTS_PER_S = 960, still refilled at 240/s.
- Past an empty bucket, items are still queued up to a further `INPUT_DEBT` of 960. Only the part of a batch beyond that is cut.
- Overflow strikes are rate limited to at most one per 0.5 s, so the chunks of one burst count once.
- `_clear_match` resets strikes, the PING and INPUTS buckets, and the overflow-strike time.

**Tests:** the rewritten flood test checks that a 300-item backlog is fully queued with 0 strikes. A 2200-item flood is cut at the burst plus the debt with 1 strike, and a continued flood is disconnected. A second new test checks that strikes reset with the match.

### WR-06: A host stall in LOADING trips the client watchdog

**Files modified:** `src/autoload/net_session.gd`, `tests/test_net_session_match.gd`
**Commit:** ed9d1b1
**Applied fix:** in LOADING the client's silence limit is `LOAD_TIMEOUT_S + START_DELAY_S`. PLAYING and RESULTS keep the 4 s limit.
**Test:** the host link is stalled for WATCHDOG + 2 s during LOADING and the client stays in LOADING. The longer LOADING bound still ends with connection_lost.

### WR-07: "Host is choosing a song." is never sent

**Files modified:** `src/autoload/net_session.gd`, `src/ui/online/lobby_screen.gd`, `tests/test_lobby_screen.gd`, `tests/test_net_session_lobby.gd`
**Commit:** 3a2d4d0
**Applied fix:** the new `NetSession.host_choosing()` sends the NOTICE "choosing" to clients only. It only works when the host is in the lobby. `LobbyScreen.open_song_pick()` calls it before going to Song Select. No codec change was needed, because the codec already accepts that code.
**Tests:** the client logs "choosing" and the host gets no log line of its own. `open_song_pick` calls the session once.

### WR-08: Unthrottled control messages amplify into NOTICE broadcasts

**Files modified:** `src/autoload/net_session.gd`, `tests/test_net_session_lobby.gd`
**Commit:** c7cb316
**Applied fix:**
- READY and SONG_STATUS go through a per-peer control bucket: 10/s, burst 20. Overflow is dropped silently, and every 20 drops count as one strike.
- `high_latency` now has hysteresis through the static `high_latency_next`. It notifies above 250 ms and re-arms only below 220 ms, or once the budget is back under 250 ms at least 10 s after the notice.

**Tests:** a 60-toggle READY flood gives at most 12 ready notices and 2 strikes, with no kick, and normal Ready still works afterwards. The hysteresis table is covered by its own test.

### WR-09: Non-RAW SceneMultiplayer commands bypass NetCodec and strikes

**Files modified:** `src/net/raw_gate_peer.gd` (new) and its `.gd.uid`, `src/net/enet_transport.gd`, `tests/test_enet_transport.gd`
**Commit:** 38f8a9f
**Applied fix:** the new `RawGatePeer` (a MultiplayerPeerExtension) sits between SceneMultiplayer and the ENet peer. Only RAW packets (cmd 3) and SYS AUTH packets (cmd 7, sub 0) reach the API. On the host, each dropped packet is a gate strike against its sender, and 3 strikes disconnect it, which the session sees as a normal peer_left.
**Tests:** a table test for the allowed packet kinds, plus a real-ENet test in which a member sends 3 crafted RPC and path-cache packets, is disconnected, and produces exactly one peer_left. NET SMOKE OK on real ENet with the gate in place.
**Note:** the command byte layout (RAW = 3, SYS = 7, AUTH = 0, mask 7) is a SceneMultiplayer internal of the pinned Godot 4.7.2. Re-check it on any engine upgrade. test_enet_transport and net_smoke would catch a mismatch, because auth or data would stop flowing.

### IN-03: No lossy-link smoke run

**Files modified:** `src/net/enet_transport.gd`, `src/net/net_autotest.gd`, `tools/net_smoke.ps1`, `tests/test_net_autotest.gd`
**Commit:** 9328ffc
**Applied fix:**
- `ENetTransport.lossy` is used by the smoke only and defaults to 0.
- When set, a "lost" reliable packet is held for 50-150 ms with head-of-line blocking and then sent in a burst, which mirrors how ENet retransmits. Unreliable packets are dropped. This applies to both sends and receives.
- `--net-lossy=<0..0.2>` (NetAutotest) and `net_smoke.ps1 -Lossy p` turn it on for client C1. The smoke still requires identical digests and zero strike disconnects, and only notes late inputs.

**Result:** `net_smoke.ps1 -Scenario full -Lossy 0.05` passed with NET SMOKE OK. All 3 client digests matched the host, strike disconnects were 0, and 3 late inputs were clamped as expected.

### IN-05: START has no upper bound on the lead

**Files modified:** `src/autoload/net_session.gd`, `tests/test_net_session_match.gd`
**Commit:** 612cd98, shared with IN-10 because both change the same two files
**Applied fix:** a lead above `START_DELAY_S + MAX_EXTRA_LEAD_S` (2 s) on the first `lead_in_for_start` call is reported as START_LATE, and everyone goes back to the lobby.
**Test:** a bogus 60 s offset leads to start_late and the lobby.

### IN-10: Seats without host-side RTT samples get a margin of 0

**Files modified:** `src/autoload/net_session.gd`, `tests/test_net_session_match.gd`
**Commit:** 612cd98
**Applied fix:** `start_match` gives every roster seat a `margins` entry, using 0.0 RTT when there are no samples. The controller then still applies `margin_for(D, 0)` = D + 50 ms.
**Test:** a seat whose host-side ClockSync was reset still gets `margins[seat] == 0.0`.

## Not in scope (info items left as the review describes)

- IN-01 and IN-02 are reviewer verdicts, not code defects.
- IN-04 (kick ban / immediate row removal), IN-06 (autotest switches honoured on clients), IN-07 (ENet reassembly cap, a threat-model note), IN-08 (MATCH_END row key headroom), IN-09 (duplicate judgments, outside the friends trust model), IN-11 (intended offline-visible UI-SPEC changes) and IN-12 (re-host port reuse) were not part of this fix pass.

---

_Fixed: 2026-10-20_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_

## Gates after the fixes

- Full gdUnit suite: 2147 cases, 2 failures. `test_bot_frequency` is the known red D-UAT-01. `test_pause_overlay` pause is the known flaky test, and it passes alone (8/8).
- `tools/net_smoke.ps1` (both scenarios): NET SMOKE OK. `-Scenario full -Lossy 0.05`: NET SMOKE OK.
- `tools/check_timing_gate.ps1`: TIMING GATE OK.
