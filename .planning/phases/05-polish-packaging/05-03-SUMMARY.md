---
phase: 05-polish-packaging
plan: 03
subsystem: packaging
tags: [dist, exe, icon, version-info, boot-splash, readme]
requires: []
provides:
  - "UNDERTOW sonar app icon (PNG 256 + multi-size PNG ICO)"
  - "exe VersionInfo 0.7.0.0 / ProductName UNDERTOW via export preset"
  - "dark ABYSS_900 boot splash without the Godot logo"
  - "tools/check_exe.ps1 gate, called by tools/dist.ps1 after export"
  - "README.txt START HERE block"
affects: [05-08]
tech-stack:
  added: []
  patterns: ["headless Image-API asset generator (tools/make_icon.gd)", "post-export exe assertion script"]
key-files:
  created:
    - tools/make_icon.gd
    - assets/ui/undertow_icon.png
    - assets/ui/undertow_icon.png.import
    - assets/ui/undertow_icon.ico
    - tools/check_exe.ps1
  modified:
    - project.godot
    - export_presets.cfg
    - tools/dist.ps1
    - tools/dist/README.txt
decisions:
  - "ICO carries 16/32/48/64/128/256 PNG entries (not one 256 entry): Godot 4.7.2 warns 'Icon size N is missing' otherwise"
  - "check_exe.ps1 refuses exe paths >= 248 chars: past MAX_PATH ExtractAssociatedIcon returns a generic icon (false pass) and Start-Process rejects the working dir"
metrics:
  duration: "~25 min"
  completed: 2026-10-21
---

# Phase 5 Plan 03: Exe polish (icon, version info, dark splash, START HERE) Summary

The friend build now has its own sonar-scope icon and Windows version info (0.7.0.0, product name UNDERTOW). It boots on a plain ABYSS_900 splash with no Godot logo. `tools/dist.ps1` refuses to ship an exe whose icon is still Godot's or whose version does not match `config/version`. The README opens with a short START HERE block.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 4819ca4 | Icon generator, PNG/ICO assets, project icon and dark boot splash |
| 2 | 88df4a0 | Preset icon and version info, check_exe.ps1, dist.ps1 hook, README START HERE, multi-size ICO |

## What was built

- **tools/make_icon.gd** (`extends SceneTree`, headless): draws the sonar scope at 1024 px using only Palette tokens, then downsamples with Lanczos. The scope has range rings, a crosshair, a 70 degree fading sweep with a SONAR_PALE leading edge, a SONAR_PALE contact blip with a halo, a WARNING_RED rival blip, an ABYSS_700 inner ring and a SONAR bezel. Output is a 256x256 PNG plus a PNG-compressed ICO. Prints `ICON OK 35787 65272`.
- **project.godot** [application] (the 3 added lines are the only change; config/version is still "0.7.0"):
  - `config/icon="res://assets/ui/undertow_icon.png"`
  - `boot_splash/bg_color=Color(0.011764706, 0.023529412, 0.050980393, 1)`
  - `boot_splash/show_image=false`

  A ProjectSettings probe confirms that 4.7.2 accepts `application/boot_splash/show_image` (has=true, val=false) and the bg_color.
- **export_presets.cfg**: only the planned keys changed:
  - `modify_resources=true`
  - `icon` and `console_wrapper_icon` set to the ICO
  - `file_version` and `product_version` set to "0.7.0.0"
  - the copyright line

  embed_pck, the console wrapper, the filters and codesign=false are untouched.
- **tools/check_exe.ps1**, in order:
  - Checks VersionInfo against `config/version + ".0"` (normalised to 4 parts) and checks ProductName.
  - Compares the SHA-256 of the extracted icon with the icon of the 4.7.2 `windows_debug_x86_64.exe` template. Equal hashes fail, and so does a missing template.
  - With `-Selftest`, runs the exe and requires `BUNDLED_OK 20` with exit 0, using the same Start-Process pattern as dist.ps1.
  - Fails on exe paths of 248 characters or more.
  - Prints `EXE CHECK OK` at the end.
