---
phase: 01-timing-core-calibration
plan: 01
subsystem: infra
tags: [godot, gdunit4, scaffold, testing, powershell]
requires: []
provides:
  - Godot 4.7.2 project skeleton (Compatibility renderer, 1920x1080 canvas_items)
  - tools/run_tests.ps1 headless gdUnit4 test command
  - FakeTime injectable ticks source
  - Master/Music/SFX bus layout
affects: [all later phase 1 plans]
tech-stack:
  added: [Godot 4.7.2, gdUnit4 v6.2.1, Share Tech Mono]
  patterns: [injected time source, headless CLI tests]
key-files:
  created: [project.godot, .gitignore, README.md, default_bus_layout.tres, tools/run_tests.ps1, tests/helpers/fake_time.gd, tests/test_smoke.gd]
  modified: []
key-decisions:
  - "gdUnit4 6.2.1 works headless on 4.7.2 but requires --ignoreHeadlessMode; baked into run_tests.ps1"
  - "Godot-generated .uid and .import files are committed (Godot 4.4+ convention)"
requirements-completed: [CAL-04]
duration: ~15min
completed: 2026-10-07
---

# Phase 1 Plan 01: Scaffold and Headless Test Command Summary

Godot 4.7.2 project scaffold with a proven headless gdUnit4 6.2.1 test command (`tools/run_tests.ps1`), FakeTime helper and Master/Music/SFX buses.

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Human installs (Godot 4.7.2, templates, gdUnit4, font, git) | 8d7adc2 (performed by orchestrator with user approval) |
| 2 | Scaffold project, buses, README, runner, FakeTime, smoke test | a00e1a7 |

## Verification

- `powershell -NoProfile -File tools/run_tests.ps1 -Path res://tests/test_smoke.gd` exits 0 (3/3 tests pass).
- A deliberately failing temporary suite exited 100 (non-zero propagated); it was then removed.
- project.godot: `gl_compatibility` count 1, no Tab binding.

## Deviations from Plan

**1. [Rule 3 - Blocking] Added `--ignoreHeadlessMode` to the runner**
- Found during: Task 2. gdUnit4 6.2.1 aborts (exit 103) under `--headless` without it. The plan explicitly allowed adding this flag; gdUnit4 was NOT replaced, so no GUT fallback was needed.
- Files: tools/run_tests.ps1, README.md. Commit: a00e1a7.

**2. [Rule 3] Runner falls back to the User-scope GODOT_BIN** when `$env:GODOT_BIN` is empty in a stale shell.

**3. Generated files committed:** Godot's first import produced `.uid` / `.import` files for the vendored addon and font; committed in a00e1a7.

## Known Stubs

None.

## Issues Encountered

None beyond the above. Real-audio timing remains unprovable headless (documented in README).

## Self-Check: PASSED

Files and commits (8d7adc2, a00e1a7) verified present.
