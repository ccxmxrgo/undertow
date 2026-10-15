---
phase: 03-offline-versus
reviewed: 2026-10-15T21:12:41Z
depth: deep
diff_base: 7c5572e
files_reviewed: 49
files_reviewed_list:
  - src/versus/match_sim.gd
  - src/versus/player_state.gd
  - src/versus/reward_meter.gd
  - src/versus/reward_bag.gd
  - src/versus/reward.gd
  - src/versus/game_event.gd
  - src/versus/event_channel.gd
  - src/versus/loopback_channel.gd
  - src/versus/sub_rig.gd
  - src/versus/bot_player.gd
  - src/versus/bot_profile.gd
  - src/versus/training_drone.gd
  - src/versus/payload_stack.gd
  - src/versus/payload_notes.gd
  - src/versus/medal_rules.gd
  - src/versus/match_setup.gd
  - src/versus/versus_config.gd
  - src/versus/match_harness.gd
  - src/core/versus_judge.gd
  - src/core/versus_hull.gd
  - src/core/versus_autoplay.gd
  - src/core/judge_config.gd
  - src/input/lane_input.gd
  - src/ui/gameplay.gd
  - src/ui/highway.gd
  - src/ui/hud.gd
  - src/ui/feedback.gd
  - src/ui/note_painter.gd
  - src/ui/pause_menu.gd
  - src/ui/main_menu.gd
  - src/ui/song_select.gd
  - src/autoload/settings.gd
  - src/audio/versus_sfx.gd
  - src/ui/versus/versus_controller.gd
  - src/ui/versus/versus_hud.gd
  - src/ui/versus/periscope_column.gd
  - src/ui/versus/periscope_panel.gd
  - src/ui/versus/killfeed.gd
  - src/ui/versus/incoming_alert.gd
  - src/ui/versus/event_banner.gd
  - src/ui/versus/edge_flash.gd
  - src/ui/versus/reward_socket.gd
  - src/ui/versus/reward_popup.gd
  - src/ui/versus/target_readout.gd
  - src/ui/versus/status_chips.gd
  - src/ui/versus/ink_cloud_layer.gd
  - src/ui/versus/ink_top_layer.gd
  - src/ui/versus/match_setup_screen.gd
  - src/ui/versus/versus_results_screen.gd
findings:
  critical: 2
  warning: 12
  info: 7
  total: 21
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-10-15T21:12:41Z
**Depth:** deep (cross-file: MatchSim <-> SubRig <-> BotPlayer <-> VersusController <-> views)
**Files Reviewed:** 49 source files in the `git diff 7c5572e HEAD -- src tests tools scenes` scope (tests were read only where they show what a finding slips past). build/, .planning and the uat-shots PNGs were skipped.
**Status:** issues_found

## Summary

I checked the Phase 3 rules engine against 03-SPEC reqs 1-14 and the D-01..D-33 defaults in 03-RESEARCH / 03-CONTEXT, then traced the live wiring (VersusController, SubRig, LaneInput, Gameplay) and the VersusHud view hot paths. I confirmed two findings by running headless probes against the real classes in Godot 4.7.2. The probes were scratch scripts outside the repo, and no source file was changed.

**Pinned timing files:** `src/core/conductor.gd`, `clock_model.gd`, `input_judge.gd` and `hull_score.gd` have no diff since 7c5572e. `src/core/judge_config.gd` changes only `perfect_regen` from 1.0 to 0.25 (D-29). The pins are intact.

**Rules versus SPEC.** These all match the spec as written:
- meter, slot and bag (reqs 1-3, 7)
- buffs (req 6)
- shields, immunity and the same-beat race (D-06/D-07)
- collisions (req 9), including the "arrived on the same beat is not a collision" edge
- Return to Sender (D-16/D-17)
- Solo Duel (req 11)
- debris (D-24/D-25)
- standings (D-22/D-23)
- medals (req 13)

The bounty rule has one real bug (CR-01): a bounty is silently lost when the first warhead is judged early. The reflection end time is off by one beat in the view and input layer (WR-02).

