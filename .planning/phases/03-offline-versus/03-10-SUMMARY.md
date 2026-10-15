---
phase: 03-offline-versus
plan: 10
subsystem: versus-hud
tags: [periscope, killfeed, target-reticle, event-channel, ui]
requires: ["03-01", "03-02", "03-03"]
provides:
  - "PeriscopePanel: one rival readout (hull bar, tube arc + held reward, blips, threat block, bounty, duel status)"
  - "PeriscopeColumn: up to 3 panels at (24, 216|312|408, 352, 88), target reticle + caret, entrance, keepout_shapes"
  - "Killfeed: right-column event log at (1544, 216, 352, 184)"
affects: [03-14, 03-15]
tech-stack:
  added: []
  patterns: ["views fed only by EventChannel.received", "song-time update(t) for rings + wall-clock step(dt) for flashes"]
key-files:
  created:
    - src/ui/versus/periscope_panel.gd
    - src/ui/versus/periscope_column.gd
    - src/ui/versus/killfeed.gd
    - tests/test_periscope_panel.gd
    - tests/test_killfeed.gd
  modified: []
decisions:
  - "Rival held rewards are all visible in the scope disc (D-26). Only the active Decoy/Overclock state is hidden: BUFF_APPLIED is never rendered. A Decoy shows only when ABSORBED fires."
  - "Hull bar: 10 segments over the spec's 176 px (x0+96..x0+272) with 2 px gaps. The pitch is 17.6 px (segment 15.6 px) because 10x16 + 9x2 = 178 does not fit 176."
  - "Killfeed callsigns use +0 tracking (not +2), and text-to-text segment gaps are one space width (glyph gaps stay 4 px)."
  - "Killfeed overlong fallback past the spec's two steps: condense the content horizontally down to 0.85, then pixel-truncate the longest verb segment. The spec bounty line 'MAKO claimed the bounty on ORCA' is ~357 px in Share Tech Mono 20, over the 324 px budget even with 4-letter names."
  - "Killfeed victim/actor rule: the actor is from/by/to(absorbed)/winner. Victim lines are LANDED on you, IMPLODED you, and BOUNTY_CLAIMED on you. Collisions involving you are neutral (SONAR bar)."
  - "Threat block: COLLISION and ABSORBED clear an 'incoming' state, and REFLECTED clears incoming/active on the reflecting rival. Active and immune states also expire on song time (end_t / immune_until) in case the end event is late."
metrics:
  duration: "~35 min (across a usage-limit pause)"
  completed: 2026-10-15
---

# Phase 3 Plan 10: Periscope panels, target reticle and killfeed Summary

This plan adds the rival periscope column on the left (88 px panels ending at y 496 on 92% `HUD_GLASS_ALPHA` glass, with a SONAR_PALE target reticle and caret) and the killfeed on the right. Both are driven only by EventChannel events, plus a read-only live-percent callable for the Solo Duel, so Phase 4 can feed them from the network unchanged.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 | 1498174 | feat(03-10): PeriscopePanel and PeriscopeColumn with target reticle |
| 2 | dfc7e3a | feat(03-10): Killfeed event log in the right column |

## Tests

- test_periscope_panel 22/22, test_killfeed 16/16, test_color_literals 7/7
- `tools/check_timing_gate.ps1`: TIMING GATE OK
- No `PRESET_FULL_RECT` in my files. The column uses `UiLayout.fill_rect` and implements `keepout_shapes()`.
- Full suite not run (parallel-wave rule; 03-14/03-15 run it at wave end)

## Public API (for 03-14)

```
PeriscopeColumn (Control, full-screen canvas, MOUSE_FILTER_IGNORE)
  const PANEL_RECTS: Array[Rect2]   # (24,216,352,88), (24,312,352,88), (24,408,352,88)
  bind(channel, local_seat, rival_seats: Array[int], names: PackedStringArray, chart: ChartData,
       cfg: VersusConfig, live_pct: Callable, training: bool)   # live_pct(seat) -> int, -1 = no solo note yet
  update(song_time)          # call every frame: countdown rings + sweep line
  step(dt)                   # _process calls it: reticle glide, entrance, panel flashes/blips
  set_drone_status(text)     # training: "NEXT IN 3 BARS" / "NEXT IN 1 BAR" (caller formats)
  set_target(seat)           # also driven by TARGET events for local_seat
  panels(), panel_for(seat), reticle_rect(), caret_rect(), has_reticle(), keepout_shapes(), play_entrance()

PeriscopePanel (Control, 352x88)
  setup(seat, callsign, drone, chart, cfg, live_pct); on_event(e); update(t); step(dt)
  threat_state(), threat_fraction(), threat_glyph(), status_text(), place_text(), lit_segments(),
  held_glyph(), bounty(), blip_count(), effect_counts() {sweep, blips_max, glow, burst_radius, damage_flash}

Killfeed (Control at RECT)
  const RECT := Rect2(1544.0, 216.0, 352.0, 184.0)
  bind(channel, local_seat, names: PackedStringArray, cfg)   # names indexed by seat; local name should be "YOU"
  step(dt); lines() -> [{segments, own, victim, age, alpha, y, x_offset, squeeze, text}]
  static line_text(line); effect_counts() {slide}
```

## Notes for 03-14

- Add a `PeriscopeColumn` and a `Killfeed` under `VersusHud`, call `column.update(song_time)` each frame, and bind both to the same channel MatchSim sends on. Pass `names` indexed by seat with "YOU" for the human and "DRONE" for the training drone.
- Training: `rival_seats = [drone_seat]`, `training = true`. Drive `set_drone_status(...)` from the drone schedule. Training OFF means no column panel and no killfeed (UI-SPEC 8.3), so skip adding or binding them.
- `live_pct` must return the integer Perfect % of the current solo for a seat, or -1 before its first solo note.
- Both nodes register for effects. Add `PeriscopePanel`, `PeriscopeColumn` and `Killfeed` to the `test_effect_settings` "versus" context. Add the column's keepout shapes and the killfeed rect to `test_layout_keepout`. The panels are children of the column and sit inside its `keepout_shapes()`.
- Entrance plays on `bind()`. Call `play_entrance()` again at the count-in if bind happens earlier.
- Killfeed overlong-line fallback (condense to 0.85 / verb truncation) and +0 callsign tracking go beyond UI-SPEC 6.6. Flag them for UAT: every bounty line is condensed about 9% with the current font.

## Deviations from Plan

**1. [Rule 1 - Layout] Killfeed lines that still overflow after the spec's two steps.** The spec format for bounty claims measures ~357 px with 4-letter names, and 6-char truncation cannot shorten 9-char names (they come out as 6 chars + "..." = 9). Without a fallback, text ran past the 352 px glass. Added a horizontal condense down to 0.85, then pixel truncation of the longest verb segment. Names and the payload glyph are always kept. Commit dfc7e3a.

**2. [Rule 1 - Layout] Hull segment pitch.** The spec's 10x16 px + 2 px gaps is 178 px and does not fit its own 176 px span. The pitch is 17.6 px instead. Commit 1498174.

**3. TDD ordering.** Tests and implementation were written and committed together per task, not as separate RED/GREEN commits. All behaviours in the plan are covered by the suites.

## Known Stubs

None. Both views are complete and fed by events. Gameplay wiring is plan 03-14 by design.

## Self-Check: PASSED
