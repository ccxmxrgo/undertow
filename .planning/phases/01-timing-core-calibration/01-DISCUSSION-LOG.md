# Phase 1: Timing Core & Calibration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md. This log preserves the alternatives considered.

**Date:** 2026-10-07
**Phase:** 01-timing-core-calibration
**Areas discussed:** Timing judgment rules, Hull & scoring model, Calibration flow, Highway look, Default controls, Phase 1 test content, Pause/fail behavior, Dev tooling
**Mode:** `--auto`. Claude selected the recommended option for every question. No user prompts were shown.

---

## Timing judgment rules

| Option | Description | Selected |
|--------|-------------|----------|
| Perfect ±35 / Good ±70, data-driven | Tight Perfect, forgiving Good, tunable via JudgeConfig | ✓ |
| Perfect ±25 / Good ±50 / OK ±80 (4 tiers) | Closer to osu!mania; harder for casual friends | |
| Perfect ±50 / Good ±100 | Very forgiving; weak skill expression for torpedo charging | |

[auto] Chords: independent per-note judgment (selected) vs GH all-frets-together.
[auto] Stray presses: break streak/combo, no hull damage (selected) vs hull chip damage.
[auto] Sustains: forgiving release 100 ms before tail (selected) vs strict release.

## Hull & scoring model

| Option | Description | Selected |
|--------|-------------|----------|
| 100 hull, −8/miss, +1/perfect regen | Survivable, rewards accuracy, avoids death spiral | ✓ |
| No regen | Simpler but punishing | |
| Rock-meter style (GH) | Familiar but less fitting the "hull" fiction | |

[auto] Fail: IMPLOSION screen + No-Fail practice toggle (selected).

## Calibration flow

| Option | Description | Selected |
|--------|-------------|----------|
| Forced-on-first-launch wizard, tap median audio + slider visual | Ensures fairness across PCs | ✓ |
| Manual offsets in settings only | Easy to skip, leads to "feels off" complaints | |

## Default controls

| Option | Description | Selected |
|--------|-------------|----------|
| D F J K / Space / H / Esc; pad shoulders/A/Y/Start | Home-row lanes, avoids Tab conflict | ✓ |
| A S D F / Enter / Tab | Tab collides with ui_focus_next | |

## Highway look (Phase 1)

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal phosphor-green vertical lanes, shape-coded notes | Readable now, CRT shader in Phase 5 | ✓ |
| Full CRT shader now | Scope creep into Phase 5 | |

## Phase 1 test content

| Option | Description | Selected |
|--------|-------------|----------|
| Generated click track + one CC0 track with hand chart in internal ChartData | No dependency on Phase 2 importer | ✓ |
| Pull minimal .chart parsing into Phase 1 | Blurs phase boundary | |

## Pause behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Pause + 3-beat countdown resume, re-anchor clock | Standard, fair | ✓ |
| Instant resume | Unfair re-entry | |

## Dev tooling

| Option | Description | Selected |
|--------|-------------|----------|
| F3 overlay + 5-min drift test + early export smoke test | Retires timing risk per research | ✓ |

## Claude's Discretion

- Scene/folder layout, secondary class names, settings/calibration UI layout, SFX choice, note rendering technique, specific CC0 track.

## Deferred Ideas

- CRT shader/background/underwater audio → Phase 5
- .chart import/song select → Phase 2
- Fire/Target-cycle behavior → Phase 3
- Stray-press hull chip damage tuning → Phase 3 playtests