**Determinism.** No global RNG is used. Every RNG is a private seeded `RandomNumberGenerator`, and `Time` appears only in the visual-only ink feather and press-fill code. MatchHarness is frame-rate independent. The live VersusController path is not, because tick misses are stamped with frame time and bots are stepped one after another (WR-01).

**State leaks.** `MatchSetup.pending` is one-shot: Gameplay always clears it, and every main-menu launch path clears it as well. `SongSelect.run_pick` is reset in `_exit_tree`, and `Gameplay.pending_*` is cleared in `_ready`. The one real leak is CR-02: a lambda reference cycle in `SubRig` keeps the whole match graph alive after every match, Solo Dive and rematch. A headless run reported "34 ObjectDB instances were leaked at exit", and the warning went away once the two lambda connections were removed.

**Performance (p95 5.22 ms against the 4.35 ms gate).** The roughly 1 ms of VersusHud cost comes from views that redraw everything every frame whether anything changed or not. The biggest is the three PeriscopePanels (WR-08). The other costs are a new StyleBox allocated on every draw (WR-09) and unconditional `queue_redraw` plus per-frame text measuring (WR-10). The "perf top list" at the end ranks the fixes.

**Visual follow-ups V-1..V-8:**

| Item | Verdict | Finding |
|---|---|---|
| V-1 | Code fix (copy constant) | WR-07 |
| V-2 | Code fix (width budget ignores +2 px glyph spacing) | WR-06 |
| V-3 | Code bug | WR-04 |
| V-4 | Code fix (one-line colour math) | WR-11 |
| V-5 | Code bug | WR-05 |
| V-6 | By design, not a bug | IN-07 |
| V-7 | Code fix (layout constant) | WR-12 |
| V-8 | Cosmetic, not a bug | IN-07 |

## Critical Issues

### CR-01: Bounty claim is silently lost when the first warhead is judged before the torpedo arrives

**File:** `src/versus/match_sim.gd:959-969` (with `1003-1017`, `1062-1065`)

**Issue:** `_on_landed_bounty` checks `rec["warheads"]` to decide whether there is still a reflect chance:

```gdscript
var heads: Array = rec.get("warheads", [])
if heads.is_empty():
    _claim_bounty(rec["id"], t)
```

`rec["warheads"]` is the immutable list copied from the flight. The live state is `_heads`.

Warhead notes start at `arrive_t`, so the first one is very often a note exactly on the arrival beat. When the target judges that note early and below Perfect (an early Good, or an early miss inside the 130 ms window), the following happens:
1. `_warhead_judged` runs before the arrival has been processed.
2. It calls `_kill_heads(id)`, which calls `_claim_bounty(id)`. No `_pending_bounty[id]` exists yet, so this does nothing, and `_heads[id]` is erased.
3. At arrival, `_on_landed_bounty` sees a non-empty `rec.warheads`, stores `_pending_bounty[id]` and waits for a `_kill_heads` call that can never come again.

The shooter never gets the 25% refund (spec req 10) and never gets credit toward the Bounty Hunter medal. The `_pending_bounty` entry also leaks.

The headless probe used two seats, seat 1 holding the bounty, and an Ink Cloud arriving at 11.0 s with its first warhead at 11.0 s:
- Good judged at 10.94 s: `claims=0 pending_bounty=1`
- Good judged at 11.06 s: `claims=1 pending_bounty=0`

**Fix:** Decide from the live warhead state, not the launch snapshot:

```gdscript
_pending_bounty[rec["id"]] = {"shooter": from, "holder": to}
if not _heads.has(rec["id"]):   # no open reflect chance (none picked, or already decided)
    _claim_bounty(rec["id"], t)
```

Add a regression test with a non-Perfect first warhead judged before `arrive_t`.

### CR-02: The SubRig lambda reference cycle leaks the whole match (sim, event log, rigs, judges, ChartData and its audio) on every match and rematch

**File:** `src/versus/sub_rig.gd:70-71`

**Issue:**

```gdscript
hull.hull_changed.connect(func(_v: float, _d: float) -> void: _report())
hull.score_changed.connect(func(_v: int) -> void: _report())
```

