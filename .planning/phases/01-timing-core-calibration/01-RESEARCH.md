# Phase 1: Timing Core & Calibration - Research

**Researched:** 2026-10-07
**Domain:** Godot 4.7.2 audio-clock rhythm timing, input judgment, calibration, settings persistence, headless testing (gdUnit4), Windows export
**Confidence:** MEDIUM-HIGH (audio/input API facts verified against current docs; Windows driver latency behaviour and gdUnit4 CLI flags need confirmation on the real machine)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
(Summarized one-to-one from 01-CONTEXT.md; the planner MUST read 01-CONTEXT.md for the verbatim text. Decision IDs are preserved.)

- **D-01** Godot 4.7.2-stable, standard (non-.NET), typed GDScript. Pin in `project.godot` and README. Godot is NOT installed; installing is a user-approved/user-performed download. Plans list it as a human prerequisite and never silently download binaries.
- **D-02** Godot project at repo root `C:\Users\user\Documents\undertow`, next to `.planning/`.
- **D-03** gdUnit4 6.x vendored in `addons/`. Pure logic (clock math, judgment, hull, config) in `RefCounted` classes with an injectable time source so tests run headless.
- **D-04** Compatibility renderer.
- **D-05** `Conductor` is the single source of `song_time`: `get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() - audio_offset`; clamped monotonic, smoothed against stair-step; never accumulate `delta`.
- **D-06** Judge in `_input()`; timestamp each event with `Time.get_ticks_usec()` and convert to song time via the Conductor's ticks<->song-time mapping.
- **D-07** 2-beat pre-roll: song_time runs from the system clock while negative, hands off to the audio clock at 0.
- **D-08** One data-driven `JudgeConfig` resource. Perfect +-35 ms, Good +-70 ms, press up to 100 ms early with no better candidate = Miss on that note, note unhit past +70 ms = Miss.
- **D-09** Chords: each note judged independently.
- **D-10** Stray presses (no note within the 100 ms window in that lane) break Perfect streak + combo, NO hull damage (config value default 0).
- **D-11** Sustains: head judged as tap; holding earns ticks; early release ends sustain, no hull damage, remaining ticks lost; release within 100 ms before tail = full hold.
- **D-12** Two separate counters: Combo (any non-Miss) and Perfect streak (Perfect only).
- **D-13** Hull starts 100; Miss -8; Perfect +1 (capped at 100); Good 0. Values in `JudgeConfig`/`HullConfig`.
- **D-14** Perfect 100, Good 50, sustain tick 10; multiplier 1x-4x every 10 combo, resets on Miss; Depth (m) = score / 100.
- **D-15** Hull 0 -> "IMPLOSION" fail screen with Retry/Back; No-Fail toggle keeps playing and flags result.
- **D-16** First launch forces calibration wizard (skippable; re-runnable from Settings). Audio: 16 clicks at 100 BPM, discard first 4, median of rest. Visual: flash vs click, slider +-1/+-10 ms (or silent visual tap test). Saved per machine in `user://settings.cfg`.
- **D-17** Show detected output latency + buffer size in wizard; warn if device name suggests Bluetooth ("Bluetooth", "Headset", "AirPods", "Buds", ...).
- **D-18** Default keyboard: lanes D F J K, Fire Space, Target-cycle H, Pause Esc. Do NOT use Tab.
- **D-19** Default gamepad: lanes LB, LT, RT, RB; Fire A; Target-cycle Y; Pause Start; trigger digital threshold 0.5.
- **D-20** Rebind screen: every action rebindable; max 1 keyboard key + 1 gamepad button per action; duplicates within gameplay set rejected with message; Reset to defaults; persist in `user://settings.cfg`.
- **D-21** Scroll speed 0.5x-3.0x step 0.1 (default 1.0x). Master/Music/SFX buses with separate volume.
- **D-22** Lane flash + floating text (PERFECT/GOOD/MISS); hit tick on Perfect/Good (SFX bus, mutable); Miss clunk + small screen nudge; shape and text, not color alone.
- **D-23** Early/late indicator toggle in Settings; on by default during calibration/practice.
- **D-24** Minimal sonar look: black bg, 4 phosphor-green lanes, notes scroll top->bottom to a horizontal hull line, distinct shapes per lane, sustains as tails, HUD (hull bar, combo, multiplier, Perfect streak, depth).
- **D-25** Pooled nodes or `_draw()`; 60+ fps at ~20 notes/sec; no CRT shader.
- **D-26** Esc/Start pauses (solo only); audio stops, Conductor freezes; resume = 3-beat countdown, audio restarts from paused position, Conductor re-anchors; menu: Resume, Restart, Settings, Quit.
- **D-27** Phase 1 content is generated/bundled: (a) procedural metronome/click track at configurable BPM; (b) one short royalty-free/CC0 OGG loop or track with a hand-authored test chart (taps, chords, sustains, tempo change). `ChartData` = format-agnostic seconds-based note arrays (lane, time, duration).
- **D-28** Autoplay (TIME-05) feeds the same `press(lane, song_time)` / `release(lane, song_time)` API at exact note times; must score all-Perfect on every test chart; main automated correctness check.
- **D-29** F3 debug overlay (song_time, raw pos, time_since_last_mix, output latency, offsets, fps, song_time-per-frame graph, last 20 hit errors).
- **D-30** Drift test: 5-minute generated click track with autoplay, note times within +-2 ms of expected song_time throughout.
- **D-31** Export smoke test: early Windows debug build run on a second PC (human).

### Claude's Discretion
Scene/folder layout, class names beyond Conductor/InputJudge/HullScore/JudgeConfig/ChartData, settings/calibration UI layout, exact metronome and hit SFX (procedural or CC0), pooled nodes vs single `_draw()`, choice of the specific CC0 test track.

