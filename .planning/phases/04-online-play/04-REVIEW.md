---
phase: 04-online-play
reviewed: 2026-10-20T14:55:36Z
depth: deep
diff_base: 0d012a1
files_reviewed: 33
files_reviewed_list:
  - src/autoload/net_session.gd
  - src/autoload/settings.gd
  - src/net/net_protocol.gd
  - src/net/net_codec.gd
  - src/net/net_transport.gd
  - src/net/enet_transport.gd
  - src/net/lobby_state.gd
  - src/net/clock_sync.gd
  - src/net/versus_sig.gd
  - src/net/net_autotest.gd
  - src/versus/referee.gd
  - src/versus/host_input_queue.gd
  - src/versus/remote_referee.gd
  - src/versus/net_host_channel.gd
  - src/versus/net_client_channel.gd
  - src/versus/match_sim.gd
  - src/versus/sub_rig.gd
  - src/versus/game_event.gd
  - src/ui/gameplay.gd
  - src/ui/versus/versus_controller.gd
  - src/ui/versus/versus_results_screen.gd
  - src/ui/versus/event_banner.gd
  - src/ui/versus/killfeed.gd
  - src/ui/versus/status_chips.gd
  - src/ui/online/lobby_screen.gd
  - src/ui/online/online_menu.gd
  - src/ui/online/connect_dialog.gd
  - src/ui/song_select.gd
  - src/ui/main_menu.gd
  - src/ui/hud.gd
  - src/ui/debug_overlay.gd
  - src/ui/palette.gd
  - tools/dist.ps1
findings:
  critical: 3
  warning: 9
  info: 12
  total: 24
status: issues_found
---

# Phase 4: Code Review Report

**Reviewed:** 2026-10-20T14:55:36Z
**Depth:** deep (call chains traced NetSession <-> Gameplay <-> VersusController <-> HostInputQueue/RemoteReferee <-> MatchSim, and LobbyScreen <-> SongSelect <-> ScreenTransition)
**Diff:** `git diff 0d012a1 HEAD -- src tests tools scenes docs project.godot` (tests were read for coverage only)
**Files Reviewed:** 33
**Status:** issues_found

## Summary

The security base is solid. Every peer payload, including the pre-auth AUTH and the client-side AUTH_REPLY, goes through `NetCodec.decode`. That function checks the size before calling plain `bytes_to_var`, and object decoding is never used. `server_relay` is false, and seats always come from `LobbyState.seat_of(peer)`. PINGs and INPUTS are rate limited, and 3 strikes disconnect the peer. Packets from kicked peers are ignored during the grace period, refused peers are dropped one poll after the reply, and names are cleaned on both ends. The pinned timing files are byte-identical: `git diff 72e21ce HEAD` on conductor/clock_model/input_judge/hull_score and `git diff 2c2e54c HEAD` on judge_config are empty. Offline versus is unchanged in behaviour. `SubRig.approach_s` now also calls `MatchSim.set_approach`, which writes the same PlayerState field.

The match lifecycle has three correctness defects that ship-block real 2-4 player use:

1. **Seat gaps create a phantom sub.** If seat 1 leaves the lobby while seat 2 stays, every peer builds an immortal, nameless player. Every client then also rejects RESULTS.
2. **A client that drops during LOADING is never eliminated.** Once the host has bound the match, nobody drops that seat.
3. **Long song titles break RESULTS.** RESULTS carries the unclipped chart title, but titles can be up to 120 chars against a 64-char codec cap, so every client drops RESULTS.

The warnings cover these areas:
- **Navigation:** scene changes are dropped while ScreenTransition is busy, which can orphan the session or start an offline dive with the match chart.
- **DONE barrier:** the client's last INPUTS can be lost when RESULTS are computed.
- **Lossy links:** they can turn into input loss and strike-kicks.
- **Follow-ups:** F-1 and F-3.

