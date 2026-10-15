---
phase: 03-offline-versus
plan: 08
subsystem: highway-board
tags: [highway, payloads, crossed-wires, sonar-jam, ink-cloud, warheads, overlay-notes, lane-input]
requires:
  - "03-02: NotePainter NOTE_GHOST/DISRUPTOR/JAM, draw_warhead_ring(grow, alpha), draw_jam_fade, Palette.JAM_GREY"
  - "03-04: PayloadStack modifier queries, VersusJudge.overlay_notes()"
provides:
  - "Highway.bind_versus(stack, judge, cfg) and payload-aware board drawing (PAY-01..06 visuals)"
  - "LaneInput.payloads: Crossed Wires physical->lane remap with release-at-press-lane"
  - "InkCloudLayer and InkTopLayer board layers (bind(highway) API)"
affects: [03-14, 03-15]
tech-stack:
  added: []
  patterns:
    - "lane columns: up to 2 drawn positions per lane (slide, or Reduce motion cross-fade)"
    - "null payloads = exact Phase 2 draw paths (solo unchanged)"
    - "debug_payload_state() test seam instead of pixel probes"
key-files:
  created:
    - src/ui/versus/ink_cloud_layer.gd
    - src/ui/versus/ink_top_layer.gd
    - tests/test_highway_payloads.gd
  modified:
    - src/ui/highway.gd
    - src/input/lane_input.gd
    - tests/test_visual_sync.gd
    - tests/test_lane_input.gd
decisions:
  - "LaneInput counts how many physical keys hold each judged lane: press fires on the lane's 0->1 edge and release on 1->0, so two keys mapped onto one lane across a remap never double-press or release each other"
  - "Reduce motion Crossed Wires: columns cross-fade with weight = the stack's cubic slide amount; the primary x (gem_center/receptor_center/chord bars) is whichever column has the larger weight"
  - "Lane key labels stay at Trench.hit_point(lane) in their own lane colour (labels unchanged, UI-SPEC 7.6/7.7)"
  - "first_depth_by_overlay records the depth when the board first SEES an overlay note (including up to 8 notes past the far end each frame), so the Pitfall 1 check does not depend on frame step"
  - "Ghosts stay NOTE_GHOST under Sonar Jam; depth charges jam like real notes"
  - "Warhead Perfect flash is drawn at the receptor (the hit note leaves _vis) from a ring buffer of max 8, timed in visual song time"
metrics:
  duration: "~70 min (including a usage-limit pause)"
  completed: 2026-10-15
  tasks: 2
  files: 7
---

# Phase 3 Plan 08: Highway Payload Visuals, LaneInput Crossed Wires Remap, Ink Cloud Layers Summary

The Highway now draws every disruptor on the player's own board. It reads a PayloadStack and a VersusJudge each frame for scroll speed, lane columns, rail tint, jam, overlay gems and warheads. LaneInput follows screen position under Crossed Wires and always releases the lane recorded at press. Two new board layers implement Ink Cloud. When `payloads` is null, every draw path runs exactly as in solo play.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 RED | 1225d7e | test(03-08): add failing tests for payload board modifiers and Crossed Wires remap |
| 1 GREEN | be8faff | feat(03-08): Highway payload modifiers and LaneInput Crossed Wires remap |
| 2 RED | c1c4daa | test(03-08): add failing tests for overlay gems, warhead rings and Ink Cloud layers |
| 2 GREEN | a191dac (content) + 894a625 (attribution) | see the deviation below |

## Public API (for 03-14)

### Highway (`src/ui/highway.gd`)
- `var payloads: PayloadStack`, `var overlay_judge: VersusJudge`, `var vcfg: VersusConfig` (all null in solo)
- `bind_versus(stack: PayloadStack, judge: VersusJudge, cfg: VersusConfig)`. Any argument may be null; a null cfg becomes `VersusConfig.new()`.
- `on_lane_released(lane, ticks)` (NEW). **03-14 must connect `LaneInput.lane_released` to it**, otherwise the InkTopLayer press fill only lasts for the 120 ms press pulse or a sustain hold.
- `lane_columns(lane) -> Array[Vector2]` (x = lane_f-space position, y = alpha), `lane_x_f(lane)`, `lane_lit(lane, now_usec := -1)`, `lane_label_center(lane)` (fixed), `gem_paint_type(type)`, `rail_color()`, `draw_lane_numbers_into(ci, alpha_mul := 1.0)`
- `receptor_center(lane)` and `gem_center(idx)` follow the lane's current column. They equal `Trench.hit_point(lane)` without Crossed Wires.
- `debug_payload_state()` keys: `approach`, `lane_x` (PackedFloat32Array), `rail_color`, `rail_k`, `jam_k`, `crossed` (Vector2i), `sliding`, `last_gem_type` (PackedInt32Array per lane), `warheads_drawn`, `swap_guides`, `overlay_visible`, `overlay_drawn`, `overlay_last` {type, kind, paint, alpha, center}, `overlay_types`, `first_depth_by_overlay` (uid -> depth), `fragments`, `fragments_drawn`, `fragment_drift`, `warhead_flashes`, `flashes_drawn`, `flash_k`, `flash_grow`.

### LaneInput (`src/input/lane_input.gd`)
- `var payloads: PayloadStack = null`. When set (and a conductor exists), the physical action index is mapped with `payloads.input_map(conductor.song_time_at(ticks))` at press time. `lane_pressed` and `lane_released` carry the judged lane. Without payloads the behaviour is identity, as before.