### Deferred Ideas (OUT OF SCOPE)
Full CRT/phosphor shader, bioluminescent background, underwater audio filter (Phase 5); Clone Hero `.chart` import, song library/select (Phase 2); Fire/Target-cycle doing anything (Phase 3); hull chip damage for stray presses (config exists, default 0; revisit Phase 3).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TIME-01 | Notes in sync with audio clock, no drift over 5 min | Conductor recipe (docs-verified), clamped/disciplined clock, caching `get_output_latency`, drift test design |
| TIME-02 | Presses judged against song time, frame-rate independent | `_input` + `Time.get_ticks_usec` anchor mapping; no hardware event timestamp exists (verified) |
| TIME-03 | Perfect/Good/Miss with tunable windows | `JudgeConfig` resource, per-lane queue judge algorithm, boundary tests |
| TIME-04 | Sustains and chords | Judge state machine for holds; independent chord notes; release forgiveness |
| TIME-05 | Autoplay all-Perfect | Same press/release API driven by fake clock; headless test |
| CAL-01 | Calibration wizard, separate audio + visual offsets, per machine | Median algorithm + sign convention, device/latency display, Bluetooth heuristic |
| CAL-02 | Rebind lane/Fire/Target-cycle on keyboard | `InputMap` runtime rebind, `physical_keycode`, ConfigFile persistence |
| CAL-03 | Gamepad play | Trigger axes as digital with own edge detection; LB/RB buttons |
| CAL-04 | Scroll speed + music/SFX volume | Audio buses + `linear_to_db`, clamped settings |
| HULL-01 | Misses damage hull, zero eliminates | `HullScore` RefCounted, `JudgeConfig` values |
| HULL-02 | Combo, score/depth, hull visible | HUD via `_draw`/Controls reading `HullScore` signals |
| HULL-03 | Visual + audio feedback per judgment | Feedback layer; shape+text; SFX pool |
| HULL-04 | Pause/resume | Conductor pause/resume re-anchor with countdown |
</phase_requirements>

## Summary

The Godot 4.7 docs (page "Sync the gameplay with audio and music", currently flagged "not yet updated for 4.7") still give the same recipe the project already chose: `get_playback_position() + AudioServer.get_time_since_last_mix()`, minus `AudioServer.get_output_latency()`, and "discard the value if less than the previous frame". [CITED: docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html] Two corrections to the CONTEXT/STACK assumptions matter for planning: (1) **`InputEvent` has no timestamp property at all** (its only documented property is `device`), so the "event timestamp" in D-06 must be `Time.get_ticks_usec()` captured at dispatch; hardware press time is unrecoverable and the residual error (up to one frame of OS-queue delay, jitter not bias) can only be absorbed by calibration. [CITED: docs.godotengine.org/en/stable/classes/class_inputevent.html] (2) **`get_output_latency()` "can be expensive; not recommended to call every frame"** [CITED: class_audioserver.html], so the Conductor must cache it (refresh about once per second and on device change), not call it per frame as D-05 literally reads.

The recommended Conductor is a *disciplined* clock: extrapolate between frames with `Time.get_ticks_usec()` and slew toward the audio-derived estimate each frame (snap only on large error). This satisfies D-05's "never backwards, smoothed" and also gives the ticks<->song-time mapping D-06 needs (`song_time_at(ticks_usec)`). The pre-roll/handoff (D-07), the pause resume (D-26), and the first start all use the same "system clock + time_to_next_mix + output_latency" start recipe from the docs, so build ONE `begin(from_position, lead_in)` routine.

gdUnit4 latest is v6.2.1, whose compatibility table lists Godot 4.5 through 4.7.1 (and 4.8 dev); **4.7.2 is not explicitly listed**, so Wave 0 must smoke-test it (fallback: GUT 9.x). [CITED: github.com/MikeSchulze/gdUnit4 README] Headless drift/autoplay verification should be done deterministically with a fake time source (fast, CI-safe); real-audio drift can only be observed manually/non-headless. Godot is not installed (verified: `godot` not on PATH), and `git` is not initialised in the repo, so Wave 0 begins with human prerequisites.

**Primary recommendation:** Build the logic layer first as `RefCounted` classes with an injected time source (Conductor math, InputJudge, HullScore, calibration math, settings I/O), prove it with gdUnit4 headless tests including autoplay all-Perfect, then wrap thin Node scenes around it; do the real-audio feel/export checks as an explicit human-gated plan.

## Architectural Responsibility Map

(Single-process desktop game; "tiers" are code layers.)

