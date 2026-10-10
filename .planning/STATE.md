---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Completed 02.2-09-PLAN.md
last_updated: "2026-10-10T12:47:39.479Z"
last_activity: 2026-10-10
progress:
  total_phases: 9
  completed_phases: 5
  total_plans: 65
  completed_plans: 49
  percent: 56
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-07)

**Core value:** Hitting notes must feel tight and fair on each player's own machine, while torpedoes reach rivals over the network fast enough that a friend's perfect streak is felt inside the same song.
**Current focus:** Phase 02.2 — Visual Design Overhaul

## Current Position

Phase: 02.2 (Visual Design Overhaul) — EXECUTING
Plan: 10 of 25
Status: Ready to execute
Last activity: 2026-10-10

Progress: [#########.] 93%

## Performance Metrics

**Velocity:**

- Total plans completed: 15
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1.2 | 9 | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

| Phase 01 P01 | 15min | 2 tasks | 7 files |
| Phase 01 P02 | ~40min (tasks 1-4) | 4 tasks | 21 files |
| Phase 01 P03 | 45min | 3 tasks | 14 files |
| Phase 01 P04 | 35min | 2 tasks | 11 files |
| Phase 01 P05 | 45min | 1 tasks | 10 files |
| Phase 01 P06 | 50min | 3 tasks | 14 files |
| Phase 01 P07 | ~60min (tasks 1-2) | 2 of 3 tasks | 12 files |
| Phase 01 P08 | ~1h | 3 tasks | 14 files |
| Phase 01 P10 | ~35min | 2 of 3 tasks | 6 files |
| Phase 02.1 P01 | 12 min | 3 tasks | 13 files |
| Phase 02.1 P02 | 10min | 3 tasks | 7 files |
| Phase 02.1 P03 | 12 min | 3 tasks | 6 files |
| Phase 02.1 P04 | 15 min | 3 tasks | 17 files |
| Phase 02.1 P05 | 16 min | 3 tasks | 13 files |
| Phase 02.1 P06 | 35 min | 3 tasks | 17 files |
| Phase 02.1 P07 | 50 min | 2 tasks | 21 files |
| Phase 02.1 P08 | 75min | 3 tasks | 15 files |
| Phase 02.1 P09 | 20min (task 1; checkpoint pending) | 1 tasks | 6 files |
| Phase 02.2 P01 | 95min | 2 tasks | 8 files |
| Phase 02.2 P02 | 25 min | 2 tasks | 4 files |
| Phase 02.2 P03 | 35min | 2 tasks | 8 files |
| Phase 02.2 P04 | 12 min | 2 tasks | 13 files |
| Phase 02.2 P05 | 10min | 2 tasks | 4 files |
| Phase 02.2 P06 | 25 min | 3 tasks | 13 files |
| Phase 02.2 P07 | 25 min | 2 tasks | 13 files |
| Phase 02.2 P08 | 25 min | 2 tasks | 10 files |
| Phase 02.2 P09 | 20 min | 2 tasks | 7 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

- 02.1-02: per-beat B uses absolute-time error diffusion; per-beat error bound is half a milli-BPM step (~4 us at 86 BPM), so the plan's 2 us bound was replaced by that bound. Python tick_to_sec matches the Godot importer exactly.
- 02.1-02: a lead-in that is not whole bars becomes a pickup bar (TS r at tick 0, song TS at r*res); bar_ticks start at bar 1. quantize merges again after snapping; write_chart raises ValueError on lanes outside 0..3, duplicate notes, non-int fields.
- 01.1-05: window is created windowed (1600x900) and Settings.apply_window() goes fullscreen at boot; Godot 4.7.2 cannot leave a window created fullscreen. All harness scenarios use a temp ScoreStore path.
- 01-10: real-hardware re-run closes gaps 1-6 (Bug 2 with documented limitation); drift-run jitter p99 0.48 ms with tau 0.4 s, no retune; export excludes build/*
- 01-08: clock_slew_tau_s = 0.4 s (time-constant smoothing, p99 < 2 ms at 30-240 fps); overlays use UiLayout.fill_rect; DriftHarness.log_path injectable
- 01-06: per-run _run_root rebuilt on restart; autoplay disables LaneInput; pause menu emits restart/menu signals and Gameplay owns scene changes; Back to Menu falls back to skeleton until plan 07 menu exists.

Recent decisions affecting current work:

- Local hit judgment, networked events only (ping never affects timing)
- Gameplay goes through an EventChannel seam (Loopback, Bot, Net) so versus is built offline first
- Transport for v1: ENet over Tailscale/ZeroTier; GodotSteam is an optional later swap
- Godot 4.7.2 standard build, GDScript, version pinned for all friends
- [Phase 01]: [01-01] gdUnit4 6.2.1 runs headless on 4.7.2 only with --ignoreHeadlessMode (in tools/run_tests.ps1)
- [Phase 01-02]: Conductor schedules play() at song_time -(next_mix+latency)-audio_offset; Settings uses ConfigFile.parse on file text
- [Phase 01]: 01-03: sustain ticks frame-rate independent; hit score uses pre-hit multiplier; resume restarts audio via play(paused_position) launched early by output delay
- [Phase 01]: 01-04: Bindings serialize as <action>_key and <action>_pad; invalid or duplicate entries revert that action to default; trigger lanes press at 0.5, release at 0.4
- [Phase 01]: 01-05: Feedback owns lane flash/text/SFX/nudge; Hud owns hull damage flash; Highway.on_sustain_end must be wired to InputJudge.sustain_end
- [Phase 02.1]: 02.1-01: sync gate error sign is note - onset (negative = early); suggested_delay = delay - median; RESEARCH tables use the opposite sign
- [Phase 02.1]: 02.1-01: mix-only gate gives April's plan-authored chart PASS_BASELINE (78.5%, chance 9.9%); new charts are always gated with --stem and --beats
- [Phase 02.1]: 02.1-03: Octave compromise - fold exact octaves only when alternating, after another octave, or amp < 0.3; isolated octave = +-2 lanes; no pitch-class fold
- [Phase 02.1]: 02.1-03: VISIBLE SLIDE in contour_lanes (after 2 clamped same-direction steps re-centre to lane 1 rising / n_lanes-2 falling)
- [Phase 02.1]: 02.1-03: Hard halves Expert chords by strength before density cap; Medium chords only on kept downbeats that were Expert chords (<= 3%)
- [Phase 02.1]: 02.1-04: phase correction uses 1/16-subgrid residuals (|r|<30 ms); constant songs = LSQ line + global shift, others = +-8 smoothing + local shift + re-smooth; refined beats moved before 0 s are dropped
- [Phase 02.1]: 02.1-04: decode.json length_s is soundfile's full decode (HRT 161.876 s vs Godot 161.866 s); song_length must use the harness decoded length
- [Phase 02.1]: autochart chart --delay-ms only changes the song.ini delay (ticks fixed); Sea Shanty 2 fitted delay 72 = analysis delay
- [Phase 02.1]: Section labels use fcluster maxclust round(n/2); fixed 0.35 cosine threshold gave one label for Sea Shanty 2
- [Phase 02.1]: INVISIBLE ships at target-nps 2.8 (other + bass sections fill): plan attempt (c) at 2.5 passed the gate but fell under the SPEC 2 n/s Expert floor
- [Phase 02.1]: HRT ships other + drums bars fill at target 3.0 (GATE PASS 91.9%); fill adds nothing since other has onsets in every bar
- [Phase 02.1]: 02.1-07: April and Space re-charted on stem 'other' chosen by stem_rank.py (GATE PASS 89.7% / 95.6%), delays 58 / 164; author_chart.gd retired to tools/charting/legacy/
- [Phase 02.1]: 02.1-08: STEM-02/04 ship as a dev-PC command (extract_song.ps1 -> autochart.py extract); in-game screen deferred
- [Phase 02.1]: 02.1-08: instrument lanes order bass, drums, other, vocals (left to right); same-tick stems -> 2-lane chord of the two strongest
- [Phase 02.1]: 02.1-08: pick_preview skips sections in the first 10 s and < 30 s before the end; previews hrt 22322, invisible 49867, space 80440; charts unchanged
- [Phase 02.1]: 02.1-09: v0.4 friend README credits all 5 bundled songs and asks friends not to share (D-13); old 'no copyrighted songs' line removed
- [Phase 02.2]: 02.2-01: perf capture uses the game's WINDOW_MODE_FULLSCREEN on 1920x1080 screens (borderless screen-sized window becomes exclusive fullscreen, vsync locked); baseline Full p95 1.030 ms, Low p95 0.828 ms uncapped
- [Phase 02.2]: PENDING_MIGRATION starts with 7 src/ui files; each migration plan removes its file, plan 24 empties it
- [Phase 02.2]: beats_between counts quarter beats from the first tempo segment; each TS anchors a new bar; off-beat bar starts (7/8) are own entries
- [Phase 02.2]: Chart time signatures are clamped (num 1..32, exp 0..5), default 4/4 at chart start; sections/time_sigs never enter the fingerprint
- [Phase 02.2]: 02.2-04: Theme is generated from Palette tokens by UiKit.build_theme() and saved by tools/make_theme.gd; a sync test fails if ui/undertow_theme.tres drifts. Low effects uses build_theme(true) (no glow shadows)
- [Phase 02.2]: 02.2-04: Oxanium[wght].ttf kept with brackets (imports fine); weight 700 via integer name_to_tag("wght"); legacy Palette aliases now point at abyss/sonar tokens until plan 24
- [Phase 02.2]: Effect nodes register via UiKit.register_fx (FX_GROUP, apply_effect_settings, effect_counts); FocusMarker is a top_level child of each screen root
- [Phase 02.2]: AbyssBackdrop splits layers: Gradient/Shafts children behind (show_behind_parent), scene on the node, additive Searchlight child on top; reuse variant table/calm on later screens
- [Phase 02.2]: Menu searchlight cone follows the mockup (57 deg below horizontal) instead of the literal 25 deg; Reduce motion keeps the static logo glow (UI-SPEC 11)
- [Phase 02.2]: MenuMusic autoload on a Preview bus (sends to Music, spectrum analyzer at effect 0); fades stepped in _process, two-player 400 ms loop cross-fade; waits for entries_added at boot; harness disables it in isolate_settings
- [Phase 02.2]: Song Select preview stays on the Music bus until plan 18 moves it to Preview with the visualizer
- [Phase 02.2]: 02.2-08: gems drawn by HighwayNotes (above Feedback) via NotePainter.draw_note keyed by type; Highway stays the state owner and draws strips/rails/hit line/sustains/chord bars/receptors; BoardRoot holds Arena, Highway, Feedback, HighwayNotes and is the Miss nudge target
- [Phase 02.2]: 02.2-08: halo size 2.6 r read as reach from centre (mockup proportions); cable_bright is an extra intro brightness over normal play (0 = normal)
- [Phase 02.2]: 02.2-09: strip tint rises toward the hit line (receptor light pool, peak 26% at x4) plus lane-coloured glass edges so lanes read as their hue; contrast pairs C1-C5/C8 proven by test
- [Phase 02.2]: 02.2-09: strip fill lives in Highway's child Polygon2D Surface (show_behind_parent) carrying sonar_surface.gdshader; Low = no material, Reduce motion = sweep off

### Pending Todos

None yet.

### Blockers/Concerns

- Godot is not installed on the dev PATH; Phase 1 setup must install it
- Windows audio output latency and Bluetooth devices (Phase 1 spike)
- Timing window values are tunable in JudgeConfig (about 50 ms constraint)
- 5-to-4 lane mapping rule must be fixed in Phase 2, before payload generation
- Steam peer support on Godot 4.7 is unverified (not blocking)

## Session Continuity

Last session: 2026-10-10T12:47:39.468Z
Stopped at: Completed 02.2-09-PLAN.md
Resume file: None
