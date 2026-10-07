# Walking Skeleton — UNDERTOW

**Phase:** 1
**Generated:** 2026-10-07
**Refreshed:** 2026-10-07 after plan 01-02 execution (tasks 1-4)

## Capability Proven End-to-End

A player launches the Godot project, hears a generated click track, watches notes scroll down a minimal 4-lane highway to the hull line, presses D/F/J/K, and sees each press judged Perfect / Good / Miss against the audio-derived song clock, with offsets persisted in `user://settings.cfg` and a Windows debug export that runs on a second PC.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Engine / language | Godot 4.7.2-stable standard, typed GDScript (D-01) | Locked; no .NET SDK needed on friends' PCs |
| Renderer | Compatibility (`gl_compatibility`, D-04) | Broadest GPU support; no shaders in this phase |
| Song clock | `Conductor` Node wrapping pure `ClockModel` RefCounted; `get_playback_position() + get_time_since_last_mix() - cached output latency - audio_offset`, slewed, monotonic (D-05) | Audio clock is truth; math is headless-testable with injected ticks |
| Input timing | Judge in `_input()`, stamp `Time.get_ticks_usec()` first, map via `song_time_at(ticks)` (D-06) | Removes frame quantization of per-frame song_time |
| Logic layer | `RefCounted` classes: ClockModel, InputJudge, HullScore, Autoplay, CalibrationMath, BindingStore, ChartData; `JudgeConfig` Resource holds all tunables (D-03, D-08) | Testable with gdUnit4 headless; Phase 2-4 reuse the same API |
| Data layer | `ConfigFile` at `user://settings.cfg` via `Settings` autoload (file text read then `ConfigFile.parse`), type-checked and clamped on load; unparsable file renamed to `.bak` and defaults restored | No code-exec risk of `.tres`; stands in for "database" |
| Test framework | gdUnit4 v6.2.1 vendored in `addons/`; works on 4.7.2 headless with `--ignoreHeadlessMode` (no GUT fallback needed) | D-03 |
| Content | Procedural `AudioStreamWAV` click track and synth song, hand-authored `ChartData` (D-27) | Sample-accurate, no licensing |
| Rendering | Single `_draw()` highway, pure function of song_time (D-25); lane shapes in `NoteShape`; 700 px/s at 1.0x scroll; moving index cull window | Simplest for ~30 visible notes |
| Autoloads | `Settings` only (calibration state lives inside it); everything else match-scoped nodes | Per CONTEXT established patterns |
| "Deployment" | Windows debug export `build/undertow-debug.exe` (separate .pck, `modify_resources=false`, addons/tests excluded) via `tools/export.ps1`, run on a second PC (D-31) | Early gate for latency and feel |
| Conductor ordering | `process_priority = -1000` so song_time is fresh before the root's `judge.tick` and the highway redraw | Avoids a one-frame-stale clock |
| Pre-roll handoff | Audio `play()` fires at song_time `-(time_to_next_mix + cached latency) - audio_offset` so the audible start lands at song_time 0 | Clock continuity at handoff (Pitfall 2) |
| Directory layout | `src/{core,input,audio,content,ui,autoload}`, `scenes/`, `tests/`, `tools/`, `addons/gdUnit4/` | Matches research recommended structure |

## Stack Touched in Phase 1

- [x] Project scaffold (Godot project, gdUnit4, `tools/run_tests.ps1`) — plan 01
- [x] Scene / routing — `scenes/skeleton.tscn` as main scene (menu replaces it in plan 07) — plan 02
- [x] Data persistence — `settings.cfg` read AND write of audio/visual offset and scroll speed — plan 02
- [x] UI: highway draw plus judgment text wired to D/F/J/K `_input` presses (audible/visual feel confirmed only at the human checkpoint) - plan 02
- [ ] Deployment: Windows debug export builds and launches on the dev PC (verified); running on a PC without Godot is PENDING the plan 02 task 5 human checkpoint

## Out of Scope (Deferred to Later Slices)

- Sustains, chords, hull, score, autoplay, pause (plans 03, 05 and 06)
- Rebinding, gamepad edge handling, volume buses UI, calibration wizard, menus (plans 04 and 07)
- CRT shader, bioluminescent background, underwater audio (Phase 5)
- Clone Hero import, song select (Phase 2); torpedoes, payloads, rivals (Phase 3); networking (Phase 4)

## Subsequent Slice Plan

- Plan 03: judged chords, sustains, hull and score, autoplay all-Perfect, drift simulation
- Plan 04: bindings, gamepad triggers, settings, calibration math
- Plan 05: palette, theme, shapes, highway, HUD, feedback, SFX components
- Plan 06: gameplay controller, pause/countdown, IMPLOSION, results, F3, F4 autoplay, drift harness
- Plan 07: calibration wizard, settings screen, main menu, human hardware gate
- Phase 2: import Clone Hero charts into `ChartData` and browse songs
- Phase 3: torpedoes and payloads against bots using `HullScore` and the press/release API
- Phase 4: online play over the event-channel seam
- Phase 5: sonar CRT look, audio polish, Windows release build