| Capability | Primary Layer | Secondary Layer | Rationale |
|------------|--------------|-----------------|-----------|
| song_time computation | Conductor (Node wrapping a pure `ClockModel` RefCounted) | AudioServer/AudioStreamPlayer | Needs engine audio APIs, but math is injectable/testable |
| Input capture + ticks stamp | `LaneInput` Node (`_input`) | InputMap | Only place that touches events; emits `(lane, pressed, ticks_usec)` |
| Judgment | `InputJudge` RefCounted | JudgeConfig resource | Pure logic; same API for human, autoplay, later bots |
| Hull/score/combo | `HullScore` RefCounted | HullConfig | Pure state; Phase 3/4 read it |
| Chart storage | `ChartData` RefCounted/Resource | Test chart builders | Format-agnostic, seconds-based |
| Rendering | Highway Control (`_draw`) | HUD Controls | Pure function of song_time + visual_offset + scroll speed |
| Settings/bindings persistence | `Settings` autoload | `ConfigFile` at `user://settings.cfg` | Global service per CONTEXT |
| Calibration math | `CalibrationMath` RefCounted | Calibration scene | Median/sign logic unit-testable |
| Audio buses/volume | `Settings` -> AudioServer | `default_bus_layout.tres` | Master/Music/SFX |
| Procedural audio (click, SFX, test song) | `AudioSynth` RefCounted producing `AudioStreamWAV` | AudioStreamPlayer pool | Sample-accurate, no generator-buffer latency |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Godot (standard) | 4.7.2-stable | Engine | Locked (D-01) |
| GDScript (typed) | built in | All code | Locked |
| `ConfigFile` | built in | `user://settings.cfg` | INI, no code-exec risk (unlike `load()` of `.tres`) |
| `InputMap` / `InputEventKey` / `InputEventJoypadButton` / `InputEventJoypadMotion` | built in | Runtime rebinding | Official runtime API [CITED: class_inputmap.html] |
| `AudioStreamWAV` (built from `PackedByteArray`) | built in | Procedural click track + SFX + synth test song | Sample-accurate, normal playback-position semantics |
| `AudioServer` buses | built in | Master/Music/SFX | Locked (D-21) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| gdUnit4 | v6.2.1 (README lists Godot 4.5-4.7.1; 4.7.2 unlisted) | Unit/headless tests | All logic tests (D-03). [CITED: github.com/MikeSchulze/gdUnit4] |
| GUT | 9.x | Fallback test framework | Only if gdUnit4 fails on 4.7.2 in the Wave 0 smoke test |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pre-rendered `AudioStreamWAV` metronome | `AudioStreamGenerator` | Generator is push-based with its own buffer latency and no meaningful `get_playback_position()`; wrong tool for a clock-reference stream. Use WAV. [ASSUMED: generator playback-position semantics from training knowledge] |
| Procedural synth demo song (WAV built at runtime) | Bundled CC0 OGG | Procedural gives exact BPM/tempo-change alignment with the hand chart and no licensing hunt; D-27(b) leaves track choice to discretion. A CC0 OGG can be added later; seeking in OGG is not sample-accurate. |
| Single `_draw()` highway | Pooled Sprite nodes | `_draw()` is simpler for ~30 visible notes; recommended. |

**Installation (human-gated):**
```powershell
# 1. Human: install Godot 4.7.2 standard (not .NET) + Windows export templates 4.7.2
#    Option A (manual): godotengine.org -> Godot_v4.7.2-stable_win64.exe.zip; unzip; export templates via Editor > Manage Export Templates
#    Option B: winget install --source winget GodotEngine.GodotEngine   (verify version == 4.7.2; id is [ASSUMED])
# 2. Human: setx GODOT_BIN "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"   (console build gives CLI stdout/exit codes)
# 3. Human-approved: download gdUnit4 v6.2.1 release zip -> copy addons/gdUnit4 into repo
godot --version        # expect 4.7.2.stable.*
```

**Version verification:** Godot version/date per STACK.md (4.7.2 on 2026-08-18) [CITED: godotengine.org/download/archive via STACK.md]. gdUnit4 v6.2.1 is the latest release per the GitHub releases page fetched this session [CITED: github.com/MikeSchulze/gdUnit4/releases]. Could not run `godot --version` (not installed) or `winget` non-interactively (msstore agreement prompt blocks; use `--source winget`).

## Package Legitimacy Audit

No npm/PyPI/crates packages are installed in this phase. The only third-party code is the gdUnit4 GDScript addon vendored from GitHub; slopcheck does not apply to that ecosystem and was not run.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| gdUnit4 v6.2.1 | GitHub release / Godot Asset Library | multi-year project | n/a | github.com/MikeSchulze/gdUnit4 (README + releases fetched this session) | n/a (non-npm/pip) | Approved, but planner should gate the download behind a `checkpoint:human-verify` (user must approve downloads per D-01 spirit) |

**Packages removed:** none. **Flagged suspicious:** none.

## Architecture Patterns

### System Architecture Diagram

```
 OS audio device <---- AudioServer mix thread <---- AudioStreamPlayer (song: WAV/OGG)
                              |                               |
        get_time_since_last_mix(), get_output_latency (cached ~1 Hz)
                              v
   Time.get_ticks_usec() --> [ClockModel (RefCounted)] <-- audio_offset (Settings)
                              |   disciplined estimate; never decreases; usec anchor
                              | song_time(frame)  +  song_time_at(ticks_usec)
          +-------------------+--------------------+
          v                                        v
 OS key/pad event --> LaneInput._input() --> InputJudge.press/release(lane, song_time)
   (edge-detect, ticks)   (stamp ticks)          ^                 |  results (judgment, error_ms)
                                                 | Autoplay (same API, exact note times)
                                                 v
                      JudgeConfig --> HullScore (hull, combo, streak, score, depth)
                                                 |
        ChartData (seconds notes + tempo map) -->|--> Highway._draw(song_time + visual_offset)
                                                 |--> HUD, feedback text/flash, SFX pool
                                                 |--> Implosion / Pause / Results
 Settings autoload <--> ConfigFile user://settings.cfg (bindings, offsets, volumes, scroll, toggles)
 F3 DebugOverlay reads Conductor + InputJudge
```

### Recommended Project Structure
```
undertow/
├── project.godot            # name, 4.7 feature tag, renderer=gl_compatibility, autoloads, input map defaults
├── export_presets.cfg       # Windows Desktop preset (committed)
├── default_bus_layout.tres  # Master, Music, SFX
├── addons/gdUnit4/          # vendored
├── src/
│   ├── core/                # clock_model.gd, conductor.gd, input_judge.gd, hull_score.gd, judge_config.gd, hull_config.gd, chart_data.gd, autoplay.gd, calibration_math.gd
│   ├── input/               # lane_input.gd, binding_store.gd
│   ├── audio/               # audio_synth.gd (click, sfx, synth song), sfx_pool.gd
│   ├── content/             # test_charts.gd (hand-authored ChartData builders)
│   ├── ui/                  # highway.gd, hud.gd, feedback.gd, debug_overlay.gd, menus, rebind, settings, calibration
│   └── autoload/            # settings.gd
├── scenes/
├── tests/                   # gdUnit4 suites (test_*.gd)
├── tools/                   # run_tests.ps1, export.ps1
└── README.md                # pinned version, prerequisites
```

