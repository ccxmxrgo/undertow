---
phase: 03-offline-versus
plan: 04
subsystem: versus-core
tags: [judge, hull, payloads, overlay-notes, autoplay, modifiers]
requires:
  - "03-01: VersusConfig, Reward, perfect_regen 0.25"
provides:
  - "VersusJudge extends InputJudge: ghost/depth-charge overlay notes"
  - "VersusHull extends HullScore: heal, Overclock score, capped ghost damage"
  - "VersusAutoplay: all-Perfect autoplay that presses depth charges and skips ghosts"
  - "PayloadNotes: seeded ghost/depth-charge generators with the Pitfall 2 spacing rule"
  - "PayloadStack: beat-locked per-highway modifier queries and warhead marks"
affects: [03-03, 03-06, 03-07, 03-08, 03-14]
tech-stack:
  added: []
  patterns:
    - "extend pinned timing classes, never edit them (Pattern 1)"
    - "payloads as data + modifier stack (Pattern 3)"
    - "beat-space easing via BeatClock.beat_at"
key-files:
  created:
    - src/core/versus_judge.gd
    - src/core/versus_hull.gd
    - src/core/versus_autoplay.gd
    - src/versus/payload_notes.gd
    - src/versus/payload_stack.gd
    - tests/test_versus_subclass.gd
    - tests/test_versus_hull.gd
    - tests/test_versus_judge.gd
    - tests/test_payload_notes.gd
    - tests/test_payload_stack.gd
  modified: []
decisions:
  - "Depth Charge note count is also capped at depth_cap(jcfg) = ceil(hull_start / miss_damage) - 1 (12 at defaults) so missing every overlay note can never take a full hull to 0 (D-08)"
  - "Ghost count has a hard limit of ceil(ghost_per_beat x beats in window); beat groups use integer 8th-grid indices (float noise produced a 17th group on some bundled charts)"
  - "Overlay-to-overlay spacing (0.25 s) applies across all lanes, not only the same lane"
  - "VersusHull.ghost_hit calls on_stray(-1), so a ghost hit also counts in stray_count (D-12: stray-like)"
  - "PayloadStack eases in beat space (beat_at), so 1-beat fades stay beat-locked across tempo changes"
metrics:
  duration: "~45 min"
  completed: 2026-10-15
  tasks: 3
  files: 10
---

# Phase 3 Plan 04: VersusJudge/VersusHull, PayloadNotes, VersusAutoplay and PayloadStack Summary

All six disruptors now run headlessly on the judge and hull side. The work is done by subclasses of the pinned InputJudge/HullScore, seeded overlay-note generators that keep the Pitfall 2 spacing on every bundled chart, and a beat-locked PayloadStack that answers the board's and LaneInput's modifier queries. None of the pinned files were edited.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 RED | 18fb796 | test(03-04): add failing tests for VersusJudge/VersusHull subclasses |
| 1 GREEN | 37cca73 | feat(03-04): VersusJudge and VersusHull extend the pinned judge and hull |
| 2 RED | 3142873 | test(03-04): add failing tests for PayloadNotes and VersusAutoplay |
| 2 GREEN | 7780fdb | feat(03-04): PayloadNotes generators and VersusAutoplay |
| 3 RED | e9a6b2f | test(03-04): add failing tests for PayloadStack modifier queries |
| 3 GREEN | 6683948 | feat(03-04): PayloadStack beat-locked modifier queries |

## Tests

- test_versus_subclass 5/5 (Pitfall 4 dispatch guard: a parent `judged.connect(on_judged)` reaches the subclass override; super and parent `_set_hull` work; Autoplay accepts a VersusJudge)
- test_versus_hull 10/10 (heal 90->100, 50->75, no revive; GOOD at x4 during Overclock = 400, after = 200; ghost cap 12 per payload; depth judgments score/regen/damage like base notes)
- test_versus_judge 11/11 (ghost hit/ignored/outside window, depth PERFECT/GOOD/early MISS/tick MISS, is_finished, sort/clear_payload, bad input; **event-list equivalence with InputJudge** on short_chart and hand_chart for Autoplay and a sloppy random presser, with and without frame jitter)
- test_payload_notes 10/10 (count rules, grid, determinism, hostile windows; **spacing invariant and D-08 worst case on all 5 songs x 4 difficulties x 10 windows**; VersusAutoplay all-Perfect with two depth-charge windows (one injected mid-run) plus ghosts at 30/60/144/1000 fps, no ghost_hit)
- test_payload_stack 11/11
- `git diff 72e21ce -- conductor.gd clock_model.gd input_judge.gd hull_score.gd` and `git diff 2c2e54c -- judge_config.gd` are empty
- `tools/check_timing_gate.ps1`: **TIMING GATE OK**
- Per the parallel-wave rule, the full suite was not run here. 03-14/03-15 run it at the end of the wave.

## Public API (for 03-06 / 03-07 / 03-08 / 03-14)

### VersusJudge (`src/core/versus_judge.gd`, extends InputJudge)
- `const GHOST := 1`, `const DEPTH := 2`, `const MAX_OVERLAY := 4096`
- `signal extra_judged(kind, lane, judgment, error_s)`: Depth Charge notes only
- `signal ghost_hit(lane, payload_id)`
- `add_overlay(notes: Array)` takes `{time, lane, kind, payload_id}` and skips invalid entries. Stored notes gain `state` ("open"|"hit"|"passed"|"missed"|"judged"), `judgment` (-1 until judged) and a unique `uid`.
- `clear_payload(payload_id, from_t)` removes that payload's open notes at or after from_t (use it on reflection).
- `overlay_notes() -> Array[Dictionary]` is the live, read-only view for Highway. It is sorted by time, then lane.
- `press/tick/is_finished` are overridden. Base notes go through `super.press`. An open ghost never blocks `is_finished`; an open depth note does.