Follow-up verdicts: **F-1 is a real bug** (WR-01, concrete fix below). **F-3 is a real spec gap** (UI-SPEC 9.4 requires the line; WR-07, concrete fix below). F-2 is not a code bug (IN-01). F-4 has correct code, but there is an untested false-positive path when the host stalls in LOADING (WR-06). F-5 is a process gap, and the rate limiter makes it riskier than it looks (WR-05, IN-03).

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: A seat gap in the roster creates a phantom, immortal player, and every client rejects RESULTS

**File:** `src/ui/versus/versus_controller.gd:195` (with `src/autoload/net_session.gd:1648-1664`, `src/net/lobby_state.gd:98-106`)
**Issue:** LobbyState puts each joiner in the lowest free seat and never compacts. Host A is seat 0, B is seat 1 and C is seat 2. If B leaves, the roster is seats `[0, 2]`. `_spec_from_load` then builds `names` with `resize(top + 1)`, which gives `["A", "", "C"]`. `setup_online` loops `for s in range(names.size())` and creates a `PlayerState` for **every index**, including seat 1 with an empty callsign. On the host this phantom sits in MatchSim with full hull (hull only changes through client STATUS reports), so:
- LAST_STANDING can never fire.
- AUTO targeting can pick it, so torpedoes are wasted.
- It gets a periscope column and a results row, and it can win on hull.

Its RESULTS row then has `"name": ""`. `NetCodec._row_ok` runs `_name_ok("")`, which is false, so **every client rejects RESULTS** and sits on WAITING FOR RESULTS until the host presses Back to Lobby. Gameplay's `_seats()` uses `spec.seats` correctly, but the controller ignores it. No test covers a gapped roster.
**Fix:** Build players from the roster seats, not from the name indices:
```gdscript
var seats: Array = spec.get("seats", [])
for s in range(mini(spec_names.size(), NetProtocol.MAX_SEATS)):
	if not seats.is_empty() and not seats.has(s):
		names.append("")          # keep names indexable by seat
		continue
	var nm := spec_names[s]
	players.append(PlayerState.new(s, nm, s == local_seat))
	names.append("YOU" if s == local_seat else nm)
```
Add a NetMatchHarness test with roster seats `[0, 2]` that asserts LAST_STANDING fires and clients accept RESULTS.

### CR-02: A client that leaves during LOADING after the host bound the match is never eliminated

**File:** `src/autoload/net_session.gd:996-1003`
**Issue:**
```gdscript
if _queue != null:
	if state == State.PLAYING:
		_queue.drop_seat(seat, "disconnected")
elif state == State.LOADING:
	_left_seats[seat] = true
```
Gameplay calls `bind_host_match` inside `start()` while the state is still LOADING. From that point `_queue != null`, so a peer that leaves in LOADING (crash, quit, network loss, or a kicked peer whose 0.5 s grace overlapped Start) hits neither branch. `_maybe_start` then starts without it. The seat stays alive in MatchSim for the whole song with full hull, no PLAYER_LEFT reaches anyone, LAST_STANDING is blocked, and the results show it as a survivor. The tests only cover a leave before the bind (`_left_seats`).
**Fix:** In LOADING, always defer the drop and apply it in `bind_host_match` or at START:
```gdscript
if state == State.PLAYING and _queue != null:
	_queue.drop_seat(seat, "disconnected")
elif state == State.LOADING:
	if _queue != null:
		_queue.drop_seat(seat, "disconnected")   # sim time is TIME_MIN_S; harmless
	else:
		_left_seats[seat] = true
```
Add a test: bind, client leaves in LOADING, then START, then assert PLAYER_LEFT and `alive == false`.

### CR-03: RESULTS carries the unclipped chart title and artist, so clients drop RESULTS for long titles

