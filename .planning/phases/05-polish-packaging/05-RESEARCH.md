# Phase 5: Polish & Packaging - Research

**Researched:** 2026-10-20
**Domain:** Godot 4.7.2 (GL Compatibility) audio-visual polish: bus effects, procedural SFX, event-driven juice, weak-PC performance, Windows friend build
**Confidence:** HIGH for the codebase audit and engine API facts (checked against the local 4.7.2 binary). MEDIUM for the scheduling and weak-PC proxy methods (derived from the engine API and the house pattern; to be confirmed during execution).

<user_constraints>
## User Constraints (no CONTEXT.md; there was no discuss session)

The user is away and asked for autonomous progress. The orchestrator gave these constraints. Treat them as locked:

- Never touch the pinned timing files: `src/core/conductor.gd`, `clock_model.gd`, `input_judge.gd` and `hull_score.gd` at `72e21ce`, and `src/core/judge_config.gd` at `2c2e54c`. `tools/check_timing_gate.ps1` enforces this.
- No copyrighted audio. Generate SFX procedurally, or use CC0 assets and credit them.
- Skip anything already DONE. Research only the gaps.
- Recommended decisions are orchestrator defaults (D-xx below). A later discuss session may override them.
- From the user's memory: keep working through limits, polish, then move to the next phases. **No release publishing.** Build the friend zip locally, but do not upload or publish a GitHub release.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Audit | Research support |
|----|-------------|-------|------------------|
| AV-01 | Highway renders as a sonar CRT screen (phosphor glow, scanlines, sweep afterglow) | **DONE** | `shaders/sonar_surface.gdshader` + `Highway._apply_surface_material/_update_sweep` |
| AV-02 | Trench background with bioluminescent life pulsing on the beat | **DONE** | `src/ui/arena.gd` (colonies, Living/Calm styles) |
| AV-03 | Sonar pings on downbeats, hull creaks, muffled filter that grows with damage | **MISSING** | Patterns 1-3, D-02..D-04 |
| AV-04 | Torpedo impacts, eliminations and launches have shake/flash/implosion feedback | **PARTIAL** (visual telegraphs exist; no impact shake, no launch juice, no SFX for impact/launch/implosion) | Pattern 4, D-05 |
| AV-05 | A low-effects toggle keeps the game smooth on weaker PCs | **PARTIAL** (toggle and contract done; never measured on weak hardware; versus Full gate borderline) | Pattern 5, D-06..D-08 |
| DIST-01 | Windows build friends download and run without Godot | **PARTIAL, nearly DONE** (single exe, self-tested zip; second-PC UAT still pending; no icon or version metadata; Godot splash) | Pattern 6, D-09, D-10 |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Engine: Godot **4.7.2-stable**, standard (non-.NET) build, GDScript. Renderer: **gl_compatibility** (`project.godot` [VERIFIED: project.godot]).
- Audio clock is the source of truth: `song_time = pos + time_since_last_mix - output_latency (- audio_offset)`. Never use `_process` delta accumulation as a clock.
- Keep logic in pure, typed `RefCounted` classes so it can be unit tested. Tests use gdUnit4 (6.2.1 vendored in `addons/gdUnit4` [VERIFIED: plugin.cfg]).
- Content/legal: public builds bundle no copyrighted music. The friends-only build bundles the user's songs (D-13). New SFX must be procedural or CC0.
- Windows desktop first. Friends get an unsigned zip; SmartScreen will warn, so tell them.
- Do not use `MultiplayerSynchronizer` or network-synced judgment. Phase 5 adds **no** network messages.
- Repo conventions seen in code: colours come from `Palette` tokens only (`test_color_literals.gd`). Every visual effect node uses the effect contract `UiKit.register_fx` + `apply_effect_settings()` + `effect_counts()` (`test_effect_settings.gd`). Full-screen canvases implement `keepout_shapes()` (`test_layout_keepout.gd`).

## Summary

Most of Phase 5's look shipped early. Phase 02.2 delivered the sonar CRT surface shader: lit-glass lane edges, phosphor lift, a per-bar sweep with a 400 ms afterglow, and 2-in-4 px scanlines. It also delivered the living/calm trench with beat-pulsing bioluminescent colonies, the Low effects and Reduce motion switches with a tested effect contract on every screen, and a perf harness that records Full and Low p95 at 1080p. Phase 3 added the versus telegraphs: red edge flash at launch and arrival, alert slot, incoming ping, panel edge flashes, and an IMPLOSION banner with shake and red vignette. Phase 02.2.1.1 / 4 / 02.2.2 delivered a single-file `UNDERTOW.exe` (embedded PCK) in a self-tested friend zip with README, checklist, ONLINE_SETUP and the Autocharter pack. **AV-01 and AV-02 are DONE and need only screenshot re-verification.**

The real gaps are mostly **audio**. There is no downbeat ping, no hull creak, and no low-pass filter anywhere (`default_bus_layout.tres` has only a SpectrumAnalyzer on Preview) [VERIFIED: grep]. Juice gaps: no board shake or flash when a torpedo lands, nothing for the shooter on launch, and no sound for impact, launch or implosion. Weak-PC smoothness has never been measured on weak hardware; every PERF row is from a discrete GPU. The dev PC now has an RX 9070 XT plus a Ryzen 9800X3D iGPU ("AMD Radeon(TM) Graphics"), so the old RX 6600 XT baselines need re-taking, and the iGPU can serve as an on-machine weak-GPU proxy. DIST-01 works, but it lacks an app icon, exe version metadata and a branded boot splash, and the real second-PC test is still a pending human UAT from earlier phases.

