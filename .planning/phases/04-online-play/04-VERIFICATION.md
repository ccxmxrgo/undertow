---
phase: 04-online-play
verified: 2026-10-20T22:00:11Z
status: human_needed
score: 12/12 must-haves verified (automated); real-internet play pending human UAT
overrides_applied: 0
human_verification:
  - test: "Real-internet match over Tailscale on 2-4 PCs (04-HUMAN-UAT tests 1 and 13)"
    expected: "Friend joins via the TAILSCALE address, goes through CONNECTING / CHECKING VERSION / SYNCING CLOCKS to LOBBY, and the match plays to shared results"
    why_human: "Needs Tailscale installed and real friend PCs behind home routers; only localhost ENet is automatable"
  - test: "Lobby ready + song-match display with a missing and a changed song (test 2)"
    expected: "MISSING / CHANGED / OK show per row, start gate names the blocker, Start Match unlocks when all ready"
    why_human: "Visual check across two real PCs with different libraries"
  - test: "Synced start by ear and F3 SKEW over a real link (test 3)"
    expected: "DIVE IN countdown agrees, music starts together by ear; record SKEW"
    why_human: "Perceptual; real-link clock jitter"
  - test: "Torpedo telegraph >= 1 beat, payload on beat, 2-beat vs 1-beat flight feel; LANDED LATE MAX (tests 4, 5)"
    expected: "Warning at least 1 beat before impact, payload lands on the beat, no visible pop-in"
    why_human: "Feel judgement and real-link latency"
  - test: "Disconnect mid-song and host leaving / host cable pull (tests 6, 7)"
    expected: "LEFT + killfeed, match continues; HOST LEFT dialog on quit; NO HOST SIGNAL then CONNECTION LOST on cable pull"
    why_human: "4 s host-loss watchdog has no real-process test (smoke only kills a client)"
  - test: "Windows Firewall prompt on first host, ONLINE_SETUP.md clarity on a friend PC with the rebuilt 446 MB zip (tests 8, 11, 14)"
    expected: "Friend connects using only the guide; Autocharter pack auto-installs from the bundled folder"
    why_human: "OS prompt and a non-developer reading the guide"
---

# Phase 4: Online Play Verification Report