### InkCloudLayer (`src/ui/versus/ink_cloud_layer.gd`)
- `bind(highway)`, `band_polygon()`, `band_alpha()`, `feather_offset(t_sec, i)`, `debug_state()`
- Calls `UiKit.register_fx`. `effect_counts()` returns `{feather, edge_line, drift}`.

### InkTopLayer (`src/ui/versus/ink_top_layer.gd`)
- `bind(highway)`, `ink_alpha()`, `debug_state()` {drawn, ticks, outlines, fills}, `effect_counts()` {"ink_top": true}
- Not registered for effects, because it draws the same in every mode.

## Notes for 03-14 (wiring)

- Board order in `board_root`: `... HighwayNotes, (Feedback/FxLayer as now), InkCloudLayer, InkTopLayer`. The ink must sit above Feedback and HighwayNotes so that popups, bursts and gems inside the band are hidden.
- Call `highway.bind_versus(player.stack, player.judge, vcfg)` and set `lane_input.payloads = player.stack`. Connect `lane_input.lane_released -> highway.on_lane_released`.
- Add `InkCloudLayer` to the `"versus"` context in test_effect_settings EXPECTED/REDUCE (Reduce key: `drift` false). Do not add `InkTopLayer`.
- FxLayer bursts and Feedback popups still use `Trench.hit_point(lane)`. Under Crossed Wires, a burst for a crossed lane appears at that lane's original x. To fix this, those layers can use `highway.receptor_center(lane)`. Those files are outside this plan's scope.
- The `sonar_surface` shader's lane-edge glow is computed from screen position, so a crossed strip's edge glow keeps the colour of that screen column. This is cosmetic, and the shader was not in this plan's scope.

## Tests

- test_visual_sync 14/14 (7 new): solo approach unchanged; Pressure Crack approach = approach_for(1.5), cap 3.5 at base 3.0, gem on the hit line; rail colour = SONAR.lerp(WARNING_RED, 0.6); Crossed Wires gems and receptors at the swapped x, labels fixed; mid-slide x between the two positions; Reduce motion produces 2 columns whose alphas sum to 1; Sonar Jam type switch.
- test_lane_input 14/14 (5 new): remap after the slide end, identity before it and after the return; a held sustain across the switch releases lane 2 and completes with no stray; two keys on one judged lane give no double press; null payloads give identity.
- test_highway_payloads 13/13: ghost type and depth in Full, Low and Reduce; ghost stays a ghost under jam; shatter drift 6 px at 125 ms, gone at 250 ms, shatters once; Reduce means no drift; an ignored ghost fades below the line with no X; depth charge draws as NOTE_DISRUPTOR; Pitfall 1 first depth >= D_FAR (plus a negative control); a judged depth charge hides and a missed one pins; warhead OPEN and DEAD rings; Perfect flash fires once for 200 ms (no growth under Reduce); Ink band corners and fade; Ink effect modes (6 feathers, edge line, static); InkTopLayer draws only with ink, with 5 ticks, 4 outlines and the press fill.
- test_color_literals 7/7. Sanity (read-only): test_highway_ready 15/15, test_effect_settings 9/9, test_note_painter 23/23.
- `tools/check_timing_gate.ps1`: **TIMING GATE OK**.
- The pinned files (conductor, clock_model, input_judge, hull_score, judge_config) were untouched during this plan.
- Per the parallel-wave rule, the full suite was not run (03-14/03-15). During Task 2 RED, a parse error in another plan's in-progress file (`_draw_chip_node` / `CHIP_AUTOPLAY_Y`) was printed. It was not caused by this plan.

## Deviations from Plan

### Process

**1. Task 2 code landed in a parallel agent's commit.** I staged the Task 2 files by explicit path. Before my `git commit` ran, a parallel agent's `git commit` for `docs(03-09)` (a191dac) committed everything staged in the shared index, so it included my highway.gd, ink_cloud_layer.gd and ink_top_layer.gd changes and their .uid files. The committed content is identical to what I staged and it is pushed. I did not rewrite the shared history. Instead I added an empty attribution commit, 894a625. Orchestrator note: parallel agents should commit with `git commit <paths>` (pathspec), not plain `git commit`, so that one agent never sweeps up another agent's staged files.

### Auto-fixed / added (Rule 2)

- **LaneInput lane refcount.** Without it, one key held before the switch plus the other key pressed after the switch would map both to the same judged lane. That causes a double `judge.press`, and the first key-up would then release a lane that the other key still holds. This is tested.
- **`Highway.on_lane_released` and `lane_lit`.** The plan asks InkTopLayer to show the press fill "while the lane is held", but Highway had no record of which keys were down.
- **`draw_lane_numbers_into`**, a public wrapper so that InkTopLayer can reuse the label drawing.
- Strips are rebuilt during Crossed Wires because the strip cache key now includes the lane columns. In solo the key stays empty, so solo rebuilds behave as before.

## Known Stubs

None. The layers are complete. Adding them to Gameplay is planned in 03-14 (by design).

## Threat Flags

None. T-03-20: the release uses the lane recorded at press, tested with a held sustain. T-03-21: only the visible overlay window is scanned (binary search plus a far-end break), and the fragment and flash ring buffers are each limited to 8. T-03-22: all transitions are beat-locked 1-beat fades, and the flash is a single 200 ms event.

## Self-Check: PASSED

- src/ui/highway.gd, src/input/lane_input.gd, src/ui/versus/ink_cloud_layer.gd, src/ui/versus/ink_top_layer.gd, tests/test_highway_payloads.gd, tests/test_visual_sync.gd, tests/test_lane_input.gd: FOUND
- Commits 1225d7e, be8faff, c1c4daa, a191dac, 894a625: FOUND on origin/main
