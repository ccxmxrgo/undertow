---
phase: 03-offline-versus
plan: 09
subsystem: versus-hud
tags: [hud, reward-socket, target-readout, reward-popup, status-chips, wreck, feedback]
requires: ["03-01", "03-02", "03-03"]
provides:
  - "RewardSocket (meter arc, held reward, waiting/launch/lost, queue pip, debris variant, name line)"
  - "TargetReadout (AUTO TARGET / TARGET / ATTACKERS / DEBRIS TARGET, refusal and bounty flashes)"
  - "RewardPopup (REWARD READY / SOLO PRIZE / PRIZE QUEUED, FIFO behind a blocker)"
  - "StatusChips (events -> Hud.set_chip)"
  - "Hud chip stack (set_chip, set_solo_dive, set_wreck)"
  - "Feedback.on_ghost_hit and Feedback.overclock"
affects: [03-14, 03-15]
tech-stack:
  added: []
  patterns: ["event-only views with bind(channel, seat, ...) and on_event(e)", "step(dt) driven animation timers", "ordered chip stack keyed by CHIP_ORDER"]
key-files:
  created:
    - src/ui/versus/reward_socket.gd
    - src/ui/versus/target_readout.gd
    - src/ui/versus/reward_popup.gd
    - src/ui/versus/status_chips.gd
    - tests/test_reward_socket.gd
  modified:
    - src/ui/hud.gd
    - src/ui/feedback.gd
    - tests/test_hud_gauges.gd
    - tests/test_feedback_popup.gd
decisions:
  - "Hud chip keys are the CHIP_ORDER keys (NO-FAIL, AUTOPLAY, SOLO DIVE, PLACE, BOUNTY, DECOY, OVERCLOCK, BALLAST, IMMUNE); chip_rects() and mode_chips use these keys (they equal the old chip texts for NO-FAIL / AUTOPLAY)"
  - "AUTOPLAY alone now sits in slot 1 (y 824), not 864: UI-SPEC 5.3 says only visible chips take slots"
  - "A hidden chip leaves chip_rects() at once and its node fades out over DUR_BASE (chip_fade_tweens), then hides"
  - "RewardSocket counts debris shots from its own TORPEDO_LAUNCH {from: seat, debris: true} events; an optional METER 'debris_used' field overrides the count"
  - "RewardPopup chooses the {FIRE} label from its own _input (pad input -> gamepad label, key -> keyboard label), like match_setup_screen"
  - "HULL +p uses VersusConfig.ballast_restore_ratio (UI-SPEC: the percent from config), not the event amount"
  - "Ghost popups use a unique negative key, so they never merge into a chord popup; Overclock is captured per popup at birth"
metrics:
  duration: "~60 min (including a usage-limit pause)"
  completed: 2026-10-15
---

# Phase 3 Plan 09: Own-sub versus HUD Summary

The player's own versus HUD in the consoles. It has four event-only views: the reward socket, the target readout, the reward-ready popup, and StatusChips feeding a new ordered chip stack in Hud. It also adds the wreck caption, the GHOST judgment popup and the Overclock GOOD colour. Layout and timing follow UI-SPEC 5.1 to 5.5 and 7.2.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 RED | 4f33ab3 | test(03-09): add failing tests for RewardSocket, TargetReadout and RewardPopup |
| 1 GREEN | d54488c | feat(03-09): RewardSocket, TargetReadout and RewardPopup views |
| 2 RED | 5bd51ff | test(03-09): add failing tests for chip stack, StatusChips, wreck caption, GHOST and Overclock popups |
| 2 GREEN | dd4b840 | feat(03-09): right-console chip stack, StatusChips, wreck caption, GHOST and Overclock popups |

## Tests

- test_reward_socket 25/25, test_hud_gauges 61/61, test_feedback_popup 14/14, test_color_literals 7/7
- Also green: test_layout_keepout 5/5, test_effect_settings 9/9, test_gameplay_smoke 13/13
- `tools/check_timing_gate.ps1`: TIMING GATE OK
- Full suite not run (parallel-wave rule; 03-14/03-15 run it)

## bind() signatures and public API