### Pattern 1: Disciplined, monotonic song clock (D-05, D-06, D-07)
**What:** Per frame, take the docs formula as a *target*, extrapolate with the µs system clock between frames, slew toward the target, snap on large error, never return less than last value. Cache `get_output_latency()`.
**When:** Always; the single source of `song_time`.
**Example:**
```gdscript
# Source: docs "Sync the gameplay with audio and music" (formula) + design per D-05/D-06
class_name ClockModel extends RefCounted
var _anchor_ticks: int = 0          # usec at last update
var _song_time: float = 0.0
var _started := false               # audio actually producing position
const SNAP_S := 0.050
const SLEW := 0.15                  # fraction of error corrected per frame

func update(now_ticks: int, audio_target: float, audio_valid: bool) -> float:
    var dt := (now_ticks - _anchor_ticks) / 1_000_000.0
    var predicted := _song_time + dt
    if audio_valid:
        var err := audio_target - predicted
        predicted = audio_target if absf(err) > SNAP_S else predicted + err * SLEW
    _song_time = maxf(_song_time, predicted)      # never backwards
    _anchor_ticks = now_ticks
    return _song_time

func song_time_at(ticks: int) -> float:            # for _input events (D-06)
    return _song_time + (ticks - _anchor_ticks) / 1_000_000.0
```
`audio_target = player.get_playback_position() + AudioServer.get_time_since_last_mix() - cached_latency - audio_offset`. `audio_valid` is false until `get_playback_position()` > 0 after `play()` (first mix(s) report 0) and while paused. [ASSUMED: first-frames-return-0 behaviour; verify in the spike with the F3 overlay]

### Pattern 2: Single start routine for first start, pre-roll handoff, resume
**What:** Per docs, `play()` is not instantaneous; audio begins at the next mix plus output latency: `time_delay = get_time_to_next_mix() + get_output_latency()`. [CITED: sync_with_audio.html] During pre-roll/countdown song_time = `(now - t_begin) - time_delay + start_position - lead_in`; call `play(start_position)` when it reaches the start position minus time_delay (so audible start lands at song_time == start_position), then let Pattern 1 discipline onto the audio clock once `get_playback_position()` advances.
**Resume (D-26):** stop player, store position, show countdown from system clock, `play(paused_pos)` per the same recipe, re-anchor (reset `_started`). OGG seeks are not sample-accurate [ASSUMED]; bundled test audio is WAV so no error.

### Pattern 3: Judge as a pure per-lane queue machine (D-08..D-12)
**What:** `InputJudge` holds per-lane arrays of notes sorted by time with a head index. `press(lane, t)`: candidate = first unjudged note in lane with `note.time >= t - good_window - ...`; compute `dt = t - note.time`; `abs(dt) <= perfect` -> Perfect; `<= good` -> Good; `-early_miss <= dt < -good` -> Miss on that note; else stray (streak/combo break, optional chip damage = config 0). `tick(t)` marks unjudged notes with `t - note.time > good` as Miss. Sustain heads create a hold state; `release(lane, t)` evaluates tail (`t >= tail - 0.100` = full hold). Ticks emitted by `tick(t)` while held, at a fixed interval (choose beat-based or 0.1 s; document).
**Autoplay (D-28):** each tick, for notes with `time <= song_time`, call `press(lane, note.time)` then `release(lane, note.time + duration)` — exact times, not frame times, so result is deterministic across frame rates.

### Pattern 4: Edge-detecting LaneInput over InputMap actions (D-06, D-19, CAL-03)
**What:** `_input(event)`: ignore `event.is_echo()`; for each lane action `if event.is_action(name)`: compute `down = event.is_action_pressed(name)` (for keys/buttons) ; for `InputEventJoypadMotion` trigger events compute `down` from the action strength/deadzone; keep `held[lane]` and emit press only on false->true and release only on true->false. Stamp `Time.get_ticks_usec()` first thing. Then `judge.press(lane, clock.song_time_at(ticks))`.
**Why:** Analog trigger axes emit a stream of motion events while above threshold; without own edge detection each could register as a new press. [ASSUMED: exact `is_action_pressed` semantics for repeated joypad-motion events; edge detection is safe regardless]. Also handle window focus loss: release all held lanes (`NOTIFICATION_APPLICATION_FOCUS_OUT`).

### Pattern 5: Rendering = pure function of song_time
`y = hull_y - (note.time - (song_time + visual_offset)) * px_per_sec * scroll_mult`. Cull via a moving index range into the sorted note array. Judgment never reads scroll speed.

### Anti-Patterns to Avoid
- **Accumulating `delta`** for note position or song time (violates D-05; pitfall 1).
- **Calling `get_output_latency()` every frame** (documented as expensive). Cache; refresh ~1 Hz and on output-device change.
- **Polling `Input.is_action_just_pressed` in `_process`** (frame-quantizes timing).
- **Using `load()`/`ResourceLoader` on files in `user://`** for settings or charts (a `.tres` can embed scripts). Use `ConfigFile`/JSON with validation.
- **Tab as a gameplay key** (`ui_focus_next`), and relying on Esc being free of `ui_cancel` (use a dedicated `pause` action).
- **AudioStreamGenerator as the reference song stream.**

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| INI persistence | Custom file format/parser | `ConfigFile` | Handles types, sections, errors via return codes |
| Key display names | Own keycode->string tables | `InputEvent.as_text()` / `as_text_physical_keycode()`, `OS.get_keycode_string()` | Layout/locale correct |
| dB conversion | Own log math | `linear_to_db()` / `db_to_linear()` | Built in |
| Test harness | Own assert/runner | gdUnit4 (contingency only: a 30-line `SceneTree` script runner) | Reports, JUnit, CI |
| Audio mixing/polyphony for SFX | Own mixer | Pool of `AudioStreamPlayer` (or `AudioStreamPolyphonic`) on SFX bus | Engine mixer |
| Median | Ad-hoc | `Array.sort()` + middle index in `CalibrationMath` (unit-tested) | Trivial but sign/outlier errors are the risk |