A GDScript lambda written inside a RefCounted script keeps a strong reference to `self`. The rig owns `hull`, the hull's signal stores the lambda, and the lambda references the rig. That is a reference cycle, so the rig is never freed. Everything it reaches stays alive with it:
- `sim` (with `event_log`, which grows to thousands of dictionaries per song)
- `players` and `channel`
- `judge` and `stack`
- `chart` (ChartData with `audio_stream`)

This happens for the human rig and every bot rig in every versus match, every Solo Dive (practice now always runs through VersusController) and every in-place Rematch. A new match from Match Setup builds a new ChartData and stream, so memory grows with each match.

I confirmed this headlessly. Building one `MatchSim` plus one `SubRig` and dropping them gives "WARNING: 34 ObjectDB instances were leaked at exit" and "15 resources still in use". After disconnecting only these two lambda connections, there is no leak.

**Fix:** Use method callables, which do not hold a reference:

```gdscript
hull.hull_changed.connect(_on_hull_changed)
hull.score_changed.connect(_on_score_changed)

func _on_hull_changed(_v: float, _d: float) -> void:
    _report()

func _on_score_changed(_v: int) -> void:
    _report()
```

Add a test that drops a rig and asserts that `weakref(rig).get_ref() == null` after the function returns. Use a helper function so the local stack slot is released.

## Warnings

### WR-01: Live versus is not frame-rate independent (misses use frame time; bots are stepped one after another)

**Files:** `src/versus/sub_rig.gd:106-131`, `src/ui/versus/versus_controller.gd:223-229`, `src/versus/match_sim.gd:425-429`

**Issue:** The live path breaks the determinism contract in three ways.

1. Expiry misses are stamped with frame time. `InputJudge._expire` resolves a late miss with `err = t_tick - note_time`, so `SubRig._on_judged` stamps `note_time + err`, which is the frame time. That frame time feeds:
   - the meter reset
   - the warhead kill and bounty claim time
   - debris
   - `on_failed`, and through it `eliminated_at`, `_elim_beat`, D-23 standings and LAST_STANDING

   MatchHarness hides this because it ticks on a fixed `TICK_S` grid. VersusController ticks at render frames.
2. `VersusController.update` runs `b.update(t)` for each bot in turn. Bot 1 advances the referee to `t`, which processes beats and expiries such as Overclock or Decoy end and duel resolution. Bot 2 then reports judgments at earlier times. `_begin` moves `_now` backwards, and the rules are evaluated against state that has already moved forward. For example, `t < p.overclock_until` fails after the expiry already ran, and a duel note can arrive after `_resolve_duel`. Event timestamps in `event_log` become non-monotonic.
3. For the human, `_on_extra_judged`, `_on_stray`, ghost hits and `_on_failed` use `rig.now`, which is the previous frame's `pre_tick(t)`, not the press time.

This contradicts the SubRig header ("never frame time") and the "seed shown in results for repro" claim (D-18). It also makes live matches drift from MatchHarness. During frame hitches it can reorder same-beat races, bounty claims and duel results.

**Fix:**
- Stamp late misses at the deterministic deadline: in `_on_judged`, `var e := minf(err, jcfg.good_window + InputJudge.EPS) if j == MISS and err > 0.0 else err`.
- In `VersusController.update`, step every actor in global time order as `MatchHarness.advance_to` already does: loop on `min(b.next_time())` across bots and the drone, then tick.
- Pass the press time to LaneInput's judge path so `rig.begin(t_press)` runs before `judge.press`. One way is to route human presses through `human_rig.press`.

### WR-02: A reflected payload's ease-out and Crossed Wires input remap end one beat late

**Files:** `src/versus/sub_rig.gd:163-167`, `src/versus/payload_stack.gd:64-72`

**Issue:** `PayloadStack.end_early(id, t)` starts the 1-beat ease-out "at the next whole beat after t". It is designed to be called with the reflection moment. SubRig calls it from `PAYLOAD_END`, whose `t` is already the next whole beat (MatchSim `_reflect` sets `end_t = te` on a beat). So `b_end = beat(te) + 1`: the effect stays at full strength for a whole beat after the referee ended it, and only then eases out.