**Phase Goal:** 2-4 friends on separate PCs can play the same song at once and feel each other's torpedoes mid-song.
**Verified:** 2026-10-20T22:00:11Z
**Status:** human_needed
**Re-verification:** No (initial verification)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | (SC1, NET-01, NET-07) Host a lobby, 1-3 others join from their own PCs over the internet, with a documented no-cost setup that works behind home routers | VERIFIED (code + localhost); real internet = human | `NetSession.host()/join()` (net_session.gd:290,321) over `ENetTransport`; auth/version check `auth_refusal_for` (548) via `_on_auth_request` (998); 4-process localhost smoke (host + 3 clients) passes. `docs/ONLINE_SETUP.md` (209 lines): Tailscale first ("Everything here is free", free Personal plan), ZeroTier, LAN, port forward last resort, Firewall, troubleshooting by error title. Shipped in the zip. `NetAddress` is Tailscale-first. |
| 2 | (SC2, NET-02) Lobby shows each player's ready state and whether they have the selected song (hash match) | VERIFIED | `set_ready` (395), client `_check_song` (1643) computes `VersusSig.of(chart) == _song.sig` -> ok / changed / missing and sends SONG_STATUS; `LobbyState` start gate; tests `test_gate_missing_single_and_many`, `test_gate_changed_when_first_bad_is_changed`; lobby_screen calls start_match / set_ready / host_set_song / kick. |
| 3 | (SC3, NET-03) When the host starts, all songs begin in sync via Conductor.begin lead-in | VERIFIED | Host `_maybe_start` (1194) schedules `host_start_ticks = now + START_DELAY_S` once all LOADED; client `_on_start` maps it with `clock.offset_us()`; `lead_in_for_start` (705) refuses unsynced/late/too-far leads (START_LATE -> abort to lobby); gameplay `_on_start_scheduled` -> `_begin_online` -> `conductor.begin(chart.audio_stream, lead_s)` (gameplay.gd:350). Smoke start spread 1.5 ms (drop) and within the 20 ms bound (full); net skew 1.3-7.8 ms. |
| 4 | Pinned timing core untouched (conductor/clock_model/input_judge/hull_score at 72e21ce, judge_config at 2c2e54c) | VERIFIED | `tools/check_timing_gate.ps1` -> TIMING GATE OK (run before and after the full suite). |
| 5 | (SC4, NET-04) Torpedo, hull, elimination and score events reach other players mid-song and torpedoes land on the intended beat (host-authoritative HostInputQueue) | VERIFIED (automated); feel = human | `HostInputQueue` (334 lines): horizon D, sorted release then `sim.update`, `drop_seat`, approach margin `margin_for` (MARGIN_CAP_S now D_MAX + L_CAP + 0.05 = 0.5 s after WR-01). Session wires INPUTS -> `push_item`, EVENTS -> `NetClientChannel.receive`. `VersusController` picks `HostInputQueue.new` / `RemoteReferee.new`. Smoke: host/client event digests identical (142 events full, 127 drop), landed_late_max 0.0 ms, late inputs 0, rejected 0. NetMatchHarness covers latency determinism and telegraph >= 1 beat. |
| 6 | (SC5, NET-05) A player who disconnects counts as eliminated while the match continues | VERIFIED | `_on_peer_left` (1037): LOADING/PLAYING -> `_queue.drop_seat(seat, "disconnected")` (CR-02 fixed the LOADING-after-bind case), `_check_results_due`. Smoke drop scenario: C3 killed mid-song, `seat 3 LEFT`, the rest finish with 4-row results and matching digests. |
| 7 | (SC5, NET-06) If the host leaves, everyone sees a message and the match ends cleanly | VERIFIED (unit/in-process); cable pull = human | Host `leave()` sends MATCH_ABORT {host_left} in LOADING/PLAYING, LOBBY_CLOSED otherwise, with a flush grace; client `_host_lost` -> `host_left` signal -> gameplay `_on_host_left` -> `HostLeftDialog` with last standings; 4 s watchdog -> CONNECTION LOST. Tests: test_host_leave_in_match_sends_match_abort, test_stalled_host_link_weak_then_host_left_once, test_enet_session_host_leave_closes, test_host_left_stops_the_song_and_shows_last_standings, test_lobby_closed_while_diving_shows_host_left_dialog. Real-process host loss not smoke-tested (F-4). |
| 8 | Validation choke point (ASVS L1): every packet passes NetCodec.decode -> validate | VERIFIED | All 4 receive paths in net_session.gd (1001, 1079, 1466, 1535) call `NetCodec.decode`; decode checks size bounds then plain `bytes_to_var` (no object decoding) then per-type schema validate; no `@rpc` anywhere; `RawGatePeer` restricts SceneMultiplayer to RAW + SYS AUTH (WR-09); clients reject packets not from HOST_ID; names/text cleaned (CR-03). test_net_codec includes fuzz. |
| 9 | Per-peer abuse limits (input bucket, control throttle, strikes) | VERIFIED | INPUT_BURST/INPUT_DEBT, CTL_PER_S/CTL_BUCKET, `_strike`; smoke: no strike disconnects. |
| 10 | Online UI flow: Play Online menu, connect dialog, lobby, start overlay, leave overlay, link chip, online results | VERIFIED (exists + wired); visuals = human | src/ui/online/* (connect_dialog, lobby_screen, start_sync_overlay, leave_overlay, host_left_dialog, online_menu, sonar_text_field); hud.gd chip_rects slot 0 "NO HOST SIGNAL" (status_chips.gd); all plan artifacts pass verify.artifacts (18/18 plans). |
| 11 | Friend zip v0.7.0 exists and is current | VERIFIED | build/dist/UNDERTOW-playtest-v0.7.0.zip, 467,661,357 bytes, sha256 dde997fc...ba1ca4 (matches 04-18-SUMMARY). Zip contains UNDERTOW.exe (sha256 82557837...db4d1e7, same as the staged exe), README, TESTER-CHECKLIST, ONLINE_SETUP.md, "Autocharter Pack/" (4 parts + SHA256SUMS). |
| 12 | The zip's Autocharter pack download URL points to the published, live release | VERIFIED | Loaded the exported pck with Godot 4.7.2 (`--main-pack UNDERTOW.exe`) and printed `PackSpec.BASE_URL` = `https://github.com/ccxmxrgo/Undertow-autocharter/releases/download/autocharter-pack-v1/`. Live: all 4 parts + SHA256SUMS.txt return HTTP 200; Content-Length of rt-core/rt-torch/models matches PackSpec sizes; downloaded app.zip sha256 19d1f2e2... matches PackSpec; release SHA256SUMS.txt matches all 4 PackSpec hashes. |

**Score:** 12/12 truths verified by automation. Real-internet behaviour needs human UAT.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| src/net/net_codec.gd (556) | decode/validate choke point | VERIFIED | used by session + harness |
| src/net/enet_transport.gd, raw_gate_peer.gd, mem_transport.gd, net_transport.gd | transport seam | VERIFIED | ENet real path in smoke |
| src/net/clock_sync.gd, lobby_state.gd, net_address.gd, versus_sig.gd, net_protocol.gd | core net | VERIFIED | |
| src/autoload/net_session.gd (1932) | lobby + match flow | VERIFIED | |
| src/versus/host_input_queue.gd (334), RemoteReferee, NetHost/ClientChannel, net_match_harness.gd | authority | VERIFIED | |
| src/ui/online/* , gameplay.gd online path, versus_controller.gd online backends | UI + wiring | VERIFIED | |
| docs/ONLINE_SETUP.md | no-cost connectivity guide | VERIFIED | in zip |
| tools/net_smoke.ps1 | 4-process smoke | VERIFIED | NET SMOKE OK |

`gsd-sdk verify.artifacts`: all 18 plans all_passed.

### Key Link Verification

`gsd-sdk verify.key-links` reported 14 unverified links; 13 were tool regex-escaping errors ("Invalid regex pattern") and 1 a pattern-text mismatch. All re-checked manually with grep and found wired: bytes_to_var in codec; UiKit.register_fx(self) in sonar_text_field.gd:85; sim.update in host_input_queue; NetCodec.decode x4 in session; hud chip_rects + LINK slot; NetCodec encode/decode x6 in harness; push_item, .receive, drop_seat in session; HostInputQueue.new / RemoteReferee.new in versus_controller; lead_in_for_start, pump_match, setup_online in gameplay; start_match/set_ready/host_set_song/kick in lobby_screen; debug_stats in debug_overlay.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Timing gate | `powershell -NoProfile -File tools/check_timing_gate.ps1` | TIMING GATE OK (twice) | PASS |
| Full gdUnit suite | `tools/run_tests.ps1` (GODOT_BIN 4.7.2 console) | 145 suites, 2154 cases, 0 errors, 1 failure: test_bot_frequency::test_four_veteran_bots_earn_2_to_4_rewards_on_every_bundled_song (known D-UAT-01). The known-flaky pause_overlay / review_fixes preroll / pack_installer update_app_only all passed in this run | PASS (known red only) |
| 4-process localhost online play | `powershell -NoProfile -File tools/net_smoke.ps1` | NET SMOKE OK; full + drop scenarios; digests match; start spread 1.5 ms (drop); landed_late_max 0.0 ms; rejected 0; seat 3 LEFT; real user data unchanged; WASAPI audio | PASS |
| Shipped exe has the live pack URL | Godot `--main-pack UNDERTOW.exe --script probe` | PACK_URL=https://github.com/ccxmxrgo/Undertow-autocharter/releases/download/autocharter-pack-v1/ | PASS |
| Release assets live | curl -I on 4 parts + SHA256SUMS | HTTP 200, sizes and hashes match PackSpec | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` declared for this phase. The phase's runnable probes are net_smoke.ps1 and check_timing_gate.ps1 (above).

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| NET-01 | Host + 1-3 join over the internet | SATISFIED (localhost) / NEEDS HUMAN (internet) | Truth 1 |
| NET-02 | Lobby ready + song hash match | SATISFIED | Truth 2 |
| NET-03 | Synced start | SATISFIED | Truth 3 |
| NET-04 | Events reach others, land on beat | SATISFIED (automated) / feel NEEDS HUMAN | Truth 5 |
| NET-05 | Disconnect = eliminated, match continues | SATISFIED | Truth 6 |
| NET-06 | Host leaving ends cleanly with message | SATISFIED (in-process); cable pull NEEDS HUMAN | Truth 7 |
| NET-07 | Documented working way behind home routers | SATISFIED (doc) / NEEDS HUMAN (real Tailscale run) | Truth 1 |

No orphaned requirements: all of NET-01..07 map to Phase 4 and are claimed by plans.

### Anti-Patterns Found

None blocking. No TBD/FIXME/XXX in phase files. "placeholder" hits in sonar_text_field.gd are the text field's hint text (intended). Review info items IN-04, IN-06..IN-09, IN-11, IN-12 were left open by design (04-REVIEW-FIX.md "Not in scope"); none affects a success criterion.

Note: tools/run_tests.ps1 also picks up the untracked local probes tests/zz_*.gd; they did not fail and are not committed.

### Human Verification Required

See 04-HUMAN-UAT.md tests 1-13 plus the new test 14 and the verifier addendum (rebuilt zip sha, follow-ups F-1/F-3/F-5 now addressed by the review fixes).

### Gaps Summary

No code gaps. Every roadmap success criterion is implemented, wired and exercised by unit, harness and real-ENet 4-process localhost tests. What remains is the real internet: Tailscale between real PCs behind home routers, perceived sync, torpedo feel, firewall prompt, and the host cable-pull watchdog. Status is human_needed.

---

_Verified: 2026-10-20T22:00:11Z_
_Verifier: Claude (gsd-verifier)_