**Key insight:** the only genuinely custom code needed is the clock discipline, the judge, and calibration math; everything else has an engine primitive.

## Runtime State Inventory

Not applicable (greenfield, no rename/refactor/migration). Skipped.

## Common Pitfalls

### Pitfall 1: Sign convention of `audio_offset` and `visual_offset`
**What goes wrong:** Calibration "fixes" the wrong direction; players are 2x worse.
**Why:** D-05 subtracts `audio_offset` inside song_time. A player who taps late by `e` (tap_song_time - click_time > 0) needs `song_time` *reduced* by `e`, so `audio_offset = +median(e)`. Note that this single tap-along measures the combined input + audio + human chain, and it also shifts the highway relative to the audible song; the visual step then re-aligns the display (`visual_offset` applies in rendering only).
**Avoid:** Write the convention in code comments and a unit test: synthetic tapper with known +37 ms bias must recover 37 ms (+-1) and, applied, yield ~0 error.
**Warning signs:** Re-running calibration after applying it gives a large non-zero median instead of ~0. Calibration must measure against *raw* (pre-offset) times, or explicitly subtract the currently applied offset.

### Pitfall 2: Pre-roll / resume handoff glitch
**What goes wrong:** song_time jumps or stalls when handing off from system clock to audio clock (first mix(es) report position 0; target momentarily wrong).
**Avoid:** `audio_valid` gating (Pattern 1), slew instead of snap for small errors, the clamp-monotonic guard, and a test that asserts monotonic + no step > 5 ms across the handoff with a simulated delayed audio start.

### Pitfall 3: `_input` timestamp is dispatch time, not press time
**What goes wrong:** Expecting `_input` to remove frame quantization entirely. Events are dispatched when the engine processes OS events at the start of a frame, so a press during a long frame is stamped late. [ASSUMED: dispatch-at-frame-start on Windows; confirm with a latency spike]
**Avoid:** Use the µs anchor mapping (removes the *additional* error of using a per-frame stale song_time), keep frame times short, offer a vsync-off / higher FPS setting, and accept the constant part is absorbed by calibration. Set `Input.use_accumulated_input = false` for gameplay. Document the residual in the README so playtest disputes have context.

### Pitfall 4: Analog trigger repeat presses / rebind capture
**What goes wrong:** A held LT produces repeated motion events -> multiple presses; rebinding captures stick drift as "LT".
**Avoid:** Edge detection (Pattern 4); during capture accept only `InputEventJoypadMotion` with axis in {`JOY_AXIS_TRIGGER_LEFT`, `JOY_AXIS_TRIGGER_RIGHT`} and `abs(axis_value) >= 0.5`; ignore sticks. Triggers are axes reported -1..1 per docs (resting 0 for XInput triggers; some DirectInput pads rest at -1 [ASSUMED]) so test with the dev's actual pad and expose the raw axis value in F3.

### Pitfall 5: Binding persistence stores the wrong thing
**Avoid:** Serialise keyboard as `physical_keycode` (int) so AZERTY layouts keep positions; joypad button as `button_index`; trigger as `{axis, sign}`. Rebuild `InputEvent` objects on load, `InputMap.action_erase_events(a)` then `action_add_event(a, ev)` (methods verified [CITED: class_inputmap.html]). Validate: unknown keys -> default; duplicates -> fall back to defaults for that action. Never trust the file (hand-editable): clamp numeric values (scroll 0.5-3.0, offsets +-500 ms, volumes 0-1), type-check each `get_value`.

### Pitfall 6: `get_output_latency()` is not truth on Windows
**What goes wrong:** WASAPI shared mode / Bluetooth devices add delay not reported. Wizard result absorbs it, but a device switch invalidates it.
**Avoid:** Store the output device name with the calibration; on mismatch at launch, prompt "re-calibrate?" (`AudioServer.output_device`, `get_output_device_list()` verified [CITED: class_audioserver.html]). The Bluetooth warning is a name heuristic only (D-17).

### Pitfall 7: Headless tests cannot prove real-audio sync
**What goes wrong:** Treating a passing headless "drift test" as evidence the speakers match the notes. Headless uses a dummy audio driver [ASSUMED], so `get_time_since_last_mix`/latency are not representative.
**Avoid:** Split D-30 into (a) deterministic fake-clock simulation: 5 min of jittered frames with injected hitches, assert note-judge times within +-2 ms of expected and clock monotonic; (b) a non-headless "Drift Harness" scene that runs the real click track for 5 min and logs `song_time` vs `Time.get_ticks_usec()` delta (shows device-clock drift) for a human to read; (c) human listening check with the F3 overlay and click track.

### Pitfall 8: Pause behaviour
**What goes wrong:** `get_tree().paused` auto-pauses `AudioStreamPlayer` (`stream_paused` is toggled automatically when the node is paused, [CITED: class_audiostreamplayer.html]) but the clock keeps extrapolating from the system timer.
**Avoid:** Explicit `Conductor.pause()` (freeze ClockModel, record position, `stop()` player) and `resume()` via Pattern 2. Pause menu nodes use `process_mode = PROCESS_MODE_ALWAYS`; gameplay `LaneInput` ignores events while paused.

### Pitfall 9: Windows export gotchas
**Avoid:** Commit `export_presets.cfg`; install matching 4.7.2 export templates (human); set `application/modify_resources` false to avoid needing `rcedit` [ASSUMED: well-known export requirement]; if charts are `.json`/`.cfg`, add `include_filter` (`*.json`) or they are silently omitted; writes only to `user://`. Run `godot --headless --path . --import` once after adding assets so `.godot/` import cache exists before tests/export. Debug build smoke command below.

