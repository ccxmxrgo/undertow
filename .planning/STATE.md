---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Completed 02.2-30-PLAN.md (gap round close, v0.5.1); awaiting 02.2-25 re-test
last_updated: "2026-10-13T20:32:00.577Z"
last_activity: 2026-10-13 -- Phase 02.2.1 planning complete
progress:
  total_phases: 10
  completed_phases: 6
  total_plans: 74
  completed_plans: 70
  percent: 60
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-07)

**Core value:** Hitting notes must feel tight and fair on each player's own machine, while torpedoes reach rivals over the network fast enough that a friend's perfect streak is felt inside the same song.
**Current focus:** Phase 02.2 — Visual Design Overhaul

## Current Position

Phase: 02.2 (Visual Design Overhaul) — EXECUTING
Plan: 30 of 30 (gap closure)
Status: Ready to execute
Last activity: 2026-10-13 -- Phase 02.2.1 planning complete

Progress: [██████████] 100%

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
| Phase 02.2 P10 | 75 min | 2 tasks | 10 files |
| Phase 02.2 P11 | 125min | 2 tasks | 9 files |
| Phase 02.2 P12 | 17 min | 2 tasks | 10 files |
| Phase 02.2 P13 | 35 min | 2 tasks | 6 files |
| Phase 02.2 P14 | 35 min | 2 tasks | 14 files |
| Phase 02.2 P15 | 60min | 2 tasks | 8 files |
| Phase 02.2 P16 | 50 min | 2 tasks | 6 files |
| Phase 02.2 P17 | 75 min | 2 tasks | 9 files |
| Phase 02.2 P18 | 6 min | 2 tasks | 3 files |
| Phase 02.2 P19 | 16 min | 2 tasks | 4 files |
| Phase 02.2 P20 | 27 min | 2 tasks | 10 files |
| Phase 02.2 P21 | ~35min | 2 tasks | 8 files |
| Phase 02.2 P22 | ~32min | 2 tasks | 10 files |
| Phase 02.2 P23 | 25 min | 2 tasks | 9 files |
| Phase 02.2 P24 | 38min | 2 tasks | 19 files |
| Phase 02.2 P25 | 40 min | 1 tasks | 9 files |
| Phase 02.2 P26 | 40 min | 3 tasks | 13 files |
| Phase 02.2 P27 | 25min | 2 tasks | 12 files |
| Phase 02.2 P28 | 20min | 2 tasks | 8 files |
| Phase 02.2 P29 | ~25 min | 2 tasks | 9 files |
| Phase 02.2 P30 | 90min | 2 tasks | 5 files |

## Accumulated Context

### Roadmap Evolution

