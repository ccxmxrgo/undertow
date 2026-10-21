---
phase: 05-polish-packaging
plan: 05
subsystem: versus-ui-juice
tags: [juice, sfx, shake, photosensitivity, versus, AV-04]
requires: [05-01 AudioSynth.sfx_bank()]
provides: [TorpedoJuice, FlashLimiter, "FxLayer.request_shake(px, usec)", PeriscopePanel.flash_implosion, FailScreen implosion sound]
affects: [src/ui/versus/versus_controller.gd bind_views, src/ui/fx/fx_layer.gd]
tech-stack:
  added: []
  patterns: [event-driven view on EventChannel, shared FlashLimiter on event song time, bounded id dedupe]
key-files:
  created: [src/ui/versus/torpedo_juice.gd, src/ui/fx/flash_limiter.gd, tests/test_torpedo_juice.gd]
  modified: [src/ui/fx/fx_layer.gd, src/ui/versus/versus_controller.gd, src/ui/versus/periscope_panel.gd, src/ui/fail_screen.gd, tests/test_fx_layer.gd, tests/test_effect_settings.gd]
decisions:
  - "request_shake(px = SHAKE_PX, usec = SHAKE_USEC): the 150 ms gap is shared by every caller, so a Miss shake and a torpedo shake never stack"
  - "One FlashLimiter per TorpedoJuice covers impact bands, socket ring and rival panel flashes; sounds are not rate capped (only de-duplicated)"
  - "Distant implosion plays at 0 dB on the player: the -14 dB is already baked into sfx_bank()[implosion_distant] by 05-01"
  - "Ids are deduped separately for launches and landings (the same torpedo id appears in both), implosions per seat"
metrics:
  completed: 2026-10-21
  tasks: 2
  files: 9
---

# Phase 5 Plan 05: TorpedoJuice Summary

Torpedoes now feel physical. They are driven only by existing EventChannel events, so offline and online behave the same and nothing in the protocol changed:
- An impact gives a boom, a 10 px / 160 ms board shake and a WARNING_RED edge flash.
- Your own launch gives a thump and whoosh, a 3 px kick and a SONAR_PALE socket ring.
- An implosion plays the near or distant implosion sound, and a rival's implosion flashes their periscope panel red.
- A solo fail now plays the implosion sound on the FailScreen.
- Every flash goes through a FlashLimiter: at most 3 per second, at least 1/3 s apart.

## Effect table as built

| Juice | Full | Low effects | Reduce motion |
|---|---|---|---|
| Impact board shake, 10 px / 160 ms (`FxLayer.request_shake(10.0, 160000)`) | on | on | off |
| Impact edge flash: WARNING_RED 96 px gradient bands (left, right, top), alpha 0.35 to 0 over 120 ms | on | on | on (opacity only) |
| Launch socket ring: SONAR_PALE, 2 px wide, 48 points, radius 40 to 72, alpha 0.8 to 0 over 200 ms | on | off | fade only (radius fixed at 56) |
| Launch board kick, 3 px / 80 ms | on | on | off |
| Rival implosion panel flash: WARNING_RED edge, 300 ms (`PeriscopePanel.flash_implosion`) | on | on | on |
| Sounds: impact, launch, implosion, implosion_distant (SFX bus, pool of 4) | on | on | on |

`effect_counts()` returns `{launch_ring, kick, impact_shake, edge_flash}`. It is registered via `UiKit.register_fx` and listed in `test_effect_settings` EXPECTED["versus"].

**Keep-out bands** (`keepout_shapes()`, global space):
- left: (0, 0, 96, 1080)
- right: (1824, 0, 96, 1080)
- top: (0, 0, 1920, 96)

`test_layout_keepout` passes with these bands, so no clipping was needed.

**Wiring:** `VersusController.bind_views` creates `TorpedoJuice` under VersusHud right after EdgeFlash and binds it to `(channel, local_seat, gp.fx_layer, reward_socket, periscope_column)`.
- gameplay.gd is untouched.
- Nothing changed under src/net or src/versus.
- No new GameEvent type or field was added.

## Tasks / Commits

| Task | Commit | Message |
|---|---|---|
| 1 RED | f4f3595 | test(05-05): failing tests for parameterised shake and FlashLimiter |
| 1 GREEN | 5ad778d | feat(05-05): parameterised board shake (Miss unchanged) and FlashLimiter |
| 2 RED | c4c9ccd | test(05-05): failing TorpedoJuice tests |
| 2 GREEN | d86085b | feat(05-05): torpedo impact/launch/implosion juice (event-driven, no protocol change) |

## Tests

- **test_torpedo_juice:** 21 tests (3 FlashLimiter, 17 unit, 1 bind_views integration).
- **test_fx_layer:** 25 tests (4 new). The existing Miss-shake tests were not modified and still pass.
- **Re-run green:**
  - Effects and layout: test_effect_settings 14, test_layout_keepout 8, test_color_literals 7, test_periscope_panel 22, test_versus_alerts 27.
  - Versus and determinism: test_versus_gameplay 12, test_versus_controller_determinism 5, test_match_determinism 4.
  - Online: test_online_controller 9, test_online_gameplay 18, test_online_views 16.
  - Other modes: test_solo_duel 14, test_training_drone 7.
  - FailScreen callers: test_gamepad_menus 17, test_gamepad_settings 19, test_overlay_layout 32, test_review_fixes 15.
- After rebasing onto 05-04, these were re-run and are green: test_torpedo_juice, test_effect_settings, test_versus_gameplay, test_versus_controller_determinism and test_layout_keepout.
- `tools/check_timing_gate.ps1`: TIMING GATE OK.

## Deviations from Plan

- Task 2 implementation was written before its test file was committed, so the "RED" commit c4c9ccd was not separately run red. Task 1 RED was confirmed red (parse error: `request_shake()` takes no args, and FlashLimiter was undeclared).
- I added test helpers to TorpedoJuice: `sfx_count(key)`, `impact_active()`, `ring_radius()`, `ring_alpha()`, `band_rects()`. The plan only listed counters.
- `request_shake` falls back to the default amplitude for a non-finite `px` and clamps `usec` to at least 1 (Rule 2, input safety).

## Notes

- test_review_fixes `test_pause_during_preroll_never_seeks_negative` failed once while other agents were running Godot in parallel. It is a wall-clock Conductor test that does not touch these files, and it passed 15/15 on re-run.
- FailScreen gets its stream from `AudioSynth.sfx_bank()`. In solo, the cache is already warm from 05-04 DiveAudio at load. In versus, TorpedoJuice warms it in `_ready` during bind_views.

## Self-Check: PASSED

- All created files exist.
- Commits f4f3595, 5ad778d, c4c9ccd and d86085b are on origin/main.