**Primary recommendation:** Add one gameplay-scoped `DiveAudio` node with three parts: downbeat pings scheduled with a lead-silence offset, procedural hull creaks, and a runtime `AudioEffectLowPassFilter` on the Music bus driven by hull and removed on exit. Add one event-driven `TorpedoJuice` view node: impact shake/flash, launch kick, implosion sound. Both use procedural `AudioSynth` generators. Then measure Low effects on the iGPU proxy (ANGLE + Windows power-saving GPU preference), fix VersusHud per-frame cost, add a slow-frame hint, polish the exe (icon, splash, version), and build v0.8.0 locally without publishing.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Downbeat pings | Client audio (SFX bus, gameplay node) | Pure scheduling math (RefCounted) | Reads `Conductor.song_time()` and tempo/time-sig data, never writes the clock |
| Hull creaks + muffle | Client audio (SFX bus + Music bus effect) | Pure mapping functions | Driven by the existing `score.hull_changed(value, delta)` signal; no change to HullScore |
| Torpedo juice | Client view (board/HUD/periscope) + SFX | EventChannel (existing) | View-only reactions to existing GameEvents (`TORPEDO_LAUNCH`, `LANDED`, `IMPLODED`); works offline and online with no protocol change |
| Low effects / slow-frame hint | Client view + Settings autoload | Perf harness (tools) | Effect contract already exists; the detector is a pure frame-time counter |
| Weak-PC measurement | Tooling (playtest harness, PowerShell) | — | Measurement only, not shipped code |
| Windows build | Build tooling (`export_presets.cfg`, `tools/dist.ps1`) | Docs (`tools/dist/README.txt`) | Export-time only |

## Audit: Phase 5 success criteria vs. codebase

| # | Criterion / Req | Status | Evidence |
|---|-----------------|--------|----------|
| 1a | Phosphor sonar CRT highway with scanlines and sweep afterglow (AV-01) | **DONE** | `shaders/sonar_surface.gdshader` (scanlines 2 px every 4 px, phosphor rail lift, per-bar sweep band + `exp` afterglow trail, lane-edge glass); `src/ui/highway.gd:995-1047` sets uniforms from Palette and Trench; Low effects removes the material, Reduce motion keeps scanlines and turns the sweep off. The CRT blink and visor are from 01.1/01.2 (`goggles_intro.gd`, `cockpit_frame.gd`). Note: the phosphor colour is `Palette.SONAR` #05D9E8 (cyan-teal), not literal green; see D-01 |
| 1b | Trench background, bioluminescent life pulsing on the beat (AV-02) | **DONE** | `src/ui/arena.gd`: colonies alpha `0.25 + 0.55*pulse*tier_gain` from `BeatClock.pulse(BeatClock.phase(song_t))`, Living vs Calm style (Calm default: low-passed breathe), lantern fish, marine snow, creature; counts halved under Low effects |
| 2a | Sonar pings land on downbeats (AV-03) | **MISSING** | The only ping is `VersusSfx.ping()` (incoming torpedo telegraph, `src/audio/versus_sfx.gd`), not beat-locked. No downbeat audio anywhere. `BeatClock.beats_between(t0,t1,tempo,time_sigs)` already returns `{time, bar}` entries to build on |
| 2b | Hull creaks grow as hull drops (AV-03) | **MISSING** | `grep -i creak` finds nothing. `score.hull_changed` is already connected in `gameplay.gd:247` (`_on_hull_arena`) |
| 2c | Muffled underwater filter grows with damage (AV-03) | **MISSING** | No `AudioEffectLowPassFilter` in `default_bus_layout.tres` or `src/` (grep). The song plays on bus `Music` (`conductor.gd:40`, pinned). Menu music and preview play on `Preview`, which sends to `Music` |
| 3a | Torpedo impact: shake/flash | **PARTIAL** | Arrival pulse of `EdgeFlash` (`src/ui/versus/edge_flash.gd`, 0.30 alpha over 300 ms); alert slot switches to ACTIVE; hull arc damage flash on hull loss. **No board shake on LANDED; no impact SFX.** The board shake exists only for a Miss (`FxLayer.request_shake()`, 6 px / 120 ms, `fx_layer.gd:390`) |
| 3b | Torpedo launch feedback | **PARTIAL** | Target side: edge flash + `VersusSfx.ping` + alert + warhead rings. Shooter side: `RewardSocket` icon shrink/fade only. **No launch SFX, flash or kick for the shooter.** Rival panels flash red on launch (`periscope_panel.gd:219-226`) |
| 3c | Elimination: implosion feedback | **PARTIAL** | Local versus: `EventBanner` IMPLOSION with 8 px shake + red vignette (`event_banner.gd:168-173`); solo: `FailScreen` squash + title shake. Rival: panel turns to wreck + killfeed line. **No implosion sound anywhere** (`fail_screen.gd`, `event_banner.gd` play no audio). **No one-shot flash on a rival's implosion** |
| 4 | Low-effects toggle keeps the game smooth on a weaker PC (AV-05) | **PARTIAL** | Toggle: `Settings.low_effects` (Settings > Display), contract enforced by `tests/test_effect_settings.gd`; effect table 02.2-UI-SPEC section 11. Measured only on discrete GPUs: solo Full p95 2.53 ms / Low 1.29 ms (RX 6600 XT, 02.2-PERF.md); versus Full p95 **4.18-4.45 ms vs 4.35 gate (borderline, UAT item 14 pending)**, versus Low p95 4.08 ms (03-15-SUMMARY). The final 02.2 "plan 24" perf row is still PENDING. No weak-GPU number exists. The GPU has since changed to an RX 9070 XT, so old rows are not comparable |
| 5 | Friend downloads the Windows build and runs it without Godot (DIST-01) | **PARTIAL (functionally done)** | `export_presets.cfg`: `embed_pck=true`, x86_64, s3tc_bptc. `tools/dist.ps1` builds `build/dist/UNDERTOW-playtest-v0.7.0.zip` (468 MB with the pack), asserts the allow-list, unzips, and requires `BUNDLED_OK 20` + `AC_PACK_FOUND`. README covers the SmartScreen "More info > Run anyway" step and crash log path. **Gaps:** second-PC UAT still pending (03/04 HUMAN-UAT); `application/config/icon` unset (exe shows the Godot icon); default grey Godot boot splash; `application/file_version`/`product_version` empty; README is a long changelog with no short "requirements" block |

