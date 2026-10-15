---
phase: 03-offline-versus
plan: 02
subsystem: ui-primitives
tags: [palette, icons, note-painter, contrast, versus-visuals]
requires: []
provides:
  - "Palette.HUD_GLASS_ALPHA (0.92), Palette.JAM_GREY (alias of TEXT_MID)"
  - "UiIcons: 25 Phase 3 glyphs (rewards, killfeed, versus, medals)"
  - "NotePainter.NOTE_GHOST / NOTE_DISRUPTOR / NOTE_JAM, jam_mix, draw_jam_fade, ghost_dashes"
  - "NotePainter.draw_warhead_ring + WARHEAD_OPEN / CONFIRMED / DEAD"
affects: [03-highway-board, 03-hud, 03-killfeed, 03-results, 03-menus]
tech-stack:
  added: []
  patterns: ["match-arm per note type in NotePainter", "cached unit-space dash polylines per lane kind"]
key-files:
  created: []
  modified:
    - src/ui/palette.gd
    - src/ui/ui_icons.gd
    - src/ui/note_painter.gd
    - tests/test_contrast.gd
    - tests/test_ui_components.gd
    - tests/test_note_painter.gd
decisions:
  - "draw_warhead_ring takes an extra `grow` flag (default true): Reduce motion passes grow=false so the Perfect flash is alpha-only while flash_k still runs 0->1"
  - "draw_jam_fade(ci, lane, center, r, state, t, k, ...) added so Highway can draw the 1-beat lane->JAM_GREY cross-fade without duplicating gem code"
  - "Ghost rim outer edge sits at r (centre line r - 1.5), keyline at r + 2 outer edge, matching NOTE_NORMAL conventions"
metrics:
  duration: "~35 min"
  completed: "2026-10-15"
  tasks: 2
  files: 6
---

# Phase 3 Plan 02: Versus Visual Primitives Summary

This plan adds the visual building blocks that the wave-3 view plans draw with. Palette gets two new constants (`HUD_GLASS_ALPHA` 0.92 and `JAM_GREY`, which is an alias of TEXT_MID). UiIcons gets the 25 glyphs from 03-UI-SPEC section 4. NotePainter gets ghost, depth-charge and jam gems plus the warhead ring. Contrast rows C20-C25 are in place and all pass.

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Palette constants, 25 UiIcons glyphs, contrast C20-C25 | 6f3eb0d |
| 2 | NotePainter ghost / depth-charge / jam types and warhead ring | bf114a4 |

## What was built

- **palette.gd:** `HUD_GLASS_ALPHA := 0.92` and `JAM_GREY := TEXT_MID`. No new colour literal.
- **ui_icons.gd:** 25 new names, each drawn with its own match arm on the 24-unit grid. Shared private helpers are `_shield`, `_crosshair`, `_diamond`, `_arc_pts`, `_capsule` and `_arrow`, so the medal glyphs reuse the shield and bounty shapes without calling `draw()` recursively. `names()` now has 36 entries.
- **note_painter.gd:**
  - `resolve_type` returns 0-3 unchanged; any other value still falls back to NOTE_NORMAL.
  - `layers`:
    - ghost: `["keyline","rim_dashed"]` in every state and every mode.
    - disruptor: the normal layers plus `"charge_mark"`.
    - jam: `["keyline","core","rim"]`; a missed jam gem gives `["core","x"]`.
  - Ghost rim: 8 dashes per perimeter at 60% dash / 40% gap. The dashes are measured by arc length along `outline_ring(kind)` and cached per kind (`ghost_dashes`), with a fixed loop bound (T-03-05).
  - Depth-charge mark: a disc of 0.22 r in ABYSS_900 with a 1 px ring in `mix(lane, TEXT_HI, 0.55)`.
  - Jam gem: a plain circle with a JAM_GREY core and a TEXT_HI rim (ready) or TEXT_MID rim (far).
  - Warhead ring:
    - OPEN: a 3 px WARNING_RED ring at r+8, a 2 px KEYLINE just outside it, and a 10x6 chevron 6 px above the ring.
    - CONFIRMED: a SONAR_PALE flash that grows to r+20 while its alpha goes from 1 to 0.
    - DEAD: ring and chevron in TEXT_LO at 50%.
  - NOTE_NORMAL is drawn exactly as before. The only change to `_draw_normal` is an optional core-colour argument, defaulting to null, which `draw_jam_fade` uses.

## Tests

- test_ui_components: 37 passed. One new test draws every Phase 3 glyph at 16, 20, 24 and 32 px (100 draws).
- test_contrast: 25 passed (C20-C25 plus a check that JAM_GREY is the TEXT_MID alias).
- test_color_literals: 7 passed.
- test_note_painter: 23 passed (9 new).
- Full suite: 1260 tests, 2 assertion failures, both in `test_pack_installer.gd > test_update_app_only`. That test fails only in the full run and passes when the suite runs alone (29/29). It depends on test order, is unrelated to this plan, and is logged as deferred.
- `tools/check_timing_gate.ps1`: **TIMING GATE OK**.

## Deviations from Plan

1. **[Rule 2 - Missing functionality] `grow` parameter on draw_warhead_ring.** The plan said Highway should pass `flash_k = 0` under Reduce motion. With that value the flash would never fade, because `flash_k` drives both radius and alpha. I added `grow: bool = true` and `alpha: float = 1.0` after `flash_k`. Under Reduce motion, Highway should keep advancing `flash_k` and pass `grow = false`.
2. **[Rule 2] `draw_jam_fade` helper.** The plan has Highway draw the normal gem with a `jam_mix` core while 0 < k < 1. The painter had no way to override the core colour, so I added `draw_jam_fade` (with a `disruptor` flag that keeps the charge mark visible during the fade) and the optional core argument on `_draw_normal`.
3. The ghost-rim contrast row also checks the ready rim (UI-SPEC 7.2 lists it) as well as the far rim.

## Deferred Issues

- `tests/test_pack_installer.gd::test_update_app_only` fails only in the full-suite run (it expected 1 zip and got 3) and passes in isolation. It looks like state left behind by an earlier suite. It existed before this plan and is out of scope.

## Notes for later plans

- Highway should pass the note `type` to `NotePainter.draw_note` (the `n.get("type")` path already exists at highway.gd:1001).
- Draw `draw_warhead_ring` after the gem. It is not drawn on ghosts. Under Sonar Jam it is drawn unchanged.
- For a missed ghost, Highway owns the 150 ms fade below the line through `fade` / `alpha`. The painter never draws an X on a ghost.
- Glass panels in versus should use `Palette.alpha(Palette.ABYSS_700, Palette.HUD_GLASS_ALPHA)`.

## Known Stubs

None.

## Self-Check: PASSED

- src/ui/palette.gd, src/ui/ui_icons.gd, src/ui/note_painter.gd, tests/test_contrast.gd, tests/test_ui_components.gd, tests/test_note_painter.gd: FOUND
- Commits 6f3eb0d and bf114a4: FOUND on origin/main
