# Phase 1: Timing Core & Calibration - Context

**Gathered:** 2026-10-07
**Status:** Ready for planning
**Mode:** auto (all gray areas resolved with the recommended default; see 01-DISCUSSION-LOG.md)

<domain>
## Phase Boundary

A single player can launch the game, calibrate their machine, and play a song solo on a minimal 4-lane sonar highway. Notes stay locked to the audio clock, and each press is judged Perfect / Good / Miss with feedback. Sustains and chords work. A hull takes damage from misses and can hit zero. Controls are rebindable (keyboard plus gamepad), with scroll speed and volume settings and pause/resume.

**Not in this phase:**
- Clone Hero import or song select (Phase 2)
- Torpedoes, payloads, rivals (Phase 3)
- Networking (Phase 4)
- The full CRT shader look and the release build (Phase 5)

Fire and Target-cycle are bindable here but do nothing yet.

</domain>

<decisions>
## Implementation Decisions

### Engine & Project Setup
- **D-01:** Godot **4.7.2-stable**, standard (non-.NET) build. Typed GDScript throughout. Pin the version in `project.godot` and the README. Godot is NOT installed on the dev PC yet. Installing it is a download step that the **user must approve or do themselves**. Plans must list it as a human prerequisite and must not silently download binaries.
- **D-02:** The Godot project lives at the repo root (`C:\Users\user\Documents\undertow`), next to `.planning/`.
- **D-03:** Test framework: **gdUnit4** (6.x, latest compatible with 4.7.2; vendored in `addons/`). Pure logic (clock math, judgment, hull, config) lives in `RefCounted` classes with an injectable time source, so tests run headless.
- **D-04:** Renderer: **Compatibility**. It has the broadest support across friends' PCs.

### Song Clock (TIME-01, TIME-02)
- **D-05:** A `Conductor` is the single source of `song_time`: `get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() - audio_offset`.
  - The value is **clamped so it never goes backwards** and smoothed against the mix-buffer stair-step.
  - Nothing may accumulate `delta`.
- **D-06:** Input is judged in `_input()`, never by polling in `_process`. Each event is timestamped with `Time.get_ticks_usec()` and converted to song time via the Conductor's ticks↔song-time mapping, so frame rate never shifts judgment.
- **D-07:** Pre-roll: a 2-beat lead-in where song_time runs from the system clock while negative, then hands off to the audio clock at 0.

### Timing Judgment (TIME-03, TIME-04)
- **D-08:** All windows live in one data-driven `JudgeConfig` resource. Starting values, to be tuned by playtest:
  - **Perfect** ±35 ms, **Good** ±70 ms.
  - A press up to **100 ms early** with no better candidate counts as a Miss on that note.
  - A note that passes +70 ms unhit is a Miss.
  - These meet the PROJECT ±50 ms constraint (Perfect is tighter than ±50, Good is forgiving).
- **D-09:** **Chords:** each note in a chord is judged independently. No "all frets together" rule, which suits keyboard play.
- **D-10:** **Stray presses** (no note within the 100 ms window in that lane) break the Perfect streak and the combo. They do NOT damage the hull in Phase 1. Hull chip damage is a `JudgeConfig` value with default 0, so it can be tuned later.
- **D-11:** **Sustains:**
  - The head is judged like a tap.
  - Holding earns score ticks.
  - Releasing early just ends the sustain: no hull damage, but the remaining ticks are lost.
  - Releasing within **100 ms before the tail** counts as a full hold (forgiving release, per research).
- **D-12:** Two counters, kept separate:
  - **Combo**: any non-Miss hit. Drives the score multiplier.
  - **Perfect streak**: Perfect hits only. Displayed now, and charges torpedoes in Phase 3.