For Crossed Wires, `input_map` stays swapped until `b_end + 1`, which is two beats after the reflect point instead of one. Bots also keep their payload penalty for an extra beat (`effective_profile`). `tests/test_sub_rig.gd:129` only checks state at 16.0 s, so the test passes.

**Fix:** End the stack on the referee's end time, either by setting it directly or by passing a time just before the beat:

```gdscript
GameEvent.PAYLOAD_END:
    if ... reason == "reflected":
        var t := float(e["t"])
        stack.end_early(int(e["id"]), t - 1e-4)   # ease-out starts at t (D-17)
        judge.clear_payload(int(e["id"]), t)
```

Alternatively, handle `REFLECTED` (stamped at the reflect moment) instead. Add an assertion such as `ink_amount(te + 0.75 beat) < 1`.

### WR-03: Crossed Wires remap can swallow a real press when another key still holds the same judged lane

**File:** `src/input/lane_input.gd:100-111`

**Issue:** Releases are handled correctly: each release ends the lane recorded at press (Pitfall 3). Presses are not. `_lane_holders[lane] > 1` returns early without calling `judge.press`.

Suppose key A was pressed before the swap. It is recorded as judged lane a, for example while holding a sustain through the slide end. After the swap, key B maps to lane a. If the player presses B for the next lane-a note while A is still down, the press is dropped and the note becomes a Miss, even though the player hit the correct screen position.

**Fix:** Always forward the press edge to the judge, and keep the holder count only to gate the release:

```gdscript
_lane_holders[lane] += 1
if conductor != null and judge != null:
    judge.press(lane, conductor.song_time_at(ticks))
lane_pressed.emit(lane, ticks)
```

If a second hold on one lane must be avoided, release the earlier action's lane first, then press.

### WR-04 (V-3): Hit bursts, sustain sparks and judgment popups use the unswapped lane x under Crossed Wires

**Files:** `src/ui/fx/fx_layer.gd:214, 324, 501, 552`, `src/ui/feedback.gd:129, 152`

**Issue:** FxLayer and Feedback position effects with `Trench.hit_point(lane)`, which is the static column of the judged lane. Under Crossed Wires the judged lane is drawn at the other column, as `Highway.receptor_center(lane)` already returns. The burst therefore lands on the wrong receptor, as the `versus_crossed_wires_x3_full` shot shows. This undermines the payload's counterplay rule, "follow colour and shape". It is a code bug, not a design choice.

**Fix:** Give FxLayer and Feedback a `highway` reference, or a `Callable lane_point(lane)`, and use `highway.receptor_center(lane)` (and its `.x` for popups) at emit time. For sustain emitters, update `position` each frame while the lane is held, because the slide moves the receptor.

### WR-05 (V-5): Ink Cloud lets judgment popups show past the band edge

**File:** `src/ui/versus/ink_cloud_layer.gd:94-104` (band polygon), `src/ui/feedback.gd:240-252` (popup draw)

**Issue:** The band is a trapezoid fitted to the highway edges. Feedback popups are centred on a lane at Heading size with a 3 px keyline, so for the outer lanes they are wider than the band, and the overhang ("T" from PERFECT) draws outside the ink. It is a code bug with a clear fix.

**Fix:** Pick one:
- Feedback skips or clips popups whose y is inside the inked depth range while `payloads.ink_amount(t) > 0`. Clip with `draw_set_transform`/`clip_children`, or fade them by `1 - ink_amount`.
- Widen the band polygon at `POP_Y` by half the widest popup width.

The first keeps the read-ahead challenge intact.

### WR-06 (V-2): The periscope callsign width budget ignores the +2 px glyph spacing, so 9-letter names truncate

**File:** `src/ui/versus/periscope_panel.gd:43-44, 463-464, 577-584`

**Issue:** `CALL_MAX = 112` comes from UI-SPEC 6.2's "fits 9 chars", but `spaced_font()` adds `spacing_glyph = 2`. With that spacing, "BARRACUDA" at Label 20 is wider than 112 px and `truncate_px` gives "BARRA…". The spec number is wrong for the font as configured, and the code inherits the error. It is a code-level fix.

`shown_callsign()` also re-runs `truncate_px` (one `get_string_size` per dropped character) on every `_draw`, every frame, for every panel (see WR-08).

