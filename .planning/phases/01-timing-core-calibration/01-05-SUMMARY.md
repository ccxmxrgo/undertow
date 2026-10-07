---
phase: 01-timing-core-calibration
plan: 05
subsystem: ui-audio-components
tags: [godot, gdscript, ui, theme, highway, hud, feedback, sfx]
requires:
  - phase: 01-03
    provides: HullScore, InputJudge signals (judged, stray, sustain_end), hand chart
  - phase: 01-04
    provides: BindingStore.display_name, Settings toggles (early_late_indicator, reduce_motion, no_fail)
provides:
  - Palette (colors, spacing tokens, font/bold/theme loaders with fallbacks)
  - ui/undertow_theme.tres (StyleBoxFlat-only shared Theme, Share Tech Mono, 4px accent focus)
  - NoteShape.draw(canvas, kind, center, size, color) with extensible Kind enum
  - Highway: sustain tails, pre-roll pips, early/late indicator, bound key labels
  - Hud bound to HullScore (hull bar + 30% notch, depth, combo, multiplier, streak, NO-FAIL)
  - Feedback (lane flash, ring, X glyph, floating text pool max 6, Miss nudge, SFX)
  - SfxPool + AudioSynth.make_tick / make_clunk
affects: [01-06, 01-07]
tech-stack:
  added: []
  patterns: [all UI colors via Palette, single _draw() highway, signal-bound HUD, capped text pool]
key-files:
  created:
    - src/ui/palette.gd
    - ui/undertow_theme.tres
    - src/ui/hud.gd
    - src/ui/feedback.gd
    - src/audio/sfx_pool.gd
    - tests/test_ui_components.gd
  modified:
    - src/ui/note_shape.gd
    - src/ui/highway.gd
    - src/audio/audio_synth.gd
    - src/ui/skeleton_root.gd
key-decisions:
  - "Highway tracks per-note state (pending/hit/missed/holding/early-release); Highway.on_sustain_end(lane, completed) must be connected to InputJudge.sustain_end"
  - "Feedback owns lane flash, floating text, SFX and nudge; Hud owns the hull damage flash"
  - "Spike readout kept behind Highway.show_spike_readout (default false; skeleton sets true)"
requirements-completed: [TIME-04, HULL-02, HULL-03]
duration: ~45min
completed: 2026-10-07
---

# Phase 1 Plan 05: Themed Highway, HUD, Feedback and SFX Summary

Reusable UI/audio components for the solo screen: Palette-only highway with shaped notes, sustain tails, pre-roll pips and early/late indicator; HullScore-bound HUD; per-judgment feedback with a capped text pool, Miss nudge and procedural hit sounds. Plan 06 assembles them.

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Palette, Theme, NoteShape, Highway, HUD, Feedback, SfxPool | 4d48a05 |

## Verification

- `powershell -NoProfile -File tools/run_tests.ps1` exits 0: 113 test cases in 17 suites, 0 failures (11 new in tests/test_ui_components.gd).
- Palette has the 5 hex colors (plus black); no `Color(` outside Palette in highway/hud/feedback.
- Floating text pool asserted never above 6 across 20 judgments; Miss nudge moves 8px and restores, skipped under reduce_motion.

## Deviations from Plan

**1. [Rule 1 - Bug] Test timing:** `create_timer` fires early under gdUnit; the nudge test waits on real ticks across frames instead.

**2. HULL caption placed under the bar** (not above) so the bar stays at (32,32) inside the 32px safe margin.

**3. NoteShape.draw signature** changed to `(canvas, kind, center, size, color)` per the plan; the only caller (Highway) updated.

**4. Highway judgment word and lane flash removed** (moved to Feedback); the skeleton scene now shows only the lane/note/indicator display until plan 06 wires Feedback. Skeleton root now connects `sustain_end` and enables the spike readout.

**5. Theme extras:** HeadingLabel / DisplayLabel / CaptionLabel type variations added to the Theme for HUD and later screens.

## Known Stubs

None. Hud fire/target and gamepad key labels are out of scope (labels use the keyboard binding).

## Self-Check: PASSED