### Pitfall 10: gdUnit4 version/flags drift
**Avoid:** Wave 0 smoke test: one trivial suite run through the CLI on 4.7.2 before any real work. `runtest.cmd` runs Godot **without** `--headless` (it opens a window and passes `-s -d --remote-debug tcp://127.0.0.1:0`) [CITED: raw runtest.cmd, gdUnit4 master]. A truly headless call is `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests` with extra flags (`--ignoreHeadlessMode` for older versions, `-c` continue-on-failure) that are [ASSUMED]; confirm with `--help` output on the installed version.

## Code Examples

### Cached latency + audio target (Conductor excerpt)
```gdscript
# Source: AudioServer docs (get_output_latency "can be expensive; not every frame")
var _latency_cache: float = 0.0
var _latency_next_refresh_ticks: int = 0

func _refresh_latency_if_due(now_ticks: int) -> void:
    if now_ticks >= _latency_next_refresh_ticks:
        _latency_cache = AudioServer.get_output_latency()
        _latency_next_refresh_ticks = now_ticks + 1_000_000

func _audio_target() -> float:
    return _player.get_playback_position() + AudioServer.get_time_since_last_mix() \
        - _latency_cache - Settings.audio_offset
```

### Procedural click track as AudioStreamWAV
```gdscript
# Pre-render: sample-accurate beat positions, no AudioStreamGenerator
static func make_click_track(bpm: float, seconds: float, rate: int = 44100) -> AudioStreamWAV:
    var n := int(seconds * rate)
    var buf := PackedByteArray(); buf.resize(n * 2)       # 16-bit mono, zero = silence
    var spb := 60.0 / bpm
    var beat := 0
    while true:
        var start := int(round(beat * spb * rate))
        if start >= n: break
        for i in range(mini(1200, n - start)):             # ~27 ms decaying sine burst
            var s := sin(TAU * 1000.0 * i / rate) * exp(-i / 250.0) * 0.8
            buf.encode_s16((start + i) * 2, int(s * 32767.0))
        beat += 1
    var w := AudioStreamWAV.new()
    w.format = AudioStreamWAV.FORMAT_16_BITS
    w.mix_rate = rate
    w.stereo = false
    w.data = buf
    return w
```
Use `AudioServer.get_mix_rate()` as `rate` to avoid resampling. 5 min mono 16-bit at 44.1 kHz is ~26 MB, acceptable. [ASSUMED: AudioStreamWAV property names as above; confirm in editor/docs at implementation]

### Calibration median with discard
```gdscript
static func audio_offset_from_taps(tap_times: Array[float], click_times: Array[float], discard: int = 4) -> float:
    var errs: Array[float] = []
    for i in range(tap_times.size()):
        var nearest := click_times[0]
        for c in click_times: if absf(c - tap_times[i]) < absf(nearest - tap_times[i]): nearest = c
        if i >= discard: errs.append(tap_times[i] - nearest)   # + = player late
    errs.sort()
    return errs[errs.size() / 2] if errs.size() % 2 == 1 else (errs[errs.size()/2 - 1] + errs[errs.size()/2]) * 0.5
```
(Taps must be recorded as raw, pre-`audio_offset` song times, or the applied offset added back.)

### Runtime rebinding + persistence
```gdscript
# Source: InputMap docs (action_erase_events/action_add_event); physical_keycode for layout independence
func bind_key(action: StringName, physical_keycode: Key) -> void:
    var ev := InputEventKey.new(); ev.physical_keycode = physical_keycode
    for old in InputMap.action_get_events(action):
        if old is InputEventKey: InputMap.action_erase_event(action, old)
    InputMap.action_add_event(action, ev)

func save_bindings(cfg: ConfigFile) -> void:
    for a in GAMEPLAY_ACTIONS:
        for ev in InputMap.action_get_events(a):
            if ev is InputEventKey: cfg.set_value("bindings", a + "_key", ev.physical_keycode)
            elif ev is InputEventJoypadButton: cfg.set_value("bindings", a + "_pad", ev.button_index)
            elif ev is InputEventJoypadMotion: cfg.set_value("bindings", a + "_pad_axis", [ev.axis, signf(ev.axis_value)])
```
Set trigger action deadzone to 0.5 via `InputMap.action_set_deadzone(a, 0.5)` (method exists [CITED: class_inputmap.html]); default LT/RT events: `InputEventJoypadMotion` with `axis = JOY_AXIS_TRIGGER_LEFT/RIGHT`, `axis_value = 1.0`.