### Hull & Scoring (HULL-01, HULL-02)
- **D-13:** **Hull**:
  - Starts at 100.
  - Each Miss costs 8.
  - Each Perfect restores 1 (small regen, so one bad passage isn't a death spiral).
  - Good costs nothing.
  - Values live in `JudgeConfig`/`HullConfig`.
- **D-14:** **Score / Depth**:
  - Perfect = 100, Good = 50, sustain tick = 10.
  - Multiplier steps 1×→2×→3×→4× every 10 combo, resetting on a Miss.
  - **Depth** shown in meters = score / 100. It is the diegetic score readout.
- **D-15:** **Hull reaches 0 → "IMPLOSION"** fail screen with Retry and Back. A **No-Fail toggle** (practice) keeps playing at 0 hull and flags the result.

### Calibration (CAL-01)
- **D-16:** First launch forces the calibration wizard (skippable). It can be re-run from Settings.
  - **Audio offset:** tap along to 16 metronome clicks at 100 BPM. Discard the first 4 taps and take the **median** of the rest.
  - **Visual offset:** a flashing note crosses the hull line in time with clicks. The player nudges a slider (±1 ms / ±10 ms steps) until flash and click line up, or does a tap test against a silent visual-only marker.
  - Both are saved per machine in `user://settings.cfg`.
- **D-17:** Show the detected output latency and buffer size in the wizard.
  - Warn when the output device name suggests Bluetooth (contains "Bluetooth", "Headset", "AirPods", "Buds", etc.). The warning recommends a wired output.

### Controls & Settings (CAL-02, CAL-03, CAL-04)
- **D-18:** Default keyboard:
  - **Lanes** D F J K
  - **Fire** Space
  - **Target-cycle** H
  - **Pause** Esc
  - **Do NOT use Tab**: it collides with Godot's built-in `ui_focus_next`.
- **D-19:** Default gamepad:
  - **Lanes** LB, LT, RT, RB (shoulders, so both hands rest on the triggers).
  - **Fire** A (South).
  - **Target-cycle** Y (North).
  - **Pause** Start.
  - Trigger presses use a digital threshold of 0.5.
- **D-20:** The rebind screen:
  - Every action can be rebound.
  - Each action holds at most 1 keyboard key + 1 gamepad button.
  - Duplicate bindings within the gameplay set are rejected with a message.
  - "Reset to defaults" is available.
  - Bindings persist in `user://settings.cfg`.
- **D-21:** Settings:
  - **Scroll speed** multiplier 0.5×–3.0× in 0.1 steps (default 1.0×).
  - **Volume** for Master, Music, SFX as separate audio buses.

### Feedback (HULL-03)
- **D-22:** Each judgment gives a lane flash at the hull line plus floating text (PERFECT / GOOD / MISS).
  - Perfect and Good play a subtle hit tick (SFX bus, can be muted). Miss plays a dull "clunk" and a small screen nudge.
  - Feedback uses **shape and text, not color alone**: groundwork for the accessibility rules on Phase 3 payloads.
- **D-23:** An early/late indicator (small arrow or "+12ms" readout) can be toggled in Settings. It is on by default during calibration and practice.

### Highway Look (Phase 1 minimal)
- **D-24:** The minimal readable sonar look:
  - Black background, 4 vertical lanes in phosphor green (#39FF14-ish).
  - Notes scroll top→bottom to a horizontal "hull line".
  - Each lane's note has a distinct shape (◆ ● ▲ ■), so notes stay readable without color.
  - Sustains are tails.
  - A HUD shows hull bar, combo, multiplier, Perfect streak, and depth.
- **D-25:** Highway rendering: pooled note nodes or `_draw()`, whichever is simpler. It must hold 60+ fps with ~20 notes/sec on screen. No CRT shader yet (AV-01 is Phase 5).

### Pause (HULL-04)
- **D-26:** Esc/Start pauses (solo only). The audio stops, and the Conductor freezes.
  - Resuming plays a **3-beat countdown** and restarts audio from the paused position.
  - The Conductor re-anchors on the audio clock.
  - The pause menu offers Resume, Restart, Settings, Quit.

### Phase 1 Content (needed before Phase 2 import exists)
- **D-27:** The song for Phase 1 is **generated or bundled test content**, not imported:
  - (a) A procedurally generated metronome/click track at configurable BPM, for calibration and drift tests.
  - (b) One short royalty-free or CC0 OGG loop or track, with a hand-authored test chart that has taps, chords, sustains, and a tempo change.
  - Charts are defined in a minimal internal `ChartData` (seconds-based note arrays: lane, time, duration), which Phase 2's importer will also produce. Keep `ChartData` format-agnostic.
- **D-28:** **Autoplay (TIME-05)** feeds the same `press(lane, song_time)` / `release(lane, song_time)` API at exact note times. It must score all-Perfect on every test chart. This is the main automated correctness check, run headless in tests where possible.

### Dev Tooling
- **D-29:** **F3 debug overlay**:
  - Live song_time, raw playback position, time_since_last_mix, output latency, offsets, and fps.
  - A graph of song_time per frame (should be a smooth ramp).
  - The last 20 hit errors in ms.
- **D-30:** **Drift test**: a 5-minute generated click track with autoplay. Assert that note times stay within ±2 ms of the expected song_time throughout (TIME-01 evidence).
- **D-31:** **Export smoke test**: export a Windows debug build early in the phase and run it on a second PC (a friend's) to check latency and feel. This is the gate called for in the research. It needs a human to run it on the second machine.

### Claude's Discretion
- Scene and folder layout, class names beyond Conductor/InputJudge/HullScore/JudgeConfig/ChartData, and the UI layout of the settings and calibration screens.
- Exact metronome sound and hit SFX (procedural or CC0).
- Whether highway notes use pooled nodes or a single `_draw()`.
- Choice of the specific CC0 test track.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope & requirements
- `.planning/PROJECT.md`: game design, Core Value, constraints (±50 ms, Godot 4.x, Windows)
- `.planning/REQUIREMENTS.md`: TIME-01..05, CAL-01..04, HULL-01..04 (this phase)
- `.planning/ROADMAP.md` § Phase 1: goal and success criteria

### Research (timing core)
- `.planning/research/SUMMARY.md`: reconciled recommendations, Phase 1 gate, gaps (timing windows, test framework)
- `.planning/research/STACK.md`: Godot 4.7.2 pin, audio-clock recipe, gdUnit4/GUT choice, renderer
- `.planning/research/ARCHITECTURE.md`: Conductor / InputJudge / HullScore / ChartData boundaries, ticks→song-time input mapping, build order
- `.planning/research/PITFALLS.md`: audio clock, `_input` vs `_process`, Bluetooth latency, Tab/`ui_focus_next`, Windows WASAPI
- External: Godot docs, "Sync the gameplay with audio and music" (https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html). Re-check on 4.7 before building the Conductor.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None. Greenfield: no Godot project exists yet (repo contains only `.planning/` and `CLAUDE.md`).

### Established Patterns
- None yet. Phase 1 sets them up:
  - Logic in testable `RefCounted` classes.
  - Autoloads only for global services (Settings, Calibration).
  - Match-scoped nodes in the gameplay scene.

### Integration Points
- `ChartData`: Phase 2's importer must output this.
- `press()`/`release()` judgment API: reused by autoplay now, and by bots and payload logic in Phase 3.
- Perfect-streak counter: Phase 3's torpedo tube reads it.
- `JudgeConfig`/`HullConfig` resources: Phase 3 payload rules and Phase 4 netcode read hull/score state from `HullScore`.

</code_context>

<specifics>
## Specific Ideas

- Theme from PROJECT.md:
  - The highway is a submarine **sonar screen**.
  - The strike line is the **hull line**.
  - Score is shown as **depth in meters**.
  - Failure is an **IMPLOSION**.
  - Keep this diegetic language in the UI text, even with the minimal look.
- Notes are recognisable by shape as well as lane, so Phase 3 Ghost Notes can use a different shape for accessibility.

</specifics>

<deferred>
## Deferred Ideas

- Full CRT/phosphor shader, bioluminescent background, underwater audio filter: Phase 5 (AV-01..05).
- Clone Hero `.chart` import, song library and song select: Phase 2.
- Fire and Target-cycle doing anything: Phase 3.
- Hull chip damage for stray presses (config exists, default 0): revisit in Phase 3 playtests.

</deferred>

---

*Phase: 01-timing-core-calibration*
*Context gathered: 2026-10-07*

## Amendments

- **2026-10-07, gap closure 01-09:** D-17 refined. The "headset" marker counts as Bluetooth only together with "hands-free" or "bluetooth". This avoids false positives on 2.4 GHz dongles such as "Razer BlackShark V2 Pro 2.4". Under the "Default" output alias, Godot cannot see the real endpoint, so the Bluetooth warning is advisory only. The plan also adds a standing "Switched headphones or speakers? Calibrate Sonar again." line.
- **2026-10-07, gap closure 01-09:** the runtime device-name lookup uses Godot APIs only. There is no OS.execute or PowerShell in shipped code.