### VersusHull (`src/core/versus_hull.gd`, extends HullScore)
- `var overclock_until := -INF`, `var now := 0.0`. **The owner must set `now` to the song time before each press/tick**, or Overclock never applies.
- `heal(amount)` is a no-op when is_failed, non-finite or <= 0.
- `ghost_hit(payload_id, damage, cap)`, `ghost_damage_spent(payload_id)`
- `on_extra_judged(kind, lane, judgment, err)` routes to `on_judged(lane, -1, ...)`.
- `connect_versus(judge: VersusJudge, cfg: VersusConfig)` = connect_judge + extra_judged + ghost_hit (using cfg.ghost_hull_damage / ghost_damage_cap).
- The reward meter is NOT wired here. MatchSim/PlayerState should feed base judgments to `meter.on_judgment` and send depth-charge Perfects (from `extra_judged`) through `meter.credit` (D-31). Ghost hits must not touch the meter (D-12).

### VersusAutoplay (`src/core/versus_autoplay.gd`)
- `_init(chart, judge: InputJudge)` queues open DEPTH notes automatically if the judge is a VersusJudge.
- `refresh(judge: VersusJudge)` queues newly added DEPTH notes. It only queues notes later than the last `update` time and is idempotent.
- `update(song_time)`, `is_done()`, `pending()`

### PayloadNotes (`src/versus/payload_notes.gd`, static)
- `MAX_NOTES := 256`
- `grid_points(chart, start, end) -> Array[float]` returns 8th-grid times in [start, end), at most BeatClock.MAX_BEATS.
- `is_free(chart, t, lane, taken, cfg, jcfg) -> bool`
- `ghosts(chart, start, end, cfg, jcfg, seed, payload_id := -1) -> Array[Dictionary]`
- `depth_charges(chart, start, end, cfg, jcfg, seed, payload_id := -1) -> Array[Dictionary]`. The **caller passes the overlay window** (`active_start .. end_t`, already shifted by approach time, Pitfall 1).
- `depth_cap(jcfg) -> int` (12 at defaults)
- Generators do not know about each other's notes. MatchSim's immunity (D-07) must keep two overlay payloads from overlapping on one sub.

### PayloadStack (`src/versus/payload_stack.gd`)
- `_init(chart, cfg)`, `install(record)` (replaces by id when id >= 0; ignores invalid records), `end_early(id, t)` (ease-out starts at the next whole beat; never extends), `clear()`, `prune(t)`, `payload_count()`
- `scroll_mult(t)`, `static effective_speed(base, mult, cap)`, `rail_tint(t)`
- `lane_pos(lane, t)` returns a Trench.lane_f-space x. Also `slide_k(t)`, `sliding(t)`, `crossed_pair(t := NAN) -> Vector2i` (no t: latest installed; with t: active only), and `input_map(t) -> PackedInt32Array` (physical lane action -> judged lane). LaneInput must remember the pressed lane per key (Pitfall 3).
- `jam_amount(t)`, `ink_amount(t)`, `ink_top_depth(t := NAN)`, `active_reward(t)`
- Warheads: `OPEN/CONFIRMED/DEAD` (= NotePainter.WARHEAD_*), `mark_warheads(torpedo_id, indices)`, `confirm(idx)`, `kill(torpedo_id)`, `clear_warheads(torpedo_id)`, `warhead_state(idx)` (-1 unknown), `warhead_progress(torpedo_id) -> Vector2i(k, n)`
- Easing: all effects use smoothstep (slides use cubic in-out) over exactly 1 beat in beat space, from arrive_t in and from end_t out.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Ghost count could exceed ceil(ghost_per_beat x beats)**
- **Found during:** Task 2 GREEN, in the bundled-chart sweep (17 ghosts in a 16-beat window).
- **Fix:** Beat groups now use the integer 8th-grid index instead of `floor(beat_at(t))`. A hard `limit = ceil(gpb x span)` was also added.
- **Commit:** 7780fdb

**2. [Rule 2 - D-08] Depth Charge safety cap**
- The plan anticipated this. `depth_cap(jcfg) = ceil(hull_start / miss_damage) - 1` (12) bounds the D-14 count, so an all-miss Depth Charge cannot empty a full hull. The test was not loosened.

**3. Test fixes during GREEN**
- test_versus_judge: two tests ticked past the unplayed base note at 1.0 and counted its MISS. They now play it first. The test_payload_notes base-count helper now uses the same 1e-6 window tolerance as the generator.

**4. Small API additions (Rule 2):** `payload_id` optional parameter on the generators, `VersusHull.ghost_damage_spent`, `VersusAutoplay.pending`, `VersusJudge.MAX_OVERLAY` trimming of closed notes, and on PayloadStack `sliding`, `prune`, `payload_count`, `clear_warheads`, plus optional `t` on `crossed_pair`/`ink_top_depth`.

## Notes for other plans

- New `class_name` files need `godot --headless --path . --import` before `tools/run_tests.ps1` sees them, because the runner only imports when `.godot` is missing.
- No MatchSim, GameEvent or PlayerState references were added (parallel-wave rule).

## Known Stubs

None.

## Threat Flags

None. T-03-10 (MAX_BEATS + 256 caps, empty or non-finite windows return []), T-03-11 (equivalence test + gate) and T-03-12 (ghost cap 12, depth_cap 12) are mitigated and tested.

## Self-Check: PASSED