**Exe runtime dependencies [VERIFIED: string scan of build/UNDERTOW.exe]:** only Windows system DLLs (`msvcrt.dll`, `kernel32.dll`, `d3d11.dll`, `opengl32.dll`, `dxgi.dll`, …), no `vcruntime140.dll`/`msvcp140.dll`. **The game itself needs no VC++ Redistributable.** Only the Autocharter pack (Python/torch) may need one, and README v0.5.4 already says so.

## Standard Stack

All built in. **No new packages.**

### Core (Godot 4.7.2 built-ins, verified via `--dump-extension-api` on the local binary)
| API | Purpose | Notes |
|-----|---------|-------|
| `AudioEffectLowPassFilter` (inherits `AudioEffectFilter`: `cutoff_hz`, `resonance`, `gain`, `db`) | Hull-driven muffle on bus `Music` | [VERIFIED: extension_api 4.7.2] |
| `AudioServer.add_bus_effect / remove_bus_effect / get_bus_effect / set_bus_effect_enabled / get_time_to_next_mix / get_time_since_last_mix / get_output_latency` | Runtime effect management and ping scheduling | [VERIFIED: extension_api 4.7.2] |
| `AudioStreamPlayer.play(from_position)` | Starting a ping part-way into a lead-silence buffer | No scheduled/delayed play API exists in 4.7.2 [VERIFIED: no method containing "schedul" in extension_api] |
| `AudioStreamWAV` (16-bit PCM built in code) | Procedural SFX | Existing house pattern: `AudioSynth._wav16`, `make_tick`, `make_clunk`, `VersusSfx.make_ping` |
| `BeatClock.beats_between(t0, t1, tempo_map, time_sigs)` | Downbeat list (`bar: true` entries, time-sig aware, 7/8 safe) | Existing pure helper, `src/core/beat_clock.gd:43` |
| `FxLayer.request_shake()` | Board-only shake honouring Reduce motion, rate-limited | Existing, `src/ui/fx/fx_layer.gd:390` |
| `RenderingServer.get_video_adapter_name()` | Log the GPU in perf rows | `get_video_adapter_type()` returns **0 (OTHER) under Compatibility even on a discrete RX 9070 XT** [VERIFIED: local probe, opengl3 and opengl3_angle], so it cannot drive auto-detect |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Runtime-added LPF on `Music` | Static LPF in `default_bus_layout.tres` | The .tres gets rewritten by editor/headless resaves (it is dirty in git right now: the uid line and fft_size were rewritten), and a leftover enabled filter would muffle menu music and previews. Runtime add/remove is self-cleaning |
| Lead-silence ping scheduling | Pre-rendered "ping track" played alongside the song | Needs starting in the same mix as the pinned Conductor's `play()`, which cannot be edited; drift and seek on pause/resume make it worse |
| Procedural SFX | CC0 samples (freesound/OpenGameArt) | The procedural path matches D-27b and needs no licence/credit bookkeeping or asset size. CC0 stays a fallback if a sound tests badly |
| Full-screen CRT post-process (`hint_screen_texture`, curvature, chroma) | — | Rejected: blurs or warps notes (S-12 readability), adds a screen copy on weak GPUs, and AV-01 is already met |

**Installation:** none.

## Package Legitimacy Audit

No external packages are installed in this phase. Everything uses Godot built-ins and existing project code. slopcheck: not applicable.

## Architecture Patterns

### System Architecture Diagram

```
                 Conductor (PINNED, read-only) ──song_time(), output_latency(), audio_offset()
                         │
   chart.tempo_map/time_sigs ──► DownbeatScheduler (pure) ──next bar time Tb──► DiveAudio
                                                                               │  play(LEAD - r) on SFX bus
   score.hull_changed(value, delta) ─────────────────────────────────────────► │
                                    ├─► CreakDirector (pure, seeded RNG) ──► creak player (SFX)
                                    └─► MuffleCurve (pure) ─cutoff─► AudioEffectLowPassFilter on bus "Music"
                                                                     (added on enter, removed on exit)

   EventChannel.received (offline loopback / online host+client channels, unchanged)
        │  TORPEDO_LAUNCH(from==me) ─► launch SFX + socket flash + small board kick
        │  LANDED(to==me)          ─► FxLayer.request_shake(px, usec) + board impact flash + impact SFX
        │  IMPLODED(seat==me)      ─► implosion SFX + muffle slam (banner shake/vignette already exist)
        │  IMPLODED(seat!=me)      ─► distant implosion SFX + periscope one-shot flash
        ▼
   TorpedoJuice (view node, register_fx for visuals) ── FlashLimiter (≤3 flashes/s shared with EdgeFlash rule)

   Perf harness (tools/playtest) ── Full/Low p95 on dGPU ── Low p95/p99 on iGPU proxy (ANGLE + power-saving)
   dist.ps1 ── export (icon, splash, version) ── zip v0.8.0 ── unzip self-test (BUNDLED_OK, AC_PACK_FOUND)
```

### Recommended file layout (new files only)
```
src/audio/dive_audio.gd         # gameplay node: pings, creaks, muffle (owns players + bus effect lifetime)
src/audio/downbeat_scheduler.gd # RefCounted: next downbeat and the lead offset math (pure)
src/audio/hull_audio_curve.gd   # RefCounted: cutoff_for_hull(), creak_interval_for_hull(), creak_db_for_hull() (pure)
src/audio/audio_synth.gd        # EXTEND: make_sonar_ping, make_creak(seed), make_impact, make_launch, make_implosion(distant)
src/ui/versus/torpedo_juice.gd  # view node reacting to EventChannel; register_fx
src/core/frame_watch.gd         # RefCounted: slow-frame counter for the Low effects hint (pure)
tools/playtest/perf_weak.ps1    # iGPU proxy capture wrapper (sets/restores GPU preference, ANGLE driver)
tools/make_icon.gd              # generates res://assets/ui/undertow_icon.png (+ .ico if needed) from Palette
tests/test_downbeat_scheduler.gd, test_hull_audio_curve.gd, test_audio_synth_sfx.gd,
tests/test_dive_audio.gd, test_torpedo_juice.gd, test_frame_watch.gd
```