```
RewardSocket (Control, RECT (272, 928, 80, 80), sibling drawn over TorpedoSocket)
  bind(channel: EventChannel, seat: int, cfg: VersusConfig)
  on_event(e), step(dt), name_label: Label
  name_text(), name_color(), arc_fraction(), arc_shown(), arc_visible(), arc_color(), ring_color(),
  breathing(), full_alpha(), waiting(), launching(), lost_flashing(), queue_pip_visible(), pip_color(),
  is_debris(), held(), icon_scale(), icon_alpha(), apply_effect_settings(), effect_counts()

TargetReadout (Control, RECT (248, 752, 144, 88))
  bind(channel: EventChannel, seat: int, names: PackedStringArray, training: bool)
  on_event(e), step(dt), caption_text(), caption_color(), value_text(), value_color(), glyph_scale(),
  keepout_rect(), apply_effect_settings(), effect_counts() -> {pulse}

RewardPopup (Control, full canvas via UiLayout.fill_rect, keepout_shapes() = (0, 516, 416, 82))
  bind(channel: EventChannel, seat: int, blocker: Callable = Callable())   # blocker() -> bool
  on_event(e), step(dt), showing(), queued_count(), caption_text(), name_text(), name_color(),
  pop_scale(), alpha(), fire_label(), last_pad, LIFE / HOLD_SEC / FADE_SEC, effect_counts() -> {pop}

StatusChips (Node, not an effect node)
  bind(channel: EventChannel, seat: int, hud: Hud, cfg: VersusConfig, chart: ChartData,
       player_count: int, training: bool)
  on_event(e), update(song_time), bars_left(t, until), static ordinal(place)

Hud additions
  set_chip(key, text, variant, glyph, visible), set_solo_dive(on), set_wreck(on), is_wreck(),
  chip_text(key), chip_variant(key), chip_glyph(key), CHIP_ORDER, CHIP_SLOTS (6), CHIP_MAX_W (208),
  chip_slide_tweens, chip_fade_tweens

Feedback additions
  var overclock: bool, on_ghost_hit(lane, payload_id := -1), GHOST_TEXT
```

## Notes for 03-14 (wiring)

- Add RewardSocket, TargetReadout and RewardPopup as Hud children after TorpedoSocket. Add StatusChips anywhere (it is a Node). Call `bind(...)` on each with the LoopbackChannel and the human seat.
- RewardPopup blocker: `func() -> bool: return streak_counter.popup_text() != ""`.
- Call `status_chips.update(conductor.song_time())` every frame. RewardSocket, TargetReadout and RewardPopup step themselves in `_process`.
- TargetReadout `names` should be the roster callsigns indexed by seat ("YOU" first). In training it shows "DRONE" for any target.
- On the local IMPLODED, call `hud.set_wreck(true)`. The socket and readout switch to debris on their own from the event.
- Practice/Solo Dive: call `hud.set_solo_dive(true)`. It was not wired into gameplay.gd here, because that file is not in this plan.
- Feedback: set `feedback.overclock` from BUFF_APPLIED/BUFF_ENDED OVERCLOCK for the local seat. Call `feedback.on_ghost_hit(lane, id)` from the ghost-hit path (03-07/03-08).
- MatchSim's debris METER (03-06) may add a `debris_used` field. The socket also counts debris launches itself.
- The new Hud children (socket, readout, popup) must still pass the test_layout_keepout scan once they are added. RewardPopup already has keepout_shapes(). The socket and readout are fixed-rect Controls inside the consoles.
- test_effect_settings should enumerate RewardSocket, TargetReadout and RewardPopup (UI-SPEC 12). All three call UiKit.register_fx in `_ready`.

## Deviations from Plan

**1. [Rule 1 - spec conformance] An existing test assertion changed: AUTOPLAY alone is now at y 824.** test_mode_chips_only_when_active expected 864. UI-SPEC 5.3 says only visible chips take slots, so AUTOPLAY alone packs to the top slot. NO-FAIL at 824 is unchanged. Commit 5bd51ff.

**2. [Rule 2] Hidden chips fade out.** UI-SPEC asks for a DUR_BASE fade-out. test_mode_chips_are_nodes_that_pop_in_at_their_rects now steps the fade tween before it checks `visible == false`. Commit 5bd51ff / dd4b840.

**3. Debris-use count.** METER has no debris_used field (03-03 schema), so the socket counts its own debris TORPEDO_LAUNCH events and accepts an optional `debris_used` field. Commit d54488c.

Line endings: a sed edit turned feedback.gd into LF. I converted it back to CRLF before committing (core.autocrlf is on, so the repo content was not affected).

## Known Stubs

None. Every view gets its data from events. Gameplay wiring is plan 03-14 by design.

## Threat Flags

None. No new network, file or auth surface. Event fields are read with `.get(default)`, unknown reward ids are ignored, and counts are clamped (T-03-23). Flashes are one-shot, and the breathing has a 1.6 s period (T-03-24).

## Self-Check: PASSED