**File:** `src/autoload/net_session.gd:778-796` (with `src/ui/versus/versus_controller.gd` `finish`, `src/net/net_codec.gd:257-260`)
**Issue:** `host_send_results` copies `data.title` and `data.artist` straight from `chart.title` and `chart.artist`. Those values pass through `SongIni.sanitize_text`, which caps at **120** chars and keeps C1 control characters (128-159). `_v_results` requires `_str_ok(title, MAX_TEXT = 64)` with no C1 characters, so a 65-120 character title fails it. Long titles are common for "Chart a Song" imports, where the title is the audio file's basename. The client then silently discards RESULTS (`decode` returns `{}`), and the host has already moved to RESULTS. The client stays on WAITING FOR RESULTS, and its results screen never appears. The LOBBY path clips with `_text()`, but RESULTS does not.
**Fix:** In `host_send_results`, sanitize the display fields with the existing helpers before sending:
```gdscript
for k in ["title", "artist"]:
	if base.has(k):
		base[k] = _text(base[k])
if base.has("host_name"):
	base["host_name"] = NetCodec.clean_name(base["host_name"])
```
Also make `_text` drop C1 characters (it already does) and clip to MAX_TEXT. Add a test with a 100-character title.

## Warnings

### WR-01: F-1 is real. The overlay margin cap (0.3 s) is below D + L + frame on capped links

**File:** `src/versus/host_input_queue.gd:23-24, 63-65, 293-297`
**Issue:** `margin_for = min(D + rtt_p90/2 + 33 ms, 0.3)`, with `D = clamp(rtt_p90/2 + 53 ms, 60, 200 ms)`. Uncapped, the margin is `rtt_p90 + 86 ms`, which passes 0.3 s once `rtt_p90 > 214 ms` (DERP relays across regions). Ghost Notes and Depth Charge overlay notes then start up to 50+ ms before LANDED arrives, so they pop in. The 33 ms term also covers only one frame. In practice the client applies events in `_client_pump`, which runs *after* `versus.update(t)` in the same frame, so the real delay is `D + L + 2F`. `payload_span` only moves the window start to a later whole beat and keeps the full bar length. A larger margin therefore never shortens a payload, and raising the cap is safe.
**Fix:**
```gdscript
const MARGIN_EXTRA_S := 0.050                       # two 60 Hz frames + jitter
const L_CAP_S := 0.25                               # beyond this the lobby already warns HIGH LATENCY
const MARGIN_CAP_S := NetProtocol.D_MAX_S + L_CAP_S + MARGIN_EXTRA_S   # 0.5 s
```
Keep the HIGH LATENCY lobby warning as the user-facing signal past `L_CAP_S`. Add a NetMatchHarness case at RTT p90 300 ms that asserts `landed_late` is below the overlay lead.

### WR-02: Scene changes are dropped while ScreenTransition is busy, so the session can be orphaned or an offline dive can start with the match chart

**File:** `src/ui/gameplay.gd:155-160, 829-835, 953-958, 134`; `src/ui/online/lobby_screen.gd:463-494`; `src/ui/screen_transition.gd:99-101`
**Issue:** `ScreenTransition.change_scene` returns `false` and does nothing while a wipe is running, and no caller checks the result. There are two concrete failures:
- **(a) Host audio error.** If the host's chart has no audio stream, `start()` (inside `_ready`, mid-wipe) calls `report_load_failed`. That aborts to the lobby synchronously, and `_on_match_aborted` calls `_go_lobby()`, which is dropped. The host stays on the audio-error label. `_show_audio_error`'s timer then sends it to the **main menu**, while NetSession is still hosting a LOBBY with clients connected and no lobby UI.
- **(b) Abort during the lobby-to-gameplay wipe.** A LOAD_FAIL or load-timeout ABORT_TO_LOBBY can arrive after `LobbyScreen._on_match_loading` started the wipe but before Gameplay's `_ready`. Nobody is listening at that point: the lobby is `_leaving` and Gameplay is not built yet. In `_ready`, `pending_match()` is `{}` again because the state is back to LOBBY, so the code falls through to `start(c, a, pending_intro)`, which is an **offline solo dive with the match chart**, while the session sits in LOBBY. The next `start_match` then times out on this peer.

