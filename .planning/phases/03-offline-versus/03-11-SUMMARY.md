---
phase: 03-offline-versus
plan: 11
subsystem: versus-hud
tags: [telegraph, alert, edge-flash, event-banner, sfx, photosensitivity]
requires: ["03-02", "03-03"]
provides:
  - IncomingAlert (alert slot 640,120,640,72)
  - EdgeFlash (screen-edge threat flash, keepout_shapes)
  - EventBanner (duel / last hull / implosion, priority over SectionBanner)
  - VersusSfx (synthesised sonar ping + collision clunk)
  - SectionBanner.suppressed hook
affects: [03-14 gameplay wiring, test_layout_keepout, test_effect_settings]
tech-stack:
  added: []
  patterns: [SectionBanner observe(t)/step(dt) split, EventChannel.received listeners, procedural AudioStreamWAV]
key-files:
  created:
    - src/ui/versus/incoming_alert.gd
    - src/ui/versus/edge_flash.gd
    - src/ui/versus/event_banner.gd
    - src/audio/versus_sfx.gd
    - tests/test_versus_alerts.gd
  modified:
    - src/ui/gauges/section_banner.gd
decisions:
  - "VersusSfx.ping(id) is de-duplicated per torpedo id, so IncomingAlert (key link: ping on launch) and VersusSfx.bind can both request it and it plays once"
  - "EdgeFlash cap: a pulse is skipped if within 333 ms of an accepted pulse or if it would be the 4th in any 1 s window; launch and arrival pulses each go through the cap (max 2 per torpedo)"
  - "EventBanner: a replaced banner (duel state, last standing) waits in a pending list and returns after the higher one fades; the duel slot keeps only its latest state; stale announce/live duels (song past end + 1 s) are dropped"
  - "SectionBanner.suppressed: hides at once; a section that started while suppressed shows when suppression ends if it is still in force; with suppressed false nothing changes"
  - "Duel captions 'SOLO DUEL' are REWARD_GOLD in every duel state (UI-SPEC 3.1 reserves gold for the Solo Duel banner caption)"
metrics:
  duration: "~50 min (with a usage-limit pause)"
  completed: 2026-10-15
  tasks: 2
  files: 6
---

# Phase 3 Plan 11: Incoming alert, edge flash, event banner and versus SFX Summary

This plan adds the telegraph cues for a threat aimed at the local seat: the IncomingAlert slot, the EdgeFlash strips (capped for photosensitivity) and a synthesised sonar ping. All three start on the TORPEDO_LAUNCH beat, at least one beat before arrival. It also adds the EventBanner (Solo Duel, Last Hull Standing, Implosion), which hides SectionBanner through a new `suppressed` hook, and a collision clunk that plays for everyone.

## What was built

- **IncomingAlert** (`src/ui/versus/incoming_alert.gd`)
  - States: INCOMING, ACTIVE, ENDED, plus the 1.2 s result states REFLECTED, ABSORBED and COLLISION, all per UI-SPEC 6.3.
  - The hint shows HIT RINGED NOTES PERFECT, CANNOT BE REFLECTED or DECOY WILL ABSORB. Decoy state is tracked from BUFF_APPLIED/BUFF_ENDED for DECOY_FLARE.
  - The ACTIVE hint is either "REFLECT k/n" or "{n} BARS LEFT" (singular for 1 bar). The bar count comes from the chart tempo map plus `MatchSim.bar_beats_at`.
  - The countdown ring and the duration line follow the song clock (`observe`). Fades, the 16 px slide and the 120 ms cross-fade follow `step(dt)`.
  - Getters for tests: `state()`, `caption_text()`, `hint_text()`, `headline_text()`, `first_visible_t()`, `ring_fraction()`.
  - Registers with `UiKit.register_fx`. `effect_counts()` returns `{slide, glow, burst_grow}`.
- **EdgeFlash** (`src/ui/versus/edge_flash.gd`)
  - Two 16 px WARNING_RED gradient strips.
  - Launch pulse rises 0 to 0.5 in 60 ms, then decays linearly to 0 at arrival. An arrival pulse of 0.3 decays over 300 ms.
  - Photosensitivity cap: at most 3 pulses per second, a 333 ms minimum gap, and at most 2 pulses per torpedo.
  - `alpha_at(t)` is a pure function of song time. `keepout_shapes()` returns the two strips.
  - It does not call `register_fx`; the plan and UI-SPEC 12 say it is on in every mode.
