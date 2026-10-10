---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Completed 02.1-05-PLAN.md
last_updated: "2026-10-10T01:16:34.186Z"
last_activity: 2026-10-10
progress:
  total_phases: 8
  completed_phases: 4
  total_plans: 40
  completed_plans: 36
  percent: 50
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-07)

**Core value:** Hitting notes must feel tight and fair on each player's own machine, while torpedoes reach rivals over the network fast enough that a friend's perfect streak is felt inside the same song.
**Current focus:** Phase 02.1 — Instrument Extraction Tool

## Current Position

Phase: 02.1 (Instrument Extraction Tool) — EXECUTING
Plan: 6 of 9
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

### Pending Todos

None yet.

### Blockers/Concerns

- Godot is not installed on the dev PATH; Phase 1 setup must install it
- Windows audio output latency and Bluetooth devices (Phase 1 spike)
- Timing window values are tunable in JudgeConfig (about 50 ms constraint)
- 5-to-4 lane mapping rule must be fixed in Phase 2, before payload generation
- Steam peer support on Godot 4.7 is unverified (not blocking)

## Session Continuity

Last session: 2026-10-10T01:16:34.180Z
Stopped at: Completed 02.1-05-PLAN.md
Resume file: None