### CLI commands (Windows)
```powershell
# one-time import cache
& $env:GODOT_BIN --headless --path . --import
# tests (gdUnit4 helper script; opens a window per its runtest.cmd)
.\addons\gdUnit4\runtest.cmd -a res://tests
# headless variant (flags to be confirmed on installed version)
& $env:GODOT_BIN --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
# debug export (preset name must match export_presets.cfg)
& $env:GODOT_BIN --headless --path . --export-debug "Windows Desktop" build/undertow-debug.exe
```
[CITED for export flags: docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Use hardware event timestamps | None exist in Godot (`InputEvent` has only `device`) | n/a | Use `Time.get_ticks_usec()` at dispatch; calibrate |
| gdUnit4 5.x / Godot 4.x broad | gdUnit4 6.x requires Godot 4.5+ | v6.0 | Fine for 4.7.2; verify patch compat |
| Docs: song-time formula | Unchanged; docs page still "not yet updated for Godot 4.7" | - | Treat as correct but verify with F3 overlay in the spike |

**Deprecated/outdated:** reliance on "AudioStreamGenerator as metronome" (push-buffer latency); `Tab` for gameplay.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `get_playback_position()` returns 0 / stale for the first mix(es) after `play()` | Pattern 1 | Handoff glitch handling is unnecessary or insufficient; verify in F3 spike |
| A2 | Windows dispatches queued input at frame start (press time not recoverable) | Pitfall 3 | Residual jitter bigger/smaller than assumed; affects window tuning only |
| A3 | Repeated joypad-motion events past the deadzone each report "pressed" | Pattern 4 | Edge detection harmlessly redundant |
| A4 | Some DirectInput pads rest triggers at -1 | Pitfall 4 | Minor; XInput is the main target |
| A5 | gdUnit4 headless flags (`-a`, `-c`, `--ignoreHeadlessMode`) and non-zero exit code on failure | Pitfall 10 | Test command in plans needs adjustment; confirm via `--help` in Wave 0 |
| A6 | gdUnit4 v6.2.1 works on 4.7.2 (README lists up to 4.7.1) | Standard Stack | Fallback to GUT; Wave 0 smoke test catches it |
| A7 | Headless Godot uses a dummy audio driver, not representative of real latency | Pitfall 7 | Drift evidence strategy would differ |
| A8 | `AudioStreamWAV` property names/behaviour as in the example; AudioStreamGenerator unsuitable as clock reference | Code Examples | Minor rework |
| A9 | `application/modify_resources=false` avoids rcedit need on Windows export | Pitfall 9 | Export fails until rcedit configured (human) |
| A10 | winget id `GodotEngine.GodotEngine` provides 4.7.2 | Installation | Use manual zip instead |
| A11 | OGG seek is not sample-accurate | Pattern 2 | Only matters if OGG track used with resume |
| A12 | `audio/driver/output_latency` default ~15 ms and settable | Pitfall 6 / planning | Latency tuning advice off |

## Open Questions (RESOLVED)

1. **Does the disciplined-clock slew produce a visually smooth ramp on the dev machine?** Unknown until the F3 overlay runs on real audio. Recommendation: make the spike (Conductor + click track + F3 graph) the first non-test deliverable, with SLEW/SNAP constants exposed in a config.
   RESOLVED: Plan 01-02 task 3 adds a song_time readout/graph to the skeleton, judged by the human in the 01-02 checkpoint; constants live in JudgeConfig (clock_snap_s, clock_slew).
2. **Sustain tick cadence (D-14 gives 10 per tick but not the interval).** Recommendation: one tick per 1/8 beat... or fixed 0.1 s; planner picks and puts it in `JudgeConfig`.
   RESOLVED: fixed 0.1 s, `JudgeConfig.sustain_tick_interval` (plans 01-02, 01-03).
3. **Tempo change in the test chart and beat visuals.** `ChartData` should carry a small tempo map (time, bpm) for beat lines and countdown length even though note times are seconds.
   RESOLVED: `ChartData.tempo_map` (plan 01-02), hand_chart includes a tempo change (plan 01-03); countdown uses it (01-03/01-06).
4. **Does gdUnit4 6.2.1 CLI run fully headless on 4.7.2 including scene tests?** Wave 0 smoke; logic tests do not need scenes.
   RESOLVED: gdUnit4 smoke test in plan 01-01 task 2; scene-runner tests first appear in 01-02 (test_boot_smoke) and stop-and-report if they fail.
5. **Visual calibration method:** D-16 allows slider or silent tap test. Recommend slider (simplest) plus optional tap test; planner decides.
   RESOLVED: slider-only visual calibration (plan 01-07 task 2); no tap test in Phase 1.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Godot 4.7.2 standard | Everything | NO (`command -v godot` empty) | - | None; human prerequisite (D-01) |
| Godot export templates 4.7.2 | D-31 export | NO (cannot exist without Godot) | - | None; human install |
| gdUnit4 addon | D-03 tests | NO (not vendored yet) | v6.2.1 target | GUT 9.x, or minimal custom SceneTree runner |
| git repo | commit_docs / history | NO (directory is not a git repo) | - | `git init` by plan/human |
| winget | Optional Godot install | Present, but non-interactive use blocked by msstore agreement prompt | - | Manual zip download |
| Python 3.14.7 | Not required | Yes | 3.14.7 | - |
| Second Windows PC (friend) | D-31, feel validation | Human | - | Defer to end-of-phase human verify (config `human_verify_mode: end-of-phase`) |
| Wired audio output + gamepad | Calibration/gamepad validation | Unknown | - | Human check |

**Missing with no fallback:** Godot install + export templates (human). Plan 01 task 1 must be a `checkpoint:human-action` (install, set `GODOT_BIN`, confirm `godot --version`), and no automated task may run before it.
**Missing with fallback:** gdUnit4 (needs approved download), git init.

## Validation Architecture

(Included at request; `workflow.nyquist_validation` is false in config but the caller asked for it.)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | gdUnit4 v6.2.1 (fallback GUT 9.x) |
| Config file | none; project-level GdUnit settings created by addon on first run (Wave 0) |
| Quick run command | `& $env:GODOT_BIN --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/<suite>.gd` [flags ASSUMED, confirm Wave 0] |
| Full suite command | `.\addons\gdUnit4\runtest.cmd -a res://tests` (opens a window) or the headless variant with `-a res://tests` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TIME-01 | ClockModel monotonic, bounded error vs reference under jitter/hitches; 5 min simulated within +-2 ms; handoff no step | unit (fake clock) | run `tests/test_clock_model.gd` | Wave 0 |
| TIME-01 | Real-audio drift/feel | manual (Drift Harness + F3 + listening) | n/a | manual |
| TIME-02 | Same physical press times judged identically under 30/60/144 fps schedules | unit | `tests/test_input_mapping.gd` | Wave 0 |
| TIME-03 | Window boundaries (35/70/100 ms, early-miss, late-miss, stray) | unit table | `tests/test_input_judge.gd` | Wave 0 |
| TIME-04 | Chords independent; sustain head/ticks/early release/forgiving release | unit | `tests/test_sustain_chord.gd` | Wave 0 |
| TIME-05 | Autoplay on every test chart + 5 min click chart = all Perfect, 0 Miss, hull 100 | unit/headless | `tests/test_autoplay.gd` | Wave 0 |
| CAL-01 | Median/discard/sign recovery of synthetic bias; settings roundtrip of offsets | unit | `tests/test_calibration_math.gd` | Wave 0 |
| CAL-01 | Wizard UX, device/latency display, Bluetooth warning | manual + unit for name heuristic | `tests/test_bt_heuristic.gd` | Wave 0 |
| CAL-02 | Rebind apply/persist/reload; duplicate rejection; reset defaults | unit | `tests/test_bindings.gd` | Wave 0 |
| CAL-03 | Synthetic JoypadMotion sequence -> exactly one press/release per crossing at 0.5; button events | unit | `tests/test_lane_input.gd` | Wave 0 |
| CAL-04 | Scroll/volume clamp + persist; bus volume applied | unit | `tests/test_settings.gd` | Wave 0 |
| HULL-01 | Miss -8, Perfect +1 capped 100, Good 0, hull 0 -> failed state; No-Fail | unit | `tests/test_hull_score.gd` | Wave 0 |
| HULL-02 | Combo/multiplier/score/depth numbers | unit | `tests/test_hull_score.gd` | Wave 0 |
| HULL-03 | Feedback shown per judgment | manual (visual/audio) + scene smoke boots without errors | `tests/test_boot_smoke.gd` | Wave 0 |
| HULL-04 | Pause/resume re-anchor: song_time frozen while paused, countdown, continues from paused position | unit (ClockModel/Conductor logic) + manual audio check | `tests/test_pause_resume.gd` | Wave 0 |

### Sampling Rate
- **Per task commit:** suite relevant to the touched class (headless, < 30 s).
- **Per wave merge:** full gdUnit4 suite.
- **Phase gate:** full suite green + human checks: real-audio drift harness, 4-lane feel on dev PC, gamepad, export smoke on second PC.

### Wave 0 Gaps
- [ ] Human: install Godot 4.7.2 + templates, set `GODOT_BIN`; `git init`
- [ ] `project.godot`, `.gitignore` (`.godot/`, `build/`, `reports/`), `README.md` with pinned version
- [ ] Vendor gdUnit4 v6.2.1 (approved download) and run a trivial suite on 4.7.2 via the CLI; record the working command line in README
- [ ] `tests/` directory + shared `FakeTime` helper (injectable ticks source)
- [ ] `--import` run to create the `.godot` cache

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | n/a (no accounts/network in this phase) |
| V3 Session Management | no | n/a |
| V4 Access Control | no | n/a |
| V5 Input Validation | yes | Validate/clamp every value read from `user://settings.cfg`; type-check; fall back to defaults; chart/ChartData builders assert lane range 0-3, non-negative durations, sorted times |
| V6 Cryptography | no | none required |
| V12 Files/Resources | yes (relevant here) | Use `ConfigFile`/JSON for user-writable data; do not `load()` user-provided `.tres`/`.res` (embedded scripts); write only under `user://` |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tampered/corrupt `settings.cfg` (NaN, huge offsets, wrong types) | Tampering / DoS | Validate + clamp on load; on parse error back up and reset to defaults |
| Malicious resource loaded from `user://` executes script | Elevation | Never `ResourceLoader.load` user files in this phase |
| Downloading unverified binaries (Godot, addon) | Tampering (supply chain) | Human-approved downloads from official sources; verify Godot checksum from godotengine.org; pin gdUnit4 tag |

## Sources

### Primary (HIGH confidence)
- docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html (fetched): formula, "discard if less than previous frame", system-clock start recipe, time_delay, drift caveat, "not yet updated for 4.7" banner
- docs.godotengine.org/en/stable/classes/class_audioserver.html (fetched): `get_time_since_last_mix`, `get_time_to_next_mix`, `get_output_latency` (expensive, not every frame), `output_device`, `get_output_device_list`
- docs.godotengine.org/en/stable/classes/class_audiostreamplayer.html (fetched): `get_playback_position` accuracy note, `stream_paused` auto-toggle on tree pause, `play(from_position)`, `finished` signal
- docs.godotengine.org/en/stable/classes/class_inputevent.html (fetched): only `device` property, no timestamp
- docs.godotengine.org/en/stable/classes/class_inputmap.html, class_inputeventjoypadmotion.html (fetched): runtime rebind API, axis_value -1..1, trigger axes
- docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html (fetched): CLI export flags, presets/templates requirements
- github.com/MikeSchulze/gdUnit4 README + releases + raw `runtest.cmd` (fetched): v6.2.1 latest, Godot 4.5-4.7.1 (+4.8 dev), runtest.cmd behaviour

### Secondary (MEDIUM confidence)
- Project research STACK.md / PITFALLS.md / SUMMARY.md (earlier sessions)
- WebSearch snippets on gdUnit4 CLI shape (`--headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd`)

### Tertiary (LOW confidence)
- Everything tagged [ASSUMED] in the Assumptions Log (training knowledge)
- Search-result claim that Godot supports input event "timestamp capture" refers to recording ticks in `_input` and is not an engine timestamp (contradicted by class docs)

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM-HIGH (built-ins verified; gdUnit4 4.7.2 compat unverified)
- Architecture: HIGH for the logic layering; MEDIUM for clock-discipline constants (need on-device tuning)
- Pitfalls: MEDIUM (several Windows driver behaviours assumed, to be confirmed by the first spike)

**Research date:** 2026-10-07
**Valid until:** about 30 days (engine patch releases may change the docs banner; re-check gdUnit4 tags)

## Project Constraints (from CLAUDE.md)

- Engine Godot 4.x stable, GDScript preferred; Windows desktop first; hit judgment accurate to about +-50 ms window range with the audio clock as source of truth; no copyrighted music bundled; solo-dev scope discipline.
- Follow the GSD workflow: file-changing work must start via a GSD command (`/gsd:execute-phase`, `/gsd:quick`, `/gsd:debug`).
- Stack section of CLAUDE.md forbids: `get_playback_position()` alone or `_process(delta)` accumulation as the clock; network-synced judgment; Godot 3.x or alpha/beta builds.
- No project skills present.