### Pattern 1: Downbeat pings via lead-silence offset (no scheduled-play API)
**What:** Each ping stream starts with `LEAD` seconds of silence (e.g. 0.15 s, more than the worst frame + one mix). Each frame, compute the next bar time `Tb` (from `BeatClock.beats_between(st, st + 1.0, tempo, time_sigs)` filtered to `bar == true`, cached per bar). Then compute where a sound started now will land on the music timeline:

`head = conductor.song_time() + conductor.output_latency() + conductor.audio_offset() + AudioServer.get_time_to_next_mix()`

This is the same lead formula the pinned Conductor uses for its own resume start (`conductor.gd:163`, `get_time_to_next_mix() + _latency_cache + audio_offset()`) [VERIFIED: codebase]. With `r = Tb - head`: when `0 <= r < LEAD`, call `player.play(LEAD - r)` so the ping's onset lands on the downbeat. When `r < -0.03` (a hitch), skip that bar. One ping per bar id.
**When:** song_time ≥ 0, conductor not paused, song not ended, not in calibration/drift harness, and the `sonar_pings` setting is on.
**Why:** `play()` starts at the next mix [ASSUMED: engine mixes new playbacks from the next mix chunk; consistent with the docs' warning that position only updates per mix]. The offset trick removes the up-to-one-mix quantisation. Even without it, the error is at most one mix (~10-20 ms), which is acceptable for an ambient cue. It must never be confused with the judgment tick.
**Example:**
```gdscript
# Source: pattern derived from conductor.gd:163 (house formula) + AudioServer API (4.7.2)
func tick(st: float, latency: float, offset: float, to_next_mix: float) -> float:
	# returns from_position to play now, or -1.0 when nothing is due
	var head := st + latency + offset + to_next_mix
	var r := _next_bar_t - head
	if r < -LATE_SKIP:
		_advance_bar(); return -1.0
	if r < LEAD:
		_advance_bar(); return clampf(LEAD - r, 0.0, LEAD)
	return -1.0
```

### Pattern 2: Hull-driven muffle on the Music bus (runtime-owned effect)
- On `DiveAudio._ready` (gameplay only): find bus `Music`, remove any stale effect named/typed `AudioEffectLowPassFilter` left over (idempotent), `add_bus_effect(idx, lpf)`, and keep its index. On `_exit_tree`, remove it. Menus and Song Select previews are then never muffled, even after a crash-free scene change mid-song.
- Mapping (pure, tested): hull ≥ 75 → effect disabled (`set_bus_effect_enabled(false)`). Below 75: log-interpolate the cutoff from 20 000 Hz at 75 to a **1 500 Hz floor** at 0. Floor rationale: kick and snare bodies stay audible, so the song still carries the beat [ASSUMED: perceptual; tune in UAT]. Use `FILTER_12DB` and resonance 0.5 (default).
- Smoothing: one-pole toward the target, tau 0.25 s, per frame in `_process`. Hull changes are step events, so this avoids zipper noise.
- Wreck/implosion (versus): slam to the floor over 300 ms and hold. Solo fail: the song stops anyway.
- Hit SFX (`SfxPool`, SFX bus) are **not** filtered, so judgment feedback stays crisp.
- Effects on a bus add no meaningful delay. An IIR biquad has no buffering, so judgment and `get_output_latency()` are unaffected [ASSUMED: biquad group delay < 1 ms in the passband].

### Pattern 3: Procedural hull creaks
- Synthesis (`AudioSynth.make_creak(seed)`): a stick-slip impulse train (impulse rate wandering 25-70 Hz with jitter, a slow pitch glide) through two resonators (~350 Hz and ~900 Hz, decaying sines excited per impulse) under a 0.5-1.2 s swell/decay envelope, plus a little low noise. Pre-render 4 deterministic variants at gameplay load (during the goggles intro), never mid-song [ASSUMED: classic stick-slip creak model from procedural sound-design practice].
- Director (pure, seeded `RandomNumberGenerator`): (a) on `hull_changed` with `delta < 0` and hull < 70, play with probability rising to 1.0 at hull ≤ 30, with a 0.8 s cooldown; (b) ambient creaks while hull < 60, mean interval lerped from 12 s (hull 60) to 3 s (hull 10), volume −24 → −12 dB, pitch_scale 0.85-1.15.
- One combined setting "Hull sounds" (creaks + muffle), default ON.

### Pattern 4: Event-driven torpedo juice (view-only)
- Subscribe to the same `EventChannel` (`channel.received`) that `VersusSfx`, `EdgeFlash`, `PeriscopePanel` and `EventBanner` already use. Read fields defensively (`int(e.get("to", -1))`). Add no new events or fields; online handshake and protocol are unchanged.
- Extend `FxLayer.request_shake(px := SHAKE_PX, usec := SHAKE_USEC) -> bool` with defaults, so Miss behaviour is byte-for-byte the same. Impact uses 10 px / 160 ms. Reduce motion returns false as today. The board shakes, not the HUD.
- Visual parts register with `UiKit.register_fx` and implement `apply_effect_settings()` / `effect_counts()`. **Audio-only parts must not register:** `test_effect_settings` requires every registered node to change counts under Low effects (EdgeFlash documents the same exclusion).
- Photosensitivity: share the "≤ 3 flashes per second" rule (03-UI-SPEC 11.6) with one small limiter. An impact flash coinciding with the EdgeFlash arrival pulse counts as one.

### Pattern 5: Weak-PC measurement and Low effects hint
- Re-baseline on the current dGPU (RX 9070 XT): `run_all.ps1 -Scenarios perf` and `-Scenarios versus`.
- iGPU proxy [ASSUMED, verify by the logged "Using Device" line]: register `HKCU\Software\Microsoft\DirectX\UserGpuPreferences\<abs path to Godot console exe>` = `GpuPreference=1;` (power saving), run the harness with `--rendering-driver opengl3_angle` (ANGLE on D3D11 respects the Windows GPU preference; plain WGL OpenGL does not reliably), confirm the log shows "AMD Radeon(TM) Graphics", then **delete the registry value**. If the log still shows the 9070 XT, record the proxy as UNAVAILABLE and rely on the friend-PC UAT. Godot's `--gpu-index` does not apply to Compatibility [CITED: docs.godotengine.org command_line_tutorial: "only available on the Forward+/Mobile renderers"].
- The ANGLE path itself matters: Godot 4.7.2 forces ANGLE on old Intel HD / Radeon HD / R-series GPUs by default (`rendering/gl_compatibility/force_angle_on_devices`, `fallback_to_angle = true`) [VERIFIED: local ProjectSettings probe], so friends with old laptops run exactly that path.
- In-game hint (pure `FrameWatch`): during play (after the first 2 s, excluding pause), count frames whose delta exceeds 1.5 × the display refresh interval (`DisplayServer.screen_get_refresh_rate()`, fall back to 60). If more than 3 % of frames are late and Low effects is off, Results shows one line, "Frames dropped. Turn on Low effects?", with a button that toggles it and saves.

### Pattern 6: Exe polish (export-time only)
- `application/config/icon` → a generated `res://assets/ui/undertow_icon.png` (256 px, Palette colours). Godot converts the project icon for the Windows export [CITED: docs.godotengine.org exporting_for_windows]. Set `application/modify_resources=true` in the preset so icon and version info are written into the exe [ASSUMED: needed for the PE resource edit; verify with Explorer > Properties > Details on the built exe].
- `application/boot_splash/bg_color` = ABYSS_900 (#03060D); `show_image=false` or the UNDERTOW wordmark (defaults today: grey 0.14 with the Godot image [VERIFIED: probe]).
- `dist.ps1` writes `application/file_version` / `product_version` = `<config/version>.0` (e.g. `0.8.0.0`) into a temp copy of the preset, or passes it through the preset before export.
- README: a 10-line "START HERE" block at the top covering Windows 10/11 64-bit, a GPU with OpenGL 3.3 or Direct3D 11, no Godot and no installer needed, the SmartScreen step, "keep the folder together", and where logs are. The changelog moves below it.

### Anti-Patterns to Avoid
- **Editing any pinned timing file**, including "just reading a new signal" by adding one. Use the existing public API only (`song_time()`, `output_latency()`, `audio_offset()`, `is_paused()`, `paused`/`resumed` signals).
- **Muffling the SFX bus or Master:** it hides hit feedback. Filter `Music` only.
- **Leaving the LPF on `Music` after gameplay:** menu music and previews (Preview → Music) would stay muffled.
- **Generating WAVs mid-song:** GDScript sample loops cost tens of ms (frame hitch). Build at load and cache statically.
- **Changing `use_custom_user_dir` / the user data path:** friends would lose settings, calibration, scores and songs (README documents `%APPDATA%\Godot\app_userdata\UNDERTOW`).
- **Code signing / publishing:** no release publishing (user rule). Signing buys no SmartScreen reputation for a new file (below).
- **Using `get_video_adapter_type()` for auto Low effects:** it returns OTHER under Compatibility.
- **Full-screen screen-texture CRT pass:** readability and weak-GPU cost.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Muffle filter | Custom DSP in an `AudioStreamGenerator` | `AudioEffectLowPassFilter` on the bus | Built in, runs on the audio thread |
| Downbeat list with tempo/time-sig changes | New bar math | `BeatClock.beats_between(..., time_sigs)` | Already handles 7/8 and tempo changes; the sweep already uses the same bar phase (`highway.gd:1028-1047`), so ping and sweep agree |
| Board shake | A new shake node | `FxLayer.request_shake` with optional params | Already Reduce-motion aware, rate-limited, restores the board position |
| Event plumbing | New signals/RPCs | `EventChannel.received` | Same path offline, host and client |
| Pooled SFX players | New pool class | Copy the `VersusSfx` / `SfxPool` round-robin pattern | Proven headless-safe |
| Version string | Hard-coded | `project.godot config/version` (dist.ps1 already reads it) | Zip name, in-game VERSION and handshake never drift |

## Common Pitfalls

### Pitfall 1: Ping drift or double pings around pause/resume and seeks
**What goes wrong:** The ping fires twice for a bar, or fires during the resume countdown. **Why:** Song time is held or jumps. **Avoid:** Track the bar index, not time. Reset the scheduler on `conductor.paused`/`resumed` and suppress while `conductor.is_paused()` or `song_time() < 0`. **Warning sign:** The test with a simulated pause shows more pings than bars.

### Pitfall 2: Muffle leaks into menus
**Avoid:** Remove the effect in `_exit_tree`, add idempotently, and test "after Gameplay is freed, bus Music has 0 LPF effects". Also cover the Retry / F4-restart path (scene reload).

### Pitfall 3: The effect contract test fails on audio nodes
**Avoid:** Do not `register_fx` audio-only nodes (see EdgeFlash header comment).

### Pitfall 4: Photosensitivity regressions
**Avoid:** Use a shared limiter, and test that a burst of 5 LANDED/IMPLODED events in 1 s yields ≤ 3 flashes.

### Pitfall 5: Perf numbers not comparable
**Why:** The GPU changed (6600 XT → 9070 XT), and harness noise is ±0.15 ms. **Avoid:** Re-baseline before and after in the same session, log the GPU name, and use p95 over the 30 s dense window (existing method).

### Pitfall 6: Bus layout churn
**What:** `default_bus_layout.tres` is currently dirty: an editor/headless resave rewrote the header uid and dropped `fft_size = 2`. **Avoid:** Phase 5 does not need to edit it (runtime effect). Do not commit incidental resaves with feature work.

### Pitfall 7: Juice in online play double-fires
**Why:** Clients get the event from the host channel. A local optimistic launch could fire juice before the echoed event. **Avoid:** React to channel events only (as VersusSfx does), and de-dupe by torpedo id like `VersusSfx._pinged_ids`.

### Pitfall 8: Version bump breaks mixed lobbies
v0.8.0 refuses v0.7.0 peers (D-21 handshake). This is intended; README must say everyone updates.

## Code Examples

### Runtime LPF lifetime
```gdscript
# Source: AudioServer API (Godot 4.7.2 extension_api), house bus lookup pattern (settings.gd _apply_bus)
var _bus := -1
var _fx_idx := -1
var _lpf := AudioEffectLowPassFilter.new()

func _ready() -> void:
	_bus = AudioServer.get_bus_index(&"Music")
	if _bus < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(_bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(_bus, i) is AudioEffectLowPassFilter:
			AudioServer.remove_bus_effect(_bus, i)
	_lpf.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_bus, _lpf)
	_fx_idx = AudioServer.get_bus_effect_count(_bus) - 1
	AudioServer.set_bus_effect_enabled(_bus, _fx_idx, false)

func _exit_tree() -> void:
	if _bus >= 0 and _fx_idx >= 0 and _fx_idx < AudioServer.get_bus_effect_count(_bus):
		AudioServer.remove_bus_effect(_bus, _fx_idx)
```

### Pure hull curve
```gdscript
static func cutoff_for_hull(hull: float) -> float:  # 0..100
	if hull >= 75.0:
		return 20000.0
	var k := clampf(hull / 75.0, 0.0, 1.0)
	return exp(lerpf(log(1500.0), log(20000.0), k))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| EV code-signing cert gives instant SmartScreen trust | EV no longer bypasses; every new file builds reputation; Azure Artifact (Trusted) Signing ≈ OV | 2024 | Signing a friends-only build buys little; keep the "More info > Run anyway" README step [CITED: learn.microsoft.com smartscreen-reputation; todesktop.com PSA] |
| rcedit for exe icons (Godot 3/early 4) | Godot converts the project icon at export | Godot 4.x | No external tool needed |
| `AudioStreamPlayer` scheduled start | Still none in 4.7.2 | — | Use the lead-silence offset trick |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `play()` begins at the next mix, so `get_time_to_next_mix()` belongs in the lead | Pattern 1 | Pings ±1 mix (~10-20 ms) off; harmless for an ambient cue. Verify by recording loopback once |
| A2 | Bus LPF adds no meaningful latency | Pattern 2 | Judgment unaffected anyway (judge uses the clock, not the filtered output); audible lag would be < 1 ms |
| A3 | 1 500 Hz floor keeps the beat audible | Pattern 2 | Tune in UAT; constant in the pure curve |
| A4 | Stick-slip impulse + resonator model sounds like a hull creak | Pattern 3 | Re-tune or swap in a credited CC0 sample |
| A5 | ANGLE + `UserGpuPreferences GpuPreference=1` puts Godot on the iGPU | Pattern 5 | Proxy unavailable; fall back to friend-PC UAT (recorded UNMEASURED, never PASS) |
| A6 | `modify_resources=true` is needed to stamp icon/version into the exe | Pattern 6 | Icon missing; check Properties > Details, flip the option |
| A7 | 2-CU 9800X3D iGPU is weaker than typical friend iGPUs (Iris Xe / 680M) | D-07 | Gate may be too harsh; D-07 treats Full on the proxy as informative only |

## Open Questions

1. **Ping loudness and frequency.** Every bar may feel busy on fast songs. Default: every bar at about −20 dB with a setting toggle. UAT question: "keep / every 2nd bar / off by default?"
2. **Versus Full p95 on the new GPU.** It may now pass comfortably. If it does, record it and still do the cheap VersusHud redraw-on-change fix only if the measurement shows it is > 0.5 ms.
3. **Second-PC UAT** is a human item carried since Phase 3. Phase 5 cannot close DIST-01 fully without it; the plan ends with a HUMAN-UAT row.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Godot console | tests, harness, export | ✓ | 4.7.2.stable.official (`C:\Users\User\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, `GODOT_BIN`) | — |
| Export templates | DIST-01 | ✓ | `%APPDATA%\Godot\export_templates\4.7.2.stable` | — |
| Discrete GPU | Full perf gate | ✓ | AMD Radeon RX 9070 XT (OpenGL 3.3 core; ANGLE D3D11 also works) [VERIFIED: probe] | — |
| Integrated GPU | Weak-PC proxy | ✓ (present) | AMD Radeon(TM) Graphics (Ryzen 7 9800X3D) | Friend-PC UAT if routing fails |
| Python launcher `py` | ad-hoc scripts only | ✓ | — | — |
| `gh` CLI | not needed (no publishing) | ✗ | — | — |
| Second Windows PC | DIST-01 final UAT | human | — | none (human_needed) |

## Validation Architecture

(`workflow.nyquist_validation` is false in config; included because the orchestrator asked for it.)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | gdUnit4 6.2.1 (`addons/gdUnit4`) + playtest harness (`tools/playtest`) |
| Quick run | `powershell -NoProfile -File tools/run_tests.ps1 -Path res://tests/test_<name>.gd` |
| Full suite | `powershell -NoProfile -File tools/run_tests.ps1` |
| Timing gate | `powershell -NoProfile -File tools/check_timing_gate.ps1` (must print TIMING GATE OK in every plan) |
| Harness | `powershell -NoProfile -File tools/playtest/run_all.ps1 -Scenarios perf,versus,visual` |

### Requirement → Test Map
| Req | Behavior | Type | Command / file | Exists? |
|-----|----------|------|----------------|---------|
| AV-01/02 | Shader + arena still applied/pulsing; Low/Reduce contract | unit + shots | `test_effect_settings.gd`, `test_arena.gd`, harness `visual` | ✅ |
| AV-03 | Downbeat schedule: one ping per bar, 4/4 + 7/8 + tempo change, none while paused / t<0, lead offset math | unit | `tests/test_downbeat_scheduler.gd` | ❌ Wave 0 |
| AV-03 | cutoff_for_hull monotonic, 20 kHz ≥ 75, floor 1 500 at 0; creak interval/db curves | unit | `tests/test_hull_audio_curve.gd` | ❌ |
| AV-03 | DiveAudio adds exactly one LPF to Music, follows hull, removes it on exit; settings toggles respected | integration (headless dummy audio) | `tests/test_dive_audio.gd` | ❌ |
| AV-03 | New AudioSynth streams: length, peak ≤ 0.9, non-silent, deterministic per seed, lead silence present | unit | `tests/test_audio_synth_sfx.gd` | ❌ |
| AV-04 | LANDED→shake (not under Reduce motion) + flash + SFX; launch from me→SFX + flash; IMPLODED me/rival; dedupe by id; ≤3 flashes/s; Miss shake unchanged | unit/integration | `tests/test_torpedo_juice.gd`, existing `test_fx_layer.gd` | ❌ / ✅ |
| AV-05 | FrameWatch threshold logic; Results hint toggles Low effects | unit | `tests/test_frame_watch.gd` | ❌ |
| AV-05 | Full p95 ≤ 4.35 ms (dGPU) solo + versus; Low p95 ≤ 16.7 ms and p99 ≤ 20 ms on iGPU proxy (or UNMEASURED) | harness | `run_all.ps1 -Scenarios perf,versus`; `tools/playtest/perf_weak.ps1` | partial |
| DIST-01 | Zip allow-list, unzip self-test BUNDLED_OK 20 + AC_PACK_FOUND, version = config/version, icon present | build script | `tools/dist.ps1` | ✅ (extend) |
| DIST-01 | Runs on a second PC without Godot | manual | 05-HUMAN-UAT.md | human |

### Sampling Rate
- Per task: the touched test file + `check_timing_gate.ps1`.
- Per wave: full gdUnit suite.
- Phase gate: full suite green, harness perf/versus/visual, dist.ps1 self-test, HUMAN-UAT sheet written.

### Wave 0 Gaps
The six new test files listed above. No framework install is needed.

## Security Domain

ASVS L1, block on high. This phase adds no network surface, file parsing or credentials.

| ASVS Category | Applies | Control |
|---------------|---------|---------|
| V2/V3/V4 | no | — |
| V5 Input Validation | yes (event dictionaries already validated by Phase 4 codec) | Read event fields with typed defaults (`int(e.get("to", -1))`); ignore unknown seats |
| V6 Cryptography | no | (dist SHA-256 checks of pack parts already exist) |
| V14 Config / build | yes | Zip allow-list assertion stays; no secrets in export; `export_filter` keeps `tools/`, `tests/`, `build/` out |

| Threat | STRIDE | Mitigation |
|--------|--------|------------|
| Malicious peer floods LANDED/IMPLODED events to strobe the screen | DoS / safety | Flash limiter ≤ 3/s, shake rate limit (existing 150 ms gap), SFX dedupe by id; host already throttles (WR-08) |
| Tampered friend zip | Tampering | Distribute privately; README notes the SHA-256 printed by dist.ps1 |

## Recommended Decisions (orchestrator defaults)

- **D-01 (AV-01/AV-02 closed as DONE):** Do not add a full-screen CRT post-process. The locked 02.2 palette (`Palette.SONAR` cyan-teal phosphor) satisfies "phosphor-green sonar CRT"; do not recolour. Phase 5 only re-captures screenshots for verification and adds one UAT question on CRT strength.
- **D-02 (downbeat pings):** On every bar start from `BeatClock.beats_between` (bar entries), song_time ≥ 0, in solo, Solo Dive, versus and online. SFX bus, about −20 dB, a timbre distinct from the incoming-torpedo ping (soft low "pong" ~700→520 Hz with two quiet echo taps). Schedule with the lead-silence offset (Pattern 1). New setting Settings > Audio > "Sonar pings", default ON. Off in Calibration and harness drift scenarios.
- **D-03 (muffle):** Add `AudioEffectLowPassFilter` at runtime to bus `Music` while Gameplay lives, and remove it on exit. Disabled at hull ≥ 75; log curve down to a 1 500 Hz floor at hull 0; 12 dB/oct; 0.25 s smoothing; slam to the floor over 300 ms on local implosion (versus wreck). Never filter SFX/Master.
- **D-04 (creaks):** Procedural stick-slip creaks, 4 seeded variants pre-rendered at load. Triggered on damage below 70 hull plus ambient creaks below 60 hull, with intervals and volume per Pattern 3. One setting "Hull sounds" (creaks + muffle), default ON.
- **D-05 (torpedo juice):** LANDED on me: board shake 10 px / 160 ms via extended `FxLayer.request_shake(px, usec)` (defaults unchanged), WARNING_RED board flash 120 ms, impact boom SFX. My launch: thump+whoosh SFX, SONAR_PALE socket ring flash, 3 px board kick (none under Reduce motion). My implosion: implosion SFX + D-03 slam (existing banner shake and vignette kept); the solo FailScreen plays the same implosion SFX. Rival implosion: distant implosion SFX (−14 dB) + one-shot red periscope panel flash 300 ms. Shared ≤ 3 flashes/s limiter. No protocol change.
- **D-06 (Low effects on weak PCs):** Keep the existing Low effects contract. Add `FrameWatch` and a one-line Results hint with a one-press "Turn on Low effects" when > 3 % of play frames exceed 1.5 × the refresh interval. No adapter-based auto-enable (adapter type is OTHER under Compatibility).
- **D-07 (weak-PC gate):** Re-baseline on the RX 9070 XT. Weak proxy = the Ryzen iGPU via `--rendering-driver opengl3_angle` + Windows power-saving GPU preference, set and then removed by `perf_weak.ps1`. Gate on the proxy: **Low p95 ≤ 16.7 ms and p99 ≤ 20 ms at 1080p**, solo dense passage and versus with 3 bots. Full on the proxy is informative only. If the proxy cannot be routed, record UNMEASURED (never PASS) and carry it to the friend-PC UAT.
- **D-08 (versus Full gate):** Re-measure first. If Full p95 > 4.35 ms on the dev dGPU, make VersusHud children redraw only on state change (Phase 3 attributed about 1 ms to VersusHud per-frame work), then apply the 02.2 UI-SPEC 12 cut order. Log every step in `05-PERF.md`.
- **D-09 (distribution):** Keep the single-file debug export (F3 overlay and logs are part of the tester flow). No code signing (EV no longer buys SmartScreen trust; the cost is unjustified for a friend build). No VC++ redist for the game (verified). Set the app icon (generated, Palette colours), boot splash bg ABYSS_900 without the Godot image, and exe file/product version from `config/version`. README gets a short START HERE / requirements block. Do not change the user data dir. **Build the zip locally only; no upload and no GitHub release** (user rule).
- **D-10 (version):** Bump `config/version` to **0.8.0** in the final build plan. README "WHAT'S NEW IN v0.8.0" + checklist section (pings, creaks, muffle, impacts, Low effects hint). All friends must update for online play.
- **D-11:** Every plan runs `tools/check_timing_gate.ps1`. Nothing in Phase 5 edits the five pinned files or `default_bus_layout.tres`.
- **D-12:** All new SFX are procedural in `AudioSynth`. If any CC0 sample is ever substituted, add a "SOUND CREDITS" README block.
- **D-13:** UI hint: reuse the 02.2 / 03 UI-SPEC tokens and effect tables. A light 05-UI-SPEC addendum (effect-mode rows for the new juice: Full / Low / Reduce motion) is enough if the UI phase gate requires one.

## Suggested Plan / Wave Breakdown (gaps only)

| Wave | Plan | Scope | Reqs |
|------|------|-------|------|
| 1 | 05-01 Procedural SFX bank | `AudioSynth`: `make_sonar_ping` (with lead silence), `make_creak(seed)`, `make_impact`, `make_launch`, `make_implosion(distant)`; static cache built at load; `test_audio_synth_sfx.gd` | AV-03, AV-04 |
| 1 | 05-02 Perf re-baseline + weak-GPU proxy tooling | `tools/playtest/perf_weak.ps1` (ANGLE + GPU preference set/restore, GPU-name assertion); re-run perf/versus on the 9070 XT; create `05-PERF.md` with baseline rows. No src edits | AV-05 |
| 1 | 05-03 Exe polish | `tools/make_icon.gd` → icon asset; `project.godot` icon + boot splash; preset `modify_resources`; `dist.ps1` version stamping + icon check; README START HERE block | DIST-01 |
| 2 | 05-04 DiveAudio | `downbeat_scheduler.gd`, `hull_audio_curve.gd`, `dive_audio.gd` wired in Gameplay (solo + versus + online), Settings keys `sonar_pings`, `hull_sounds` + two Audio toggle rows; tests | AV-03 |
| 2 | 05-05 TorpedoJuice | `torpedo_juice.gd` on the EventChannel; `FxLayer.request_shake(px, usec)` defaults; socket/panel flashes; FailScreen implosion SFX; flash limiter; effect contract; tests | AV-04 |
| 3 | 05-06 Weak-PC pass | `frame_watch.gd` + Results hint; VersusHud redraw-on-change if D-08 triggers; measure gates (D-07/D-08), log to `05-PERF.md` | AV-05 |
| 3 | 05-07 v0.8.0 build + UAT | version bump, README WHAT'S NEW + checklist, `dist.ps1` → local zip + self-test (no publish), harness shots, `05-HUMAN-UAT.md` (friend PC, ping loudness, muffle floor, creak feel, CRT strength, weak laptop) | DIST-01, all |

Plans 05-04 and 05-05 both touch `gameplay.gd` wiring. If they run in parallel, keep the wiring in separate small helper calls, or serialize them.

## Sources

### Primary (HIGH confidence)
- Local Godot 4.7.2 binary: `--dump-extension-api` (AudioStreamPlayer methods, AudioEffectFilter, AudioServer, RenderingServer adapter methods; no scheduled play API)
- Local ProjectSettings probe: gl_compatibility driver/fallback/force_angle defaults, boot splash defaults, vsync/max_fps
- Local adapter probe: `get_video_adapter_type()` = 0 on opengl3 and opengl3_angle
- String scan of `build/UNDERTOW.exe` imports (no vcruntime140)
- Codebase: files cited in the audit table; `.planning` 02.2-UI-SPEC sections 11-12, 02.2-PERF.md, 03-UI-SPEC 6.3-6.5 / 11-12, 03-15-SUMMARY, 03-VERIFICATION
- [Godot command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) (`--gpu-index` Forward+/Mobile only, `--rendering-driver`, `--frame-delay`)
- [Godot exporting for Windows](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html) (project icon conversion, signing, embed PCK limit)

### Secondary (MEDIUM)
- [Microsoft: SmartScreen reputation](https://learn.microsoft.com/et-ee/windows/apps/package-and-deploy/smartscreen-reputation), [Microsoft: code signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options), [ToDesktop PSA: EV certs no longer grant immediate reputation](https://www.todesktop.com/blog/posts/windows-apps-psa-ev-certs-do-not-grant-immediate-reputation-anymore)

### Tertiary (LOW, flagged as ASSUMED)
- Stick-slip creak synthesis model, ANGLE GPU-preference routing, play()-at-next-mix behaviour (see Assumptions Log)

## Metadata

**Confidence breakdown:**
- Audit: HIGH (direct file evidence and greps)
- Standard stack: HIGH (verified against the 4.7.2 binary)
- Architecture/patterns: MEDIUM-HIGH (house patterns reused; scheduling nuance assumed)
- Weak-PC method: MEDIUM (proxy routing to verify at execution)
- Pitfalls: HIGH (most come from the repo's own history)

**Research date:** 2026-10-20
**Valid until:** 2026-11-20 (engine pinned; stable)