**Fix:** Give Gameplay a one-shot static `Gameplay.pending_online := true`, set by the lobby next to `pending_chart`. In `_ready`, if `pending_online` is set and `pending_match()` is empty, navigate back to the lobby (or Play Online) instead of falling through. For every online navigation, use a helper that retries on the next idle frame when `change_scene` returns false:
```gdscript
func _goto(path: String) -> void:
	if navigate.is_valid(): navigate.call(path); return
	if not ScreenTransition.change_scene(path):
		await ScreenTransition.swapped   # or get_tree().process_frame loop until idle
		ScreenTransition.change_scene(path)
```

### WR-03: Host closes the lobby while a client is still in PLAYING, and the client is stuck on a dead session

**File:** `src/ui/gameplay.gd:838-841`; `src/autoload/net_session.gd:1449-1450`
**Issue:** The host can be in RESULTS while a client is still in PLAYING. This happens when the client's song ends later, when the DONE deadline passed, or when RESULTS was rejected (CR-03). If the host then closes the lobby, it sends LOBBY_CLOSED. The client runs `_leave_with("closed")`, the session goes OFFLINE, and the `left_lobby` signal fires. `Gameplay._on_left_lobby` only acts when `versus_results` exists, so the client keeps showing WAITING FOR RESULTS with no dialog. Its only exit is Esc, then Leave Match.
**Fix:** In `_on_left_lobby`, if no results screen is up, fall through to `_on_host_left("host_left")` so the HOST LEFT dialog shows the last known standings.

### WR-04: The DONE barrier can compute results before the client's final INPUTS reach MatchSim

**File:** `src/autoload/net_session.gd:1074-1077, 1209-1215, 1183-1192`
**Issue:** A client sends its final INPUTS flush and DONE in the same frame, so both arrive in the same host `transport.poll()`. INPUTS only go into `_inbox`, and `_inbox` is drained into the queue only in `_host_pump`. DONE then calls `_check_results_due` and `results_due`, and from there `Gameplay._host_results`, `VersusController.finish` (`queue.pump(t + d)`) and the standings, all inside the same poll. The last batch (status and judgments) is never applied. `host_send_results` then moves to RESULTS and `_inbox` is discarded. The impact today is small because the last 0.5 s has no notes, but the barrier's guarantee is broken and the final STATUS can be lost.
**Fix:** Drain `_inbox` into `_queue` at the top of `_check_results_due`, before emitting `results_due`, or make `report_done` / `results_due` deferred to the next `_host_pump`.

### WR-05: The INPUTS rate limit drops legitimate bursts after a network stall and strikes the peer. Strikes never decay

**File:** `src/autoload/net_session.gd:1161-1170, 1230-1236`
**Issue:** The bucket refills by *host arrival time* and holds 240 tokens, which is 1 s. After a lossy-link stall (ENet holds reliable packets until the retransmit succeeds), a backlog arrives in one poll. Items beyond the bucket are **dropped** (`items.slice(0, n)`), not deferred, and the peer gets a strike. Dropped judgments and STATUS silently desync the host's standings from the client's own hull and score. Strikes are never reset, not on `_to_lobby` and not per match, so three stalls over a session kick a friend. The research rate (240 items/s) was meant as an abuse cap, not as a burst size. F-5 (no lossy-link run) means this path is untested.
**Fix:** Size the bucket to the D-23 burst (`MAX_INPUTS_PER_S * 4`), or rate-limit on the *item timestamps* span instead of arrival time. Queue rather than drop when an overflow is under 2x the cap. Only strike on sustained overflow. Reset `strikes` and the token buckets in `_clear_match`.

### WR-06: A host main-thread stall of 4 s or more during LOADING trips the client watchdog (F-4 false positive)

**File:** `src/autoload/net_session.gd:1304-1312`
**Issue:** In LOADING the host builds the chart (`build_chart`) and swaps scenes on its main thread, and NetSession's `_process` (which sends pings) cannot run during that time. If this takes longer than `WATCHDOG_S` (4 s), for example on a cold-cache HDD, a large imported chart, or a slow PC, every client fires `host_left("connection_lost")` and leaves, even though the host is fine. The watchdog was only unit-tested with a silent host, never with a host that is slow in LOADING.
**Fix:** While `state == LOADING`, use `LOAD_TIMEOUT_S + START_DELAY_S` as the silence limit. Keep 4 s in PLAYING and RESULTS. Rely on `server_lost` (the ENet timeout) for real drops in LOADING.