- **EventBanner** (`src/ui/versus/event_banner.gd`)
  - Full-screen canvas. The panel is a child Control at SectionBanner.RECT, so its fade does not touch the vignette.
  - Duel states: announce, live and result. Live shows "YOU p%" or "YOU --%", the leader among living rivals (from the `live_pct` Callable), and a progress line.
  - LAST HULL STANDING and IMPLOSION. Implosion adds an 8 px / 120 ms shake and a WARNING_RED 22% radial corner vignette that fades over 600 ms.
  - Priority: IMPLOSION > LAST HULL STANDING > SOLO DUEL.
  - Getters: `current_kind()`, `caption_text()`, `headline_text()`, `right_text()`. `effect_counts()` returns `{slide, shake, glow}`.
- **VersusSfx** (`src/audio/versus_sfx.gd`)
  - Synthesised ping: 1.1 to 1.7 kHz sweep with an echo, about 220 ms.
  - Synthesised collision: a 60 to 40 Hz thump plus filtered noise, about 320 ms.
  - Pooled AudioStreamPlayers on the SFX bus. No audio assets were added.
- **SectionBanner:** new `suppressed` property (setter `set_suppressed`), cited to 03-UI-SPEC 6.4.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 1c05a0e | IncomingAlert, EdgeFlash and VersusSfx + tests |
| 2 | 2fd06ce | EventBanner, SectionBanner.suppressed + tests |

## Verification

- `tests/test_versus_alerts.gd`: 27/27 pass.
- `tests/test_hud_gauges.gd`: 61/61 pass, including all existing SectionBanner tests. It first needed a `--import` so that 03-09's new `StatusChips` class would resolve.
- `tests/test_color_literals.gd`: 7/7 pass.
- `tools/check_timing_gate.ps1`: TIMING GATE OK.
- Full suite deferred to wave end (03-14/03-15) per the parallel-wave rule.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Both the alert and VersusSfx.bind would ping, so the ping played twice**
- **Found during:** Task 1 design.
- **Issue:** The plan has IncomingAlert ping on launch and also has `VersusSfx.bind` ping on TORPEDO_LAUNCH, which would play two pings per torpedo.
- **Fix:** `ping(id)` de-duplicates by torpedo id. A test asserts one ping with both paths bound.
- **Commit:** 1c05a0e

**2. [Rule 1 - Bug] EventBanner step(dt) crossed only one phase per call**
- **Found during:** Task 2 tests.
- **Issue:** A large dt left the banner in HOLD or OUT, so the next banner was queued instead of shown.
- **Fix:** `step()` loops over the IN, HOLD, OUT and IDLE transitions and carries the overshoot. SectionBanner itself was left unchanged.
- **Commit:** 2fd06ce

### Process note
Tasks were marked tdd="true". Tests and implementation went into one feat commit per task rather than separate test/feat commits. All behaviours in the plan are covered by tests.

## Notes for 03-14 (wiring)

- **IncomingAlert**
  - Call `bind(channel, local_seat, names, chart, cfg, sfx)`.
  - Every frame call `observe(conductor.song_time())`. `step(delta)` already runs from `_process`.
  - The first visible time is the TORPEDO_LAUNCH `launch_t`. For the harness lead check, use `arrive_t() - first_visible_t()`.
- **EdgeFlash**
  - Call `bind(channel, local_seat)`, then `observe(song_time)` every frame.
  - It is full-screen (`fill_rect`) and implements `keepout_shapes()`. Do not add it to the `test_effect_settings` EXPECTED list, because it is not FX-registered.
- **EventBanner**
  - Call `bind(channel, local_seat, names, cfg, Callable(match_sim, "duel_live"), hud_section_banner)`, then `observe(song_time)` every frame.
  - It sets `section_banner.suppressed` itself.
  - Add "EventBanner" and "IncomingAlert" to `test_effect_settings`. Reduce motion flips EventBanner `{slide: false, shake: false}` and IncomingAlert `{slide: false, burst_grow: false}`.
- **VersusSfx**
  - Add it as a child and call `bind(channel, local_seat)`. This binding is what plays the collision sound for everyone. The alert only pings.
  - It falls back to the Master bus if there is no SFX bus.
- **test_layout_keepout:** add IncomingAlert at (640,120,640,72), EventBanner at (640,200,640,72), and the two EdgeFlash strips.
- **Multiple threats:** the alert shows one threat at a time. A new launch at you replaces whatever it shows, and events for older ids are ignored.

## Known Stubs

None. The views are complete but not yet wired into gameplay, which is plan 03-14 by design.

## Threat Flags

None. No new network, file or auth surface. T-03-27 (flash cap) and T-03-28 (malformed fields: `.get()` defaults, clamped fractions, "?" for unknown seats) are mitigated and tested.

## Self-Check: PASSED

- All 6 key files exist on disk.
- Commits 1c05a0e and 2fd06ce are present in `git log`.