- Phase 02.2.1 inserted after Phase 02.2: MIDI chart import (CONT-01 pulled forward; friend's GH3 pack uses notes.mid) (URGENT)

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
- 02.2-26 (G1, user-approved): JudgeConfig defaults Perfect 50 / Good 100 / early-miss 130 ms; the timing gate pins judge_config.gd to fbcf994 and the other four core files to 72e21ce
- 02.2-26: gem/receptor/hit-line sync is proven by tests/test_visual_sync.gd (60 cases); the triangle gem was 2.05 px above the line and is recentred in NotePainter.unit_shape
- 02.2-26: the results histogram range follows the Good window (-100..+100 ms, 40 x 5 ms bins)
- 02.2-27 (G2): Calm still-trench gameplay background next to Living, Settings > Display > Background ([display] background), default Calm; tests/harness pin Living where they assert Living; the user picks one after the re-test and the other is removed later
- 02.2-28 (G3 part 1): root cause was the input map: built-in ui_accept/ui_cancel had no joypad events; project.godot overrides add pad A/B and keep Enter/KP Enter/Space/Escape; no ui_* action reuses a lane pad binding (tested). Pad stick tests go through Input.parse_input_event (GUI focus needs Input just-pressed state); helpers in tests/helpers/pad.gd
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
- [Phase 02.2]: 02.2-10: the Miss shake has one path, FxLayer.request_shake moving board_root only (Feedback nudge removed); bursts clipped by Control.clip_contents (works in Compatibility)
- [Phase 02.2]: 02.2-10: burst sprites drawn at 4x dot size and spawned on the receptor rim for readability (motion values per spec); a new popup within 150 px fades the older one
- [Phase 02.2]: 02.2-11: Arena colonies live on side-wall/ceiling vertices only, culled 18 px outside the expanded note path (analytic half-plane test), 64 px from screen edges and out of the console corners; creature seeded by chart id, first crossing at 15..45 s then every 45..75 s
- [Phase 02.2]: 02.2-11: visual review raised band fills to a gradient lip 0.06+0.16n (spec 0.03+0.05n was invisible), doubled colony halos with a 0.5 floor, lantern fish cyan/pink school that swims; board-slice perf Full p95 2.53 ms, no cut step
- [Phase 02.2]: 02.2-12: Console bracket at SONAR 40% (keeps x<32 dark); perfect value right-aligned in 264..356 drawn by Hud; StreakCounter.right_x() is the constant 368; gauges are sized Controls drawing in screen coords
- [Phase 02.2]: 02.2-13: Mode chips use fixed slots (NO-FAIL y 824, AUTOPLAY y 864); depth right-aligned in a fixed '99,999' box with the M unit at the box edge
- [Phase 02.2]: 02.2-13: Hull damage is sequential (200 ms red flash holds, then ~150 ms shrink); Bathymeter.estimate_max_depth replays HullScore rules and matches an Autoplay run within 1 m
- [Phase 02.2]: 02.2-14: Section banner cross-fades on a new section during the hold and restarts the 1.6 s hold; names cut at 28 chars then by pixel width
- [Phase 02.2]: 02.2-14: Progress track polish (fill stroke glow, playhead diamond, lit reached ticks) identical in all effect modes
- [Phase 02.2]: 02.2-14: Windowed test launches open on the secondary monitor (run_all --position, tools/test_screen.gd, UNDERTOW_TEST_SCREEN override)
- [Phase 02.2]: 02.2-15: Best grade/misses are stored only when the grade rank improves; results opacity = calm AbyssBackdrop + ABYSS_900 55% (backdrop_opaque()); the three results buttons wrap focus and Esc = Back to Menu — D-16 keeps best-of semantics without changing record ids; the calm backdrop is the UI-SPEC 8 opaque look; the closed loop keeps focus inside the results
- [Phase 02.2]: 02.2-16: The results entrance is one Tween (0.89 s) driving apply_entrance(t); any key/pad/mouse/action press during it jumps to the final state and is consumed, so it never activates a button; histogram EARLY/LATE at baseline 292 (spec 268 collided with the TIMING caption) and window guides symmetric about x 1552 — keeps the entrance testable at any instant and skip-safe (T-02.2-31); VIS-05 complete
- [Phase 02.2]: 02.2-17: album art is decoded from a buffer chosen by magic bytes, with PNG/JPEG header dimensions checked (<= 4096) before decoding and an 8 MB cap before reading; oversize zip images are skipped, not a zip failure; zip cache marker stores EXTRACT_VERSION 2 so old caches re-extract once; Song Select defers an uncached cover request while the library scans and caches 'no art' results — decompression-bomb guard and D-19 art for existing zips; VIS-06 art half only (tiles/visualizer in plan 18)
- [Phase 02.2]: 02.2-18: Song Select preview plays on the Preview bus; 30-bar visualizer reads its analyzer (linear attack 30 ms / release 180 ms, magnitude_source seam); tile intensity = notes per second over entry.length_sec (1..5)
- [Phase 02.2]: 02.2-19: Song Select sections parsed lazily on a worker (ChartParser + ChartImporter, no audio), selected song only, cached per song id, stale results dropped by request id
- [Phase 02.2]: 02.2-19: Song Select SOURCE line dropped (not in the UI-SPEC 6 layout); skipped-lines warning moved to the SECTIONS caption line
- [Phase 02.2]: 02.2-19: songs harness outer-32-px check replaced by list-text contrast (row title vs row background >= 4.5:1)
- [Phase 02.2]: 02.2-20: Gameplay calls pause_menu.set_run_info before open; the run line drops an empty difficulty and truncates only the title
- [Phase 02.2]: 02.2-20: danger panels (IMPLOSION, dialogs) override the panel glow to WARNING_RED locally; the dialog panel has an opaque ABYSS_900 backing so the pause panel never shows through
- [Phase 02.2]: 02.2-20: intro rig-boot readout drawn above the lens mask, faint static scope rings added so the goggles cue reads; room_glow_texture kept as the rig backlight (VP_GLOW)
- [Phase 02.2]: 02.2-21: Calibration hides the decorative backdrop while the audio test stamps taps (set_quiet) — Taps are stamped once per frame, so frame cost biases the measured offset (T-02.2-41); xvfb showed +21 ms from the table backdrop
- [Phase 02.2]: 02.2-21: Settings toggles are PillToggle buttons whose text stays ON/OFF; Reduce screen shake renamed Reduce motion — UI-SPEC 9.3/14; tests and harness keep using .text and pressed
- [Phase 02.2]: 02.2-22: ScreenTransition autoload is the single scene-change choke point (sonar wipe 150+150 ms, 400 ms failsafe); only the cover consumes input and a press there jumps to the end; the reveal passes input; scene load time comes out of the reveal (floor half)
- [Phase 02.2]: 02.2-23: UiSounds plays move only after a navigation press (programmatic focus silent); blips suppressed while a Gameplay is RUNNING and muted for the whole calibration AUDIO/VISUAL steps; drawn HUD chips (MAX, NO-FAIL, AUTOPLAY) became child Controls so UiKit.pop_in animates them
- [Phase 02.2]: 02.2-24: Song Select's focus-marker owner is SongSelect (it draws its own list bar/caret); results gained a FocusMarker (UI-SPEC 4.3)
- [Phase 02.2]: 02.2-24: HighwayNotes is a registered effect node (Low hides the additive halo layer); effect counts expose capability flags (glint_enabled, frozen)
- [Phase 02.2]: 02.2-24: cloud perf capture (xvfb llvmpipe) logged as NOT representative; no cut steps; plan 24 (final) perf row pending the user's PC
- [Phase 02.2]: 02.2-25: perf gate unmeasured (not failed) in the cloud, so the UAT has no perf decision row; the PENDING PERF.md row stays for the Windows PC
- [Phase 02.2]: 02.2-25: the v0.5 zip ships TESTER-CHECKLIST.txt (user request); dist.ps1 runs under Windows PowerShell and pwsh
- [Phase 02.2]: 02.2-29: Settings rows use explicit row-by-row focus neighbours; a listening keyboard rebind cell swallows pad input except B (cancel)
- [Phase 02.2]: 02.2-29: Stick pushes are latched (one step / flip per push) on StepSlider and the Background row; fail screen B/Esc = Back to Menu
- [Phase 02.2]: 02.2-30: v0.5.1 friend zip built and self-tested (BUNDLED_OK 20); UAT sheet back to pending with G1-G3 fixed-pending-retest; 02.2-25 and the phase stay open until the user re-tests

### Pending Todos

- 02.2-26 on the PC: confirm notes that look on the receptor now score Perfect (1x and the usual speed); check Sea Shanty 2 Expert/Hard 92 ms same-lane repeats
- 02.2-27 on the PC: compare Living vs Calm in a dive (Settings > Display > Background, also from pause) on a real GPU and pick one
- 02.2-28 on the PC: walk menu -> song select -> dive -> pause dialogs -> results / fail with a real controller; check Xbox vs PlayStation layouts (Cross = confirm, Circle = back) and Steam Input remapping
- 02.2-25 Task 2: user plays v0.5 (one Expert, one Easy song), walks every screen and answers 02.2-HUMAN-UAT.md
- Windows PC: perf capture (fill the PENDING 02.2-PERF.md row), run_all.ps1 -SkipDrift, exe launch, listen to menu music / blips (02.2-HUMAN-UAT.md "Remaining for the Windows PC")

### Blockers/Concerns

- Godot is not installed on the dev PATH; Phase 1 setup must install it
- Windows audio output latency and Bluetooth devices (Phase 1 spike)
- Timing window values are tunable in JudgeConfig (about 50 ms constraint)
- 5-to-4 lane mapping rule must be fixed in Phase 2, before payload generation
- Steam peer support on Godot 4.7 is unverified (not blocking)

## Session Continuity

Last session: 2026-10-11T03:22:38.196Z
Stopped at: Completed 02.2-30-PLAN.md (gap round close, v0.5.1); awaiting 02.2-25 re-test
Resume file: .planning/phases/02.2-visual-design-overhaul/02.2-HUMAN-UAT.md
