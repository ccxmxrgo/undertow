# UNDERTOW

Competitive online rhythm game in Godot. "Your streak is a torpedo."

## Pinned toolchain

- Godot **4.7.2-stable**, standard (non-.NET) build, Windows. Everyone uses this exact version.
- Export templates 4.7.2.stable (Windows Desktop).
- gdUnit4 **v6.2.1** (vendored in `addons/gdUnit4`).
- Fonts: Share Tech Mono (OFL, license in `assets/fonts/OFL-ShareTechMono.txt`) and Oxanium (OFL, license in `assets/fonts/OFL-Oxanium.txt`); sources in `assets/fonts/README.txt`.
- Renderer: Compatibility (`gl_compatibility`), 1920x1080 viewport, `canvas_items` stretch.

## Prerequisites

1. Godot 4.7.2 console build; set `GODOT_BIN` to `Godot_v4.7.2-stable_win64_console.exe`.
2. Export templates 4.7.2 installed (Editor > Manage Export Templates).
3. PowerShell.

## Running tests

```powershell
powershell -NoProfile -File tools/run_tests.ps1
powershell -NoProfile -File tools/run_tests.ps1 -Path res://tests/test_smoke.gd
```

The script imports the project on first run (creates `.godot/`), then runs
`GODOT_BIN --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <Path>`
and propagates the exit code (0 = pass, 100 = test failures). gdUnit4 6.2.1 needs
`--ignoreHeadlessMode` to run under `--headless`. Reports go to `reports/` (git-ignored).

Note: real-audio timing cannot be proven headless (the Dummy audio driver has no real device clock).
Use the non-headless Drift Harness and the F3 overlay for that.

## Windowed test launches open on the second monitor

`tools/playtest/run_all.ps1` starts every harness window on the first non-primary monitor
(Godot `--position`, found with `System.Windows.Forms.Screen`), so test runs do not cover the main
screen. Windowed tool scripts (`tools/make_wordmark.gd`, `tools/audio_device_probe.gd`) move their
window there through `tools/test_screen.gd`. The perf scenario's 1920x1080 / fullscreen capture uses
the screen the window is on and restores the window to it. Set `UNDERTOW_TEST_SCREEN=primary` to
use the main monitor instead (default `secondary`; with one monitor the primary is used). Each
scenario JSON logs `window_screen`, `window_screen_position` and `window_position`.

## Layout

```
src/core      pure timing/judgment logic (RefCounted, unit-testable)
src/input     input mapping
src/audio     conductor, audio clock
src/content   charts and song loading
src/ui        screens and widgets
src/autoload  singletons
scenes        .tscn scenes
tests         gdUnit4 suites (tests/helpers/fake_time.gd = injectable time)
tools         scripts (run_tests.ps1)
```