**Fix:** Measure the available width instead of hard-coding it:

```gdscript
const PLACE_GAP := 8.0
var avail := PLACE_RIGHT - Palette.font().get_string_size(place_text(), ..., fs).x - PLACE_GAP - callsign_x()
```

With no bounty marker (x 96) that leaves about 128 px, which fits "BARRACUDA". Compute and cache the truncated string in `setup()` and when the bounty or place changes. Alternatively, drop `CALL_SPACING` to 1.

### WR-07 (V-1): The collision headline is longer than the alert's headline box

**File:** `src/ui/versus/incoming_alert.gd:32, 295, 546`

**Issue:** "BOTH TORPEDOES DESTROYED" at Heading 40 is wider than `HEADLINE_MAX = 528`, so it shows as "BOTH TORPEDOES DESTR…". The copy is too long for the box. `truncate_px` also runs on every frame the alert is drawn, which loops over glyph widths for this string.

**Fix:** Shorten the copy to `"BOTH DESTROYED"` or `"TORPEDOES DESTROYED"`, and update UI-SPEC row 340 to match. Cache the truncated headline when `_headline` changes instead of truncating in `_draw`.

### WR-08 (perf, top item): PeriscopePanel redraws all of its chrome every frame for every panel

**File:** `src/ui/versus/periscope_panel.gd:305-310` (`update` always calls `queue_redraw`), `314-328` (`step`), `530-660` (`_draw`)

**Issue:** `PeriscopeColumn.update` calls `p.update(t)` every frame, and that calls `queue_redraw()` unconditionally. With Full effects, `step()` queues another redraw for the sweep line. Each redraw re-records the whole panel:
- a StyleBoxFlat with a `PANEL_GLOW_SIZE` shadow
- the chamfer polyline (allocates a new `PackedVector2Array`) and 4 bracket polylines
- the disc and two 48-point antialiased arcs
- 16 separate antialiased `draw_arc` calls for the idle dashed threat ring (`DASHES`, line 71)
- 10-20 hull rects
- 3 `draw_string` calls through a FontVariation
- two `truncate_px` calls
- `live_pct()`, a Callable into `sim.duel_live`, during duels

`step()` also reads and writes 4 fields by name through `get(v)`/`set(v)` and allocates a filtered blip array every frame. That is about 45 canvas commands × 3 panels rebuilt in GDScript per frame. It fits the measured ~0.9-1.0 ms p95 drop when VersusHud is hidden, and the ~1.1 ms drop under Low effects (glow shadow and sweep off).

**Fix:**
1. Split each panel into a static child (box, brackets, callsign, place, hull, status) that redraws only from `on_event`/`_on_status`/`set_targeted`, and a small dynamic child (sweep, threat ring, blips, flashes).
2. In `update()`, call `queue_redraw()` on the dynamic child only when something on it moves: `_threat != "none"`, `sweep_on()`, blips present, or flashes running.
3. Cache `shown_callsign()` and the status text, and recompute them only when depth, duel or drone status changes. Limit `live_pct` to about 10 Hz.
4. Precompute the 16 dashes once and draw them with a single `draw_multiline`.
5. Replace `get(v)`/`set(v)` with direct field updates.

### WR-09 (perf): IncomingAlert and EventBanner allocate a new StyleBoxFlat in every draw and rebuild texts every frame

**Files:** `src/ui/versus/incoming_alert.gd:317-329, 463-475, 478-503`, `src/ui/versus/event_banner.gd:354-366, 576-584, 606-620`

**Issue:** `_panel_style()` is called from `_draw()` and creates a new `StyleBoxFlat` (`UiKit.chamfer_box` / `UiKit.style_panel`) with a glow shadow each time.

The alert is visible for the whole active payload, which was on screen in 47-73% of the captured frames. The duel banner is visible for the whole solo. During those times the views allocate a resource every frame. `observe()` also calls `_refresh_texts()` every frame in the ACTIVE and duel states, which formats strings and calls `duel_live` for each seat, then calls `queue_redraw()` twice (`incoming_alert.gd:328-329`).

