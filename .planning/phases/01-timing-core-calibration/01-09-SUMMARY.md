---
phase: 01-timing-core-calibration
plan: 09
subsystem: calibration-device-awareness
status: complete
gap_closure: true
tags: [godot, gdscript, audio-device, calibration, gap-closure]
requires:
  - phase: 01-07
    provides: CalibrationWizard, Settings calibration section
provides:
  - AudioDeviceInfo (Godot-only snapshot and change signature)
  - Narrowed Bluetooth heuristic (D-17 refined)
  - Recalibration note, "Previously saved" caption, constrained wizard button widths
affects: [01-10]
key-files:
  created:
    - src/core/audio_device_info.gd
    - tools/audio_device_probe.gd
    - tests/test_audio_device_info.gd
  modified:
    - src/core/device_heuristics.gd
    - src/autoload/settings.gd
    - src/ui/calibration_wizard.gd
    - src/ui/settings_screen.gd
    - tests/test_bt_heuristic.gd
    - tests/test_settings.gd
    - tests/test_calibration_flow.gd
    - .planning/phases/01-timing-core-calibration/01-07-PLAN.md
    - .planning/phases/01-timing-core-calibration/01-UI-SPEC.md
requirements-completed: [CAL-01]
metrics:
  tasks: 2
  completed: 2026-10-07
---

# Phase 1 Plan 09: Device awareness gap closure Summary

Godot-API-only device snapshot (sorted device list + mix rate + latency in 5 ms buckets + endpoint count) drives change detection, with an honest "System default" readout and a recalibration reminder; Bluetooth markers narrowed; re-run shows absolute offset plus "Previously saved" caption; wizard buttons capped at 280-480 px.

## Commits
- e277df2: AudioDeviceInfo, probe, heuristic narrowing, tests
- 7456776: Settings/wizard/settings-screen wiring, tests, doc fixes

## Probe output (windowed, this PC, Godot 4.7.2, WASAPI)
```
output_device: 'Default'
device list: ["Default", "Realtek Digital Output (Realtek(R) Audio)", "1 - 24G4 (AMD High Definition Audio Device)", "Microphone (fifine Microphone) (Elgato Virtual Audio)", "Speakers (Razer BlackShark V2 Pro 2.4)", "Microphone (Razer BlackShark V2 Pro 2.4) (Elgato Virtual Audio)", "4 - VG249QML5A (AMD High Definition Audio Device)", "System (Elgato Virtual Audio)", "Fifine (Elgato Virtual Audio)"]
mix rate: 48000.0
latency samples x5 (1 s apart): 0.0100 s each -> one 5 ms bucket [10]
signature #1 == signature #2 (…|48000|10|8)
```
Latency is stable here, so it stays in the signature. Does Godot 4.7.2 expose the default endpoint? No: `AudioServer.output_device` returns the alias "Default" and the device list is just names; nothing resolves the alias to an endpoint (consulted the AudioServer class reference for output_device / get_output_device_list; no property or method names the resolved default). Documented limitation: a plain Windows default-output switch is not detected; plug/unplug (note the list includes Elgato virtual devices, which will trigger on Elgato software start/stop), mix-rate and latency changes are.

## Deviations from Plan
- **[Rule 3] Acceptance grep `grep -v '^#' settings.gd | grep -c AudioServer` is 0:** not literally met. Remaining hits are the pre-existing volume-bus calls (`get_bus_index`, `set_bus_volume_db`), unrelated to device lookup. No device APIs are called from settings.gd.
- Existing tests updated for the new behaviour: `test_device_change_shows_prompt...` now sets a stale signature; `test_bluetooth_warning_follows_device_name` uses an injected provider.
- RED phase for Task 1 was not run separately (tests and implementation written together, then run green).

## Verification
- test_audio_device_info (11), test_settings (14), test_calibration_flow (16), test_bt_heuristic (3): all pass.
- Full suite once at end: 179 test cases, 0 errors, 0 failures, 0 orphans.
- `grep -rnE "Thread\.new|OS\.execute|powershell" src`: empty. `audio_device_probe` not referenced from src/scenes/project.godot. export_presets.cfg keeps `tools/*`.

## Known Stubs
None.

## Self-Check: PASSED