- **tools/dist.ps1**: calls check_exe.ps1 right after the export artifact check and fails the build on a non-zero exit. The header has a new comment line. The allow-list, Autocharter Pack bundling and verification (PackSpec pins, AC_PACK_FOUND) and the BUNDLED_OK 20 selftest are byte-unchanged. The file's line endings are still CRLF.
- **tools/dist/README.txt**: a 12-line START HERE block sits above the title line, as specified in the plan. Everything below it is unchanged.

## Verification

Debug export was run to a scratch path, then copied to `%TEMP%\ut0503chk\UNDERTOW.exe`. dist.ps1 and export.ps1 were **not** run, so build/ and the v0.7.0 zip are untouched.

- Export exit code 0, with no warnings once the ICO had every size.
- VersionInfo: FileVersion 0.7.0.0, ProductVersion 0.7.0.0, ProductName UNDERTOW.
- Icon hashes:
  - exe `c633e63dfa42f0b76b5927b271fb2383360a848650d005c7e281382bebb88f14`
  - template `8d73cbae83193cd4552282ecec7b6e16c264e206831d88246f116666f2b8969b`

  The extracted 32x32 bitmaps were inspected by eye: the exe shows the sonar scope and the template shows the Godot robot.
- `check_exe.ps1 -Selftest` printed: EXE VERSION OK 0.7.0, EXE ICON OK, BUNDLED_OK 20, EXE CHECK OK.
- Exe size: 136,148,072 bytes (pck embedded).
- Negative test: running the check on a copy of the plain Godot template fails with exit 1 (version mismatch: FileVersion 4.7.2, empty ProductName).
- README first line is `START HERE`. `grep -c check_exe.ps1 tools/dist.ps1` = 3.
- TIMING GATE OK.

**A6 outcome:** confirmed. With `modify_resources=true`, Godot 4.7.2 embeds both the ICO and the version info into the PE. No rcedit was needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ICO had only a 256 px entry**
- **Found during:** Task 2 (first export)
- **Issue:** Godot's resource modification warned `Icon size "16"/"32"/"48"/"64"/"128" is missing`, so the small icons in Explorer and the taskbar might not have been replaced, and the export finished "with warnings".
- **Fix:** make_icon.gd now writes 6 PNG entries (16, 32, 48, 64, 128, 256), each downsampled from the 1024 px master. The project PNG did not change (byte-identical).
- **Files modified:** tools/make_icon.gd, assets/ui/undertow_icon.ico
- **Commit:** 88df4a0

**2. [Rule 2 - Correctness] Icon check could pass falsely on long paths**
- **Found during:** Task 2
- **Issue:** On a 272-character path, ExtractAssociatedIcon returned a different (generic) icon. That icon still "differs" from Godot's, which would be a silent false pass, and Start-Process failed with "directory name is invalid".
- **Fix:** check_exe.ps1 now fails up front on exe paths of 248 characters or more. The checks themselves were not weakened.
- **Commit:** 88df4a0

## Notes for 05-08

- When you bump `config/version` to 0.8.0, also set `application/file_version` and `application/product_version` in export_presets.cfg to `"0.8.0.0"`. check_exe.ps1, run from dist.ps1, will fail the build otherwise.
- Update the README title line (v0.7.0 ...) under the START HERE block as usual. The START HERE block itself does not name a version.
- The build machine needs the 4.7.2 export template at `%APPDATA%\Godot\export_templates\4.7.2.stable\` for the icon check. It is present.
- Keep the build path short. build/UNDERTOW.exe in the repo is fine.

## Self-Check: PASSED

- All created files exist: tools/make_icon.gd, assets/ui/undertow_icon.png(.import), assets/ui/undertow_icon.ico, tools/check_exe.ps1.
- Commits 4819ca4 and 88df4a0 are present on origin/main.