### WR-07: F-3 is real. "Host is choosing a song." is never sent while the host is in Song Select (UI-SPEC 9.4 requires it)

**File:** `src/ui/online/lobby_screen.gd:1331-1346`; `src/autoload/net_session.gd` (no API)
**Issue:** The line only appears locally, at `host()` and when a client enters the lobby with no song. UI-SPEC 9.4 says clients see it while the host is in Song Select. The client log codec already accepts the code (`log_text("choosing")`).
**Fix:**
```gdscript
# net_session.gd
## Host in LOBBY: tells every client the host opened Song Select (UI-SPEC 9.4).
func host_choosing() -> void:
	if _host_lobby():
		transport.send(0, NetCodec.encode({"type": NetProtocol.NOTICE, "code": "choosing",
			"name": "", "n": 0}))
# lobby_screen.gd open_song_pick(), before _go(SONG_SELECT_SCENE):
	_call(&"host_choosing", null)
```
Send it to clients only. The host does not need a log line for its own action. Add a test.

### WR-08: Unthrottled control messages amplify into NOTICE broadcasts and log churn

**File:** `src/autoload/net_session.gd:1044-1057, 1094-1101`
**Issue:** Only PING and INPUTS have rate limits. A peer that toggles READY or flips SONG_STATUS between missing and changed in a loop makes the host broadcast a NOTICE to **every** peer per packet. Each NOTICE fills every lobby log and plays its line. LOBBY rebroadcasts are throttled at 0.1 s, but NOTICEs are not. The same flapping happens with `high_latency` when a peer's p90 jitters around 250 ms, because the notice re-fires on every false-to-true edge. Even under the friends model (ASVS V5 rate limits), this is a cheap DoS on the lobby UI.
**Fix:** Add a per-peer control token bucket (for example 10 msgs/s, burst 20). Drop the overflow silently, and strike only on a sustained flood. Debounce `high_latency` with hysteresis, for example notify when above 250 ms and re-arm only below 220 ms or after 10 s.

### WR-09: Non-RAW SceneMultiplayer commands from members bypass the NetCodec choke point and strikes

**File:** `src/net/enet_transport.gd:60-73`
**Issue:** Pointing `root_path` at a missing node stops RPC, spawn and path-cache packets from touching the tree. They still reach SceneMultiplayer's handlers, though, and each one fails with an engine `ERR_FAIL_*` print (for example "root node not found" in `process_simplify_path`). Those packets never reach `peer_packet`, so they are never counted, never struck, and never cause a disconnect. An authenticated peer can flood them and grow stdout and `user://logs/godot.log` without limit (Godot rotates log files by count, not size). The research's "single choke point" (V1) does not hold for this path.
**Fix:** Drive `ENetMultiplayerPeer` directly (`get_packet` / `put_packet` with `transfer_channel`), with no SceneMultiplayer in the data path. Auth can be a first-message state in NetSession. Alternatively, wrap it in a `MultiplayerAPIExtension` that only accepts the RAW command byte and strikes anything else. At minimum, document the risk and accept it under the friends model.

## Info

### IN-01: F-2, the clock-sync bound loosened in tests, is not a code bug
**File:** `src/net/clock_sync.gd:30-39`
**Issue:** The estimator (median offset of the 5 lowest-RTT samples among the last 32) is standard. Its error is bounded by path asymmetry, which no NTP-style method removes. The offset is frozen at START (`_on_start`), so mid-match drift is not corrected, by design (anti-pattern 6). **Fix:** Accept the result. Optionally use only samples from the Ready burst for the START offset, and record F3 SKEW in UAT test 3.