**Fix:** Build the style boxes once per state (cache them per `_state`/kind and per Low-effects value). Rebuild only when the state or effect settings change. In `observe`, refresh texts only when the bar count or the integer percentage changes, and call `queue_redraw` only then (or while the ring is draining).

### WR-10 (perf): Idle views still call queue_redraw every frame, and Killfeed re-measures text every frame

**Files:**
- `src/ui/versus/killfeed.gd:291` (`step` always redraws, even with 0 lines), `348-382` (`_seg_width`/`_gap` call `get_string_size` for every segment, every frame; `chamfer_points` allocates per line)
- `src/ui/versus/reward_socket.gd:228` (always redraws, even with nothing held or animating)
- `src/ui/versus/edge_flash.gd:145-149` (redraws when alpha is 0)
- `src/ui/versus/ink_cloud_layer.gd:89-91` and `ink_top_layer.gd:46-48` (redraw when ink is 0; `ink_top_layer` also allocates a `_dbg` Dictionary in every draw)
- `src/ui/versus/status_chips.gd:111-131` (every frame while Decoy or Overclock is active: formats a string and calls `_hud.chip_rects()`, which measures every chip's text)

**Issue:** Each one costs a canvas re-record, a GDScript `_draw` call or text shaping lookups every frame, with nothing changing on screen.

**Fix:** Redraw only while something animates or changes:
- Killfeed: `if not _lines.is_empty(): queue_redraw()`. Store each segment's x offset when the line is pushed (`push_line`) and draw from those cached values.
- RewardSocket: redraw only while `_held != -1` (breathing), `_anim != NONE` or `_arc_t < 1`.
- EdgeFlash and the ink layers: redraw only while alpha is above 0, plus one final redraw to clear.
- StatusChips: compare `bars_left` as an int with the last value before building the string.

### WR-11 (V-4): The Pressure Crack rail tint blends toward a desaturated pink-grey instead of red

**File:** `src/ui/highway.gd:638-642`

**Issue:** `Palette.SONAR.lerp(Palette.WARNING_RED, 0.6 * _rail_k)` is a 60% RGB mix of cyan and red. The result is a pale pink-grey, so the "danger" cue reads as white in `versus_pressure_crack_*`. UI-SPEC 7.5 gave the 0.6 factor, but the colour math is the defect.

**Fix:** Tint fully at peak: `Palette.SONAR.lerp(Palette.WARNING_RED, _rail_k)`. Or draw a WARNING_RED rail overlay with alpha `_rail_k` over the SONAR rail. Update UI-SPEC 7.5 and the colour test.

### WR-12 (V-7): The Solo Dive training description sits 24 px above the stepper caption

**File:** `src/ui/song_select.gd:69` (`SECTION_NAMES_BASELINE := 736.0`), `92` (`TRAINING_CAPTION_POS := Vector2(1080, 760)`), `1790-1793`

**Issue:** The 3-second description replaces the section-names line at baseline 736. The "TRAINING TORPEDOES" caption is at baseline 760. Two Label 20 lines 24 px apart leave about 4 px between the descenders and the cap height, which is what `solo_training_stepper` shows. It is a layout constant.

**Fix:** Either move the caption and stepper down 8 px (`TRAINING_CAPTION_POS.y = 768`, `TRAINING_RECT.y = 776`, with keep-out and focus rects updated) or draw the description at baseline 728 when `training_description_active()` is true.

## Info

### IN-01: The `ghost_resets_meter` tunable does nothing

**File:** `src/versus/versus_config.gd:27`, `src/versus/match_sim.gd:236-239`

**Issue:** The flag (CONTEXT open question 4) is never read. `on_stray` is a no-op, and ghost hits never reach the referee. Flipping it in a playtest silently has no effect, which breaks the "all numbers are tunables" constraint.

**Fix:** Either implement it (`SubRig._on_ghost_hit` → `sim.on_ghost_hit(seat, t)` → `if cfg.ghost_resets_meter: p.meter.on_judgment(MISS)`) or remove the export.

### IN-02: A test seam lives in shipping code as process-wide static state

**File:** `src/ui/versus/versus_controller.gd:20, 114`

**Issue:** `static var test_autoplay_human` is reset only by tests and by the playtest driver. If a test aborts before `after_test`, every later versus match in the same process runs with the human on autoplay. This is harmless in the exported game but fragile in the test suite.

**Fix:** Pass it through `setup(..., autoplay)` from the test, or reset it in `Gameplay._ready` the way `pending_autoplay` is reset.

### IN-03: `approach_s` is captured once and goes stale if the scroll speed changes mid-match

**File:** `src/ui/versus/versus_controller.gd:102`

**Issue:** The pause-menu settings overlay can change `Settings.scroll_speed`. The Ghost Notes and Depth Charge window (`payload_span`, Pitfall 1) still uses the old approach time, so overlay notes can appear without a full approach.

**Fix:** Refresh `human_rig.approach_s = Trench.approach_for(Settings.scroll_speed)` on `settings_changed`.

### IN-04: Duel prize into an empty slot leaves meter progress partial while holding

**File:** `src/versus/reward_meter.gd:137-141`

**Issue:** `queue_prize` sets `held` but leaves `progress` where it was. `METER` events then report something like `progress 20/57, held X`. Spec req 2 says the meter "stops at full" while holding. The local views mask this (`meter_fraction` returns 1.0 when held), but a Phase 4 consumer would not.

**Fix:** Call `_set_progress(target)` in `queue_prize` when filling the slot.

### IN-05: Collision is stamped at the launch beat, not the halfway point

**File:** `src/versus/match_sim.gd:614`

**Issue:** Spec req 9 says both torpedoes "explode at the halfway point". The event `t` is `tb`, the launch beat. Views flash at launch time. This is minor, but it is the host-decided time Phase 4 will broadcast.

**Fix:** Stamp `tb + 0.5 × travel` beats, or add a `meet_t` field.

### IN-06: Smaller per-frame or per-note allocation costs outside VersusHud

**Files:** `src/ui/highway.gd:529` + `574-575` (`_rebuild_strips()` runs twice per frame, and `_columns_key()` allocates each time), `src/versus/payload_stack.gd:92-223` (each query re-runs `BeatClock.beat_at`; `lane_pos` calls `_beat` twice per lane, about 12-15 tempo walks per frame), `src/versus/bot_profile.gd:57-58` (`effective_for` duplicates a Resource for every sampled note)

**Fix:** Compute `bt` once per frame and pass it in (`*_at_beat` variants). Call `_rebuild_strips` once at the end of `_process`. Cache the four `effective_for` variants per bot.

### IN-07: V-6 and V-8 are not code bugs

**Issue:**
- V-6: Sonar Jam warheads judged during the 1-beat colour fade is the specified behaviour (D-15/D-16 plus the 1-beat ease). It is a UX decision.
- V-8: Killfeed lines still sliding in when 3-4 arrive in one beat is the specified DUR_FAST entrance. If you want to change it, you could shorten the stagger or skip the slide for lines pushed in the same frame.

## Perf top list (for the 5.22 ms → ≤ 4.35 ms p95 follow-up)

1. **PeriscopePanel** (WR-08). Split static from dynamic drawing, redraw the static part only on events, and drop per-frame `truncate_px`, `get`/`set` reflection and the 16 separate dash arcs. This is the largest single item, ×3 panels.
2. **Per-draw StyleBoxFlat and per-frame text rebuilds** in IncomingAlert and EventBanner (WR-09). This cost is paid on most frames of a match, because an active payload keeps the alert on screen.
3. **Unconditional `queue_redraw`** in Killfeed, RewardSocket, EdgeFlash, the ink layers and the EventBanner panel, plus Killfeed's per-frame text measuring and StatusChips' per-frame `chip_rects()` (WR-10).
4. Highway and PayloadStack repeated `beat_at` walks and the double `_rebuild_strips` (IN-06). These are small but run every frame.
5. Glow shadows (`PANEL_GLOW_SIZE`) on three panels plus the alert and banner. Low effects removes them, and they account for part of the 1.1 ms Low-effects gain. If items 1-3 are not enough, consider one shared glow texture instead of per-box shadows.

---

_Reviewed: 2026-10-15T21:12:41Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
