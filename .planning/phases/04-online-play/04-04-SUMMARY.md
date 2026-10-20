---
phase: 04-online-play
plan: 04
subsystem: ui
tags: [ui, widget, text-field, icons, chips, contrast, effects]
requires: []
provides:
  - SonarTextField (src/ui/online/sonar_text_field.gd)
  - UiIcons online/host/signal/link_broken/copy/warning + draw_signal / signal_bar_colors
  - UiKit.chip_style("danger")
  - contrast checks C26-C30
affects: [04 online menu, lobby, settings ONLINE, in-match chips]
tech-stack:
  added: []
  patterns: [self-rendered focusable Control with UiKit effect contract]
key-files:
  created:
    - src/ui/online/sonar_text_field.gd
    - tests/test_sonar_text_field.gd
  modified:
    - src/ui/ui_icons.gd
    - src/ui/ui_kit.gd
    - tests/test_ui_components.gd
    - tests/test_contrast.gd
    - tests/test_effect_settings.gd
decisions:
  - "SonarTextField draws its own well, text, caret and counter instead of wrapping a LineEdit, so it fully owns Esc/Space/gamepad routing and the Reduce-motion caret"
  - "An empty name on commit reverts and emits invalid(\"empty\"); a bad port emits invalid(\"port_range\")"
  - "rejected_count counts reject events (one per rejected key, or one per paste that dropped characters); max-length overflow counts as a reject"
  - "C29/C30 row = ABYSS_600 at HUD_GLASS_ALPHA over the menu glass composite"
metrics:
  duration: ~45 min (split by a usage-limit pause)
  completed: 2026-10-20
requirements: [NET-01, NET-02]
---

# Phase 4 Plan 04: Online UI primitives Summary

This plan adds the SonarTextField widget for name, port and address entry with keyboard, mouse and gamepad. It also adds six online glyphs (one of them a signal glyph with a lit count), the `danger` chip variant and contrast pairs C26-C30. All of them are tested and follow the Low effects / Reduce motion rules.

## Tasks

| # | Task | Commit |
|---|------|--------|
| 1 | Six glyphs, danger chip, contrast C26-C30 | 1249096 |
| 2 | SonarTextField widget and effect-settings context | 8636643 |

## SonarTextField API

- `SonarTextField.new()`, then `setup(config: String, value: String = "")`. The config is `"name"`, `"port"` or `"address"`; anything else falls back to `"name"`. The initial value is cleaned (charset, case, max length) silently.
- Properties: `config`, `value` (this is the edit buffer while editing), `placeholder`, `caret`, `rejected_count`, `last_blip`, `clipboard_fn: Callable` (returns String; you can inject your own).
- Signals: `committed(value)`, `cancelled`, `invalid(code)` (code is `"port_range"` or `"empty"`), `editing_changed(on)`.
- Methods: `begin_editing()` (grabs focus; use it for the first-visit prompt), `commit()`, `cancel()`, `is_editing()`, `set_value(v)` (stops editing without signals), `max_length()`, `insert_text(s)`, `paste()`, `cycle(dir)`, `tick(delta)`, `caret_visible()`, `edge_role()` / `edge_color()` / `static role_color(role)`, `counter_text()`, `display_text()`, `static cycle_order(cfg)`.
- `debug_state()` returns `{config, value, editing, caret, rejected_count, edge_color_role}`. `edge_color_role` is one of `idle`, `focused`, `editing` or `rejected`.
- `effect_counts()` returns `{caret_blink, glow}`. Low effects sets glow to false. Reduce motion sets caret_blink to false and keeps the glow static.
- Screens: while a field is editing, it consumes Esc, Enter, B and A in `_gui_input`, so screens that use `_unhandled_input` for ui_cancel (for example Settings) never see them. A screen that reads ui_cancel in `_input` must check `field.is_editing()` itself.
- Blips: the UiSounds observer already plays confirm/back for real ui_accept/ui_cancel events. The field itself plays `error`, `move` (cycling) and `confirm` on a mouse click.

## UiIcons / UiKit

- `UiIcons.NAMES` grew from 36 to 42 names. `draw(ci, "signal", ...)` draws all four bars lit.
- `UiIcons.draw_signal(ci, rect, lit, color_lit) -> bool` clamps `lit` to 0..4. `UiIcons.signal_bar_colors(lit, color_lit) -> Array[Color]`. Unlit bars are ABYSS_500 at 70%.
- `UiKit.chip_style("danger")` = edge WARNING_RED, fill ABYSS_700 @0.8, text WARNING_RED.

## Tests

The following suites pass: test_ui_components (39), test_contrast (30), test_color_literals (7), test_sonar_text_field (20, new), test_effect_settings (13, new `sonar_text_field` context) and test_review_fixes (15). The timing gate prints TIMING GATE OK.

## Deviations from Plan

**1. [Design] No LineEdit child.** The plan said to wrap a LineEdit. The plan also allowed choosing whichever approach keeps the caret correct, so the field renders its text, caret, scroll window and counter itself instead. Reason: Space is bound to `ui_accept`, while the field also needs gamepad cycling, consumed Esc and a caret that follows Reduce motion. The visible behaviour matches UI-SPEC 4.1. The public API is unaffected; no downstream plan references a LineEdit.

**2. [Rule 1 - Test fix] The draw-state test now ticks past the 200 ms reject flash** before it asserts the `idle` edge.

**3. Source comment reworded** so that `grep -c PRESET_FULL_RECT` returns 0, as the done criterion requires.

**TDD note:** the tests were written before the implementation in both tasks. The RED state was not committed separately; the tests and the code landed in one feat commit per task.

## Known Stubs

None.

## Threat mitigations

- T-04-11: the charset filter applies to typing and pasting, so control characters are dropped. This is tested.
- T-04-12: the clipboard is cut to 4×max+16 characters before filtering, then to the remaining room. A test pastes 100 000 characters.

## Self-Check: PASSED

- src/ui/online/sonar_text_field.gd and tests/test_sonar_text_field.gd exist.
- Commits 1249096 and 8636643 are present on main.