### IN-02: F-4 host-loss watchdog: the code path is correct
**File:** `src/autoload/net_session.gd:1304-1312, 1410-1418`
**Issue:** The watchdog, `server_lost` and MATCH_ABORT all go through `_host_lost`, which runs once and leaves the session OFFLINE before any signal fires. The remaining risk is the LOADING false positive (WR-06) and real-world tuning in UAT test 7.

### IN-03: F-5 (no lossy-link run) is a process gap, but it hides WR-05
**Issue:** Run `tools/net_smoke.ps1` once with clumsy (2-5 % loss, 50-150 ms) on one client before calling online play done, and assert `strike_kicks == 0` and an identical host log.

### IN-04: Kick has no ban, and a kicked peer stays seated during the 0.5 s grace
**File:** `src/autoload/net_session.gd:354-364`
**Issue:** The kicked friend can rejoin at once with a new peer id. During the grace period the row still counts for `start_gate` and the LOAD roster, which feeds CR-02. **Fix:** Remove the row from `_lobby` at kick time, keep the peer in `_kicked` until it disconnects, and optionally refuse its name or address for the rest of the session.

### IN-05: START has no upper bound on the lead
**File:** `src/autoload/net_session.gd:1590-1599, 666-680`
**Issue:** A buggy host clock or offset can schedule a start minutes away, and the client would wait in silence. **Fix:** Treat `lead > START_DELAY_S + 2 s` as START_LATE.

### IN-06: Clients honour the autotest switches LOAD.autoplay and max_song_s in normal builds
**File:** `src/ui/versus/versus_controller.gd` (`setup_online` autoplay), `src/ui/gameplay.gd` `online_end_time`
**Issue:** A host can make every client autoplay or end early. Under the friends model this is low risk, but it is surprising. **Fix:** Ignore both unless a `NetAutotest` node exists on this peer.

### IN-07: The 16 KiB cap applies after ENet has reassembled the packet
**File:** `src/net/net_codec.gd:51-55`
**Issue:** ENet's own maximum packet size (32 MiB default) is the real bound before decode, so a member can force large allocations. This is accepted under the friends model. Note it in the threat model.

### IN-08: MATCH_END standings rows use exactly MAX_NESTED_KEYS (8) keys
**File:** `src/versus/match_sim.gd:827-828`, `src/net/net_codec.gd:27`
**Issue:** If anyone adds a ninth key to `standings()`, every client silently rejects MATCH_END. **Fix:** Add a test that round-trips every GameEvent type MatchSim can emit through `validate_event`, or raise the cap with headroom.

### IN-09: Duplicate or forged IN_JUDGED and IN_EXTRA are accepted
**File:** `src/versus/host_input_queue.gd:261-264`
**Issue:** A client can send the same note several times, or extra Perfects, and charge its meter. This is outside the friends trust model. A cheap check would be a host-side seen-set per `(seat, note_index)`.

### IN-10: Seats without host-side RTT samples get a margin of 0
**File:** `src/autoload/net_session.gd:590-595`
**Issue:** `margins` only contains seats with samples, so a seat without any gets no D cover and its overlay notes pop in by D + L. **Fix:** Default every roster seat to `margin_for(d_s, d_s)`.

### IN-11: Small offline-visible changes
**File:** `src/ui/debug_overlay.gd:9-10`, `src/ui/palette.gd:76`
**Issue:** The F3 panel is now 580 px tall even offline, with an empty net label, and `STAGGER_MENU` dropped from 0.035 to 0.030 for every menu. Both changes are intended by the UI-SPEC, and neither changes behaviour. Shrink the panel when offline if the extra shading is unwanted.

### IN-12: `host_match` on a stale session reuses the port while the retired transport is still bound
**File:** `src/ui/online/online_menu.gd:657-659`, `src/autoload/net_session.gd:345`
**Issue:** `leave()` retires the server with a 0.1 s grace, and `host(port)` runs in the same frame, which can fail with "port busy" on some stacks. **Fix:** Close the retired host transport immediately when re-hosting, or retry `host()` on the next frame.

---

_Reviewed: 2026-10-20T14:55:36Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
