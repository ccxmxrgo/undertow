---
phase: 2
slug: chart-import-songs
status: approved
reviewed_at: 2026-10-08
shadcn_initialized: false
preset: none
extends: .planning/phases/01.2-goggles-immersion/01.2-UI-SPEC.md
created: 2026-10-08
---

# Phase 2 - UI Design Contract (Chart Import & Songs)

> EXTENDS `01.2-UI-SPEC.md`, which extends `01.1-UI-SPEC.md`, which extends `01-UI-SPEC.md`. Anything not restated here is inherited unchanged: Share Tech Mono, the 4 type sizes (20 / 28 / 40 / 96) and 2 weights (Regular, Bold via `FontVariation`), the spacing scale (4..64), 1920x1080 base with `canvas_items` / `keep`, Compatibility renderer, the shared Theme `res://ui/undertow_theme.tres`, the single focus indicator (4px `#39FF14` border + caret), the input model (Tab never bound, `ui_*` navigation, hold-repeat after 400 ms at 10 Hz), Low effects and Reduce motion semantics, destructive dialog pattern, badge style (2px `#8FD98A` outline box, 32px tall).
> Where this file conflicts with 1.2, 1.1 or 1, THIS file wins for the new Song Select screen, the main-menu entries it touches, and the new Settings "LIBRARY" section.
> Platform: Godot 4.7.2, Control + `_draw`, **not web**. All pixels are at the 1920x1080 base. Mode: --auto (no questions asked). (D-xx) = 02-CONTEXT.md. (R) = 02-RESEARCH.md. (default) = chosen by the researcher, listed in the Defaults Log.
> Fantasy: the diver picks a dive site on the sub's sonar table before jacking in. Same neon abyss as 1.2. Screen edges are clean.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (Godot; shadcn not applicable). Registry gate: not applicable |
| Preset | not applicable |
| Component library | Shared Theme for buttons, Settings rows and dialogs. Song Select list and detail panel are code-drawn (`_draw`) so they match the 1.2 look |
| Icon library | none. Difficulty glyphs reuse `NoteShape` (diamond, circle, up-triangle, square). Caret and "!" are drawn polygons / font glyph. Hint text uses words, not arrow glyphs, because Share Tech Mono arrow coverage is unverified |
| Font | Share Tech Mono (unchanged) with a **system fallback** enabled so non-Latin song titles (CJK, Cyrillic, accents) render instead of empty boxes (default; verify in the harness with a fixture title) |
| Shaders | None (1.2 rule holds) |
| Background | `Arena` in **menu mode** (default): base `#02040A`, centre glow, trench wall rings scrolling at x0.25 speed, marine snow, corner vignette. No crowd, no beat pulse (pulse term 0), no miss glitch. If `Arena` cannot run without a `Conductor`, fallback = `#02040A` fill + static radial glow + marine snow + corner vignette |
| Render order, back to front | Arena (menu mode) > list + detail panel > footer > scan status > transient messages > fade-to-black on dive. All non-interactive nodes `mouse_filter = IGNORE`, `UiLayout.fill_rect` |
| New nodes (for harness and planner) | `SongSelect` (root), `SongList`, `DetailPanel`, `FilterField`, `SortChip`, `ScanStatus`, `FooterHints`, `CreditsLine`. Names are part of the contract so playtest scenarios can address them |

---

## Spacing Scale

Inherited (4, 8, 16, 24, 32, 48, 64). Phase 2 uses:

| Token | Value | Where |
|-------|-------|-------|
| xs (4) | 4px | Underline under the selected-difficulty pip, glyph-to-text nudges |
| sm (8) | 8px | Row gap in the list, gap between pips, badge padding |
| md (16) | 16px | Row inner padding right, gap between filter field and list, tile gap |
| lg (24) | 24px | Detail panel padding (all four sides) |
| xl (32) | 32px | Outer safe margin (nothing persistent inside it except the Arena vignette) |
| 2xl (48) | 48px | Minimum height of buttons, filter field, difficulty-tile row text box; gap between list column and panel |
| 3xl (64) | 64px | Screen-edge padding (left, right, top) |

Exceptions: row height 72 + 8 gap = **80 px pitch** (two text lines need 72); detail tile 72 px tall; scan bar 8 px. All multiples of 4. Strokes (2 and 4 px) are not spacing.

### Screen grid (exact, 1920x1080)

| Region | Rect (x, y, w, h) | Notes |
|--------|-------------------|-------|
| Header | 64, 64, 944, 48 | "SELECT SONG" title left, run badge after it, sort chip right-aligned to x = 1008 |
| Filter field | 64, 120, 944, 48 | Display-only field fed by key events |
| Song list | 64, 184, 944, 720 | **9 visible rows**, pitch 80, row body 72. Row n top = 184 + 80n. Scroll track x = 1024..1028 |
| Detail panel | 1056, 120, 800, 784 | Padding 24: inner rect x 1080..1832 (w 752), y 144..880 |
| Footer row A | 64, 928, 1792, 48 | Buttons left, scan status after them, credits line right-aligned to x = 1856 |
| Footer row B | hint baseline y = 1008 | Label 20, left x = 64 |

**Clean-edge rule (1.2) holds:** nothing persistent is drawn in the outer 32 px. The lowest text (hint line) has baseline 1008, descenders about 1014, inside the 1048 limit. The right edge of panel and credits is x = 1856 (64 px margin).

---

## Typography

Inherited: 4 sizes, 2 weights, line heights 1.5 (Label, Body) and 1.2 (Heading, Display). **No new sizes, no exceptions.** Display (96) is unused on this screen. Heading is UPPERCASE with +2 px spacing (inherited rule). Two-line rows use explicit baselines (below) rather than line-height stacking.

| Element | Size | Weight | Colour |
|---------|------|--------|--------|
| Screen title "SELECT SONG" | Heading 40 | Bold | `#E8E6F0` |
| Run badge ("PRACTICE DIVE", "AUTOPLAY") | Label 20 | Regular | `#8FD98A`, 2px outline box |
| Sort chip "SORT: TITLE" | Label 20 | Regular | `#8A93AD` (value part `#E8E6F0`) |
| Filter text | Body 28 | Regular | `#E8E6F0`; placeholder `#8A93AD` |
| Filter count "12 / 340" | Label 20 | Regular | `#8A93AD` |
| List row title | Body 28 | Regular (Bold when selected) | `#E8E6F0`; broken rows `#8A93AD` |
| List row artist, length, reason | Label 20 | Regular | `#8A93AD` |
| List row best depth | Label 20 | Regular | `#05D9E8`; "-" when none, `#8A93AD` |
| "TEST" badge | Label 20 | Regular | `#8FD98A`, 2px outline box |
| Panel song title | Heading 40, UPPERCASE, max 2 lines, ellipsis | Bold | `#E8E6F0` |
| Panel artist | Body 28 | Regular | `#E8E6F0` |
| Panel "CHARTED BY {x}", captions (LENGTH, BPM, NOTES, DIFFICULTY, BEST DEPTH, ACCURACY, SOURCE, PREVIEW) | Label 20 | Regular | `#8A93AD` |
| Panel stat values (length, BPM, notes, best depth, accuracy) | Heading 40 | Bold | `#05D9E8` |
| Difficulty tile name | Body 28, UPPERCASE | Regular (Bold when selected) | `#E8E6F0`; unavailable `#8A93AD` at 50% |
| Panel source value, warnings line | Label 20 | Regular | `#E8E6F0` / `#8A93AD` |
| Error reason block (title line) | Body 28 | Bold | `#FF4A3D` |
| Error reason block (fix hint) | Label 20 | Regular | `#8A93AD` |
| Buttons (Open Songs Folder, Rescan, Start Dive) | Body 28 | Bold | `#E8E6F0` |
| Button key hint ("ENTER", "A") | Label 20 | Regular | `#8A93AD` |
| Scan status | Label 20 | Regular | `#8A93AD` (error: `#FF4A3D`) |
| Footer hints, credits line | Label 20 | Regular | `#8A93AD` |
| Empty-state title ("NO MATCHES", "NO SONGS FOUND") | Heading 40 | Bold | `#E8E6F0` |
| Empty-state body | Body 28 | Regular | `#8A93AD` |

Numerals monospaced. Panel stat values are left-aligned in fixed 256 px columns (no layout shift). Strings from song data (title, artist, charter) are plain Labels / `draw_string` (never BBCode), already stripped of `<...>` and control chars and capped at 120 chars at import (R); the UI additionally truncates by measured width with "..." (three ASCII dots) so no row overflows.

### Row baselines (row top = r)

| Item | Position |
|------|----------|
| Caret (selected only) | polygon, x 80..96, centred y = r + 36 |
| Title baseline | (112, r + 32) |
| Artist / reason baseline | (112, r + 60) |
| Best depth, right-aligned to x = 992 | baseline r + 32 |
| Pips, right-aligned to x = 992 | centre y = r + 52 |
| Length "3:12", right-aligned to x = 904 | baseline r + 60 |

Title max width 776 px (to x = 888 minus badge when present). "TEST" badge sits 8 px after the title text end, vertically centred on the title line.

---

## Color

Neon-abyss palette from 1.2. Lane neons are `Palette.LANE_COLORS`.

| Role | Value | Usage on this screen |
|------|-------|----------------------|
| Dominant (60%) | `#02040A` | Arena base behind everything. Letterbox stays `#000000` |
| Secondary (30%) | `#0D1424` (panel fill at 80%, row fill at 60%), `#123A52` (selected row fill at 70%, pressed button fill, Start Dive fill), `#1E8CB4` (borders and range rings at low alpha), `#5A3CAA` (Arena walls only) | Rows, detail panel, buttons, borders |
| Accent (10%), teal data | `#05D9E8` | Reserved list below |
| Chrome text | `#E8E6F0` primary, `#8A93AD` captions | Per Typography |
| Focus accent | `#39FF14` | **Only** the inherited focus indicator: selected list row (4px border + caret), focused control in Settings > LIBRARY. Never fills, never text on this screen |
| Badge | `#8FD98A` | "TEST", "PRACTICE DIVE", "AUTOPLAY" outline boxes (1.2 badge style) |
| Error | `#FF4A3D` | Reserved list below |
| Difficulty (lane neons) | Easy `#22D3EE` cyan diamond, Medium `#FBBF24` amber circle, Hard `#F472B6` magenta up-triangle, Expert `#A3E635` lime square | Reserved list below |

Accent teal `#05D9E8` reserved for: (1) panel stat values (length, BPM, notes, best depth, accuracy), (2) the best-depth text in list rows, (3) the scan progress fill and scroll thumb, (4) the preview equaliser bars, (5) the sonar sweep and ping ring in the panel background (alpha 0.10 to 0.25, decorative), (6) the hover border on buttons and rows. Not used for body text, titles or captions.

Difficulty colours (lane neons) reserved for: (1) the four difficulty tiles in the panel, (2) the difficulty pips in list rows, (3) the 2px underline marking the selected difficulty under a pip. Mapping is by lane: Easy = lane 1, Medium = lane 2, Hard = lane 3, Expert = lane 4 (so the shapes match what the player will see on the board). They are never used for text, row highlight, buttons or chrome. Dimming of non-selected available tiles uses `NOTE_DIM = 0.60`; unavailable difficulties are drawn outline-only in `#8A93AD` at 35%.

Error `#FF4A3D` reserved for: (1) the "!" glyph on broken rows, (2) the reason block in the panel (4px left border, title line), (3) scan / folder errors in the status line, (4) the audio-load failure message, (5) Settings > LIBRARY folder errors. No destructive actions exist in this phase, so no destructive dialogs and no other use of red. Reason text inside a list row stays `#8A93AD` so a library with many broken songs is not a wall of red.

Panel treatment: fill `#0D1424` at 80%, 2px border `#1E8CB4` at 60%. Selected row: fill `#123A52` at 70% plus the 4px `#39FF14` border and caret. Unselected row: fill `#0D1424` at 60%, 2px border `#1E8CB4` at 35%. Hover (mouse): border `#05D9E8` at 60%.

Contrast (on `#0D1424`, approximate): `#E8E6F0` 15:1, `#8A93AD` 6:1, `#05D9E8` 10:1, `#FF4A3D` 5.5:1, `#E8E6F0` on `#123A52` 9.6:1. Colour is never the only signal: difficulty = shape + name; selection = border + caret + Bold; broken = "!" glyph + reason text + dimmed title; scan error = "!" glyph + text.

---

## Song Select Screen (D-09..D-13)

### Header

- "SELECT SONG" at baseline (64, 104).
- Run badge after the title, x = 384, y = 72..104 (32 tall): "PRACTICE DIVE" when entered from Practice Dive, "AUTOPLAY" when entered from Autoplay Dive; both stack (second at x = 384 + first width + 8). Normal Start Dive shows no badge. Practice carries NO-FAIL for the run only (1.1 rule).
- Sort chip right-aligned to x = 1008, baseline y = 100: "SORT: TITLE", "SORT: ARTIST", "SORT: BEST SCORE". Click or F2 / gamepad Y cycles Title > Artist > Best score > Title.

### Filter field (D-12)

- 944x48, fill `#0D1424` at 60%, 2px border `#1E8CB4` at 35%. Not a `LineEdit` (so arrows and Enter keep driving the list). It is a display driven by `_unhandled_key_input`.
- Empty: placeholder "Type to search title or artist" (`#8A93AD`) and, right-aligned inside the field (16 px inset), the count "{n} songs" (singular "1 song").
- With text: text left at x = 80 with a 2x28 caret (blinks 1 Hz; static under reduce motion), border becomes 2px `#05D9E8` at 60%, right side shows "{shown} / {total}".
- Matching: case-insensitive, whitespace-separated terms, all must appear in title or artist. Max 40 characters.

### Song list (virtualised, 9 rows)

Row anatomy (944x72) per the baselines above. Content:

| Slot | Content |
|------|---------|
| Title | Song title. Calibration Track shows "Calibration Track" + "TEST" badge |
| Artist line | Artist (or "Unknown artist" when empty). Calibration Track: "Built-in test chart". Broken: "!" glyph (`#FF4A3D`, 20px Bold) + one-line reason (`#8A93AD`) in place of the artist |
| Length | "3:12" (hidden on broken rows) |
| Best depth | Best across the song's difficulties, "1,240 m" in `#05D9E8`, or "-" |
| Pips | 4 slots in fixed order Easy, Medium, Hard, Expert. Present: filled lane shape (16px box, 2px outline, 25% fill, lane colour, `NOTE_DIM` unless it is the currently selected difficulty). Absent / unusable: outline only, `#8A93AD` at 35%. The currently chosen difficulty gets a 2px underline in its lane colour, 4px below the shape (shape cue) |

Row states:

| State | Look |
|-------|------|
| Default | Fill and border per Color; title Regular |
| Hover | 2px `#05D9E8` at 60% border |
| Selected | 4px `#39FF14` border, `#123A52` at 70% fill, caret, title Bold |
| Broken | Title `#8A93AD`, reason line, pips all outline-only. Selectable (so the reason shows in the panel) but Enter does nothing |
| Needs a chart (D-18) | **Distinct from Broken.** Audio-only file or folder with audio and no chart. Title (from tags or filename, falling back to the file name) in `#E8E6F0` at 70% alpha, a "NEEDS A CHART" badge (`#8FD98A`, 2px outline, 8px after the title) instead of the red "!" glyph, artist slot shows the hint "The extraction tool will chart this later" in `#8A93AD`, length shown if known, pips all outline-only. No red anywhere. Selectable (preview still plays so the player can confirm the track) but Enter does nothing |
| Selected + broken | Same as Selected, text stays `#8A93AD` |
| Info row (non-selectable) | "Add your own songs..." row (below): dashed 2px `rgba(138,147,173,0.35)` border, text `#8A93AD`, no fill; skipped by navigation |

Order: playable songs in the chosen sort, then **Calibration Track** (always shown, last among playable), then "Needs a chart" rows (by title), then broken songs (sorted by title) (default). "Needs a chart" songs are never silently skipped (D-18). Broken songs are never interleaved with playable ones, so a large library with many broken songs never buries playable songs.

Sort rules: Title = case-insensitive ascending; Artist = case-insensitive ascending, then title; Best score = best depth descending (songs with no record after, by title). During an active scan, newly arrived rows are inserted in sort order **without moving the selected row on screen** (the scroll offset is adjusted to keep the selection at the same y).

Scrolling: keep the selection inside rows 3 to 7 of 9 (scroll margin 2 rows); 120 ms ease-out smooth scroll (instant under Reduce motion). On entry, the last played song (persisted `last_song_id`) is selected and centred; if none, the first playable row. Scroll track 4px `rgba(232,230,240,0.25)` at x = 1024, thumb `#05D9E8`, min thumb 24px, hidden when everything fits.

Onboarding info row: shown as the last row of the playable block when the user library has no imported songs (only bundled + Calibration Track): "Add your own songs. Open the Songs folder and drop Clone Hero song folders or .zip files in." (Label 20, wraps to two lines inside the 72 px body).

### Detail panel ("sonar panel") (D-09)

Panel background layers, behind all text, clipped to the panel rect:
1. Fill and border per Color.
2. Range rings: 3 circles centred (1456, 512), radii 160 / 280 / 400, 2px `#1E8CB4` at 10% alpha; horizontal and vertical crosshair 2px at 6%.
3. Sweep: a 60 degree fan of 12 stacked line sectors, `#05D9E8` fading 0.10 to 0, rotating 1 rev / 8 s. **Off in Low effects, frozen and hidden under Reduce motion.**
4. Ping ring: on selection change, a ring expands from the centre, radius 0 to 400 over 600 ms, `#05D9E8` alpha 0.20 to 0. Off in Low effects and under Reduce motion. Cuttable.

Content layout (inner x 1080..1832; baselines unless noted):

| Item | Position |
|------|----------|
| Title (Heading 40, UPPERCASE, max 2 lines) | Baselines 184 and 232; block reserves y 144..240 |
| Artist | Baseline 272 |
| "CHARTED BY {name}" (omitted text: "CHARTED BY UNKNOWN") | Baseline 304 |
| Stat captions LENGTH / BPM / NOTES | x = 1080 / 1336 / 1592, baseline 364 |
| Stat values | same x, baseline 412. Length "3:12"; BPM "120" or range "90-140"; NOTES = note count of the **selected difficulty**, "1,204" |
| Divider | 2px `#1E8CB4` at 35%, y = 440, x 1080..1832 |
| "DIFFICULTY" caption | Baseline 476 |
| Difficulty tiles | y 488..560 (72 tall), 4 tiles 176 wide, 16 gap: x = 1080, 1272, 1464, 1656 |
| Best captions "BEST DEPTH" / "ACCURACY" (caption names the difficulty: e.g. "BEST DEPTH - EXPERT") | x = 1080 / 1336, baseline 604 |
| Best values | baseline 652. Depth format `1,240 M` (Heading, uppercase), accuracy "96%" |
| Warnings line (only if the import skipped lines) | Baseline 696 |
| "SOURCE" caption + value on one line | Caption x = 1080, value x = 1200, baseline 728 |
| Preview row | Baseline 760 |
| Start Dive button | x 1080..1832, y 832..880 |

Difficulty tile (176x72): lane glyph 24px at x+16, centred vertically; name in Body 28 UPPERCASE at x+52 baseline y+46.
- Available, not selected: 2px border in lane colour x0.60, fill 10% of lane colour, glyph dimmed, text Regular.
- Selected: 4px border in full lane colour, fill 25% lane colour, full glyph, text Bold, plus a 24px by 4px bar of the lane colour centred under the tile top edge outside (y 560..564) as the shape cue.
- Unavailable (difficulty not in the chart): no border, outline-only glyph `#8A93AD` at 35%, name `#8A93AD` at 50%. Not selectable; Left / Right skip it.
- Click selects. "EXPERT" (6 chars at 28 px about 101 px) fits the 124 px text box.

Best score block: values for the selected difficulty from `ScoreStore.best(fingerprint)`. With no record: caption row shows "BEST DEPTH - {DIFF}" only and the value area shows the Label "No record yet. Finish a dive to set one." (`#8A93AD`, baseline 652; same copy as before).

Preview row (baseline 760): while the preview is audible, 4 vertical bars (6 px wide, 4 gap, max height 24, `#05D9E8`) at x = 1080 driven by the Music bus peak (static bars 12/20/16/8 px under Reduce motion), then the caption "PREVIEW" at x = 1136. Hidden when no preview is playing (debounce window, broken song, music volume 0).

SOURCE value: "Bundled", "Songs folder", "Library: {folder name}", "Test chart". Bundled songs additionally credit through the artist line (the `song.ini` artist for the two bundled tracks is "Pro Sensory (Alex McCulloch)").

Debug: when the F3 overlay is on, the fingerprint of the selected difficulty is drawn as Label 20 `#8A93AD` right-aligned at (1832, 696). Invisible otherwise.

Start Dive button: full inner width, 48 tall. Fill `#123A52`, 2px `#05D9E8` border, text Body 28 Bold "Start Dive" at x+24, key hint right-aligned 24 inset ("ENTER", or "A" when the last input was a gamepad). Not part of the focus ring (Enter dives from the list); hover = border brightens to 100% alpha, click dives. Variants: "Start Practice Dive", "Start Autoplay Dive". Disabled (broken song, none selected): border and text `#8A93AD` at 35% / 50%, text "Unavailable", no key hint. While the chart is being built: "Loading..." disabled.

Needs-a-chart panel (D-18): same as the broken panel (stat values "-" except LENGTH when known, all tiles unavailable, Start Dive disabled "Needs a chart") but the reason block uses a neutral 4px `#8FD98A` left border (no "!" glyph, no red): title line Body 28 Bold `#E8E6F0` "Needs a chart", hint Label `#8A93AD` "This is audio only. The extraction tool will chart it in a later update." The preview row still works.

Album art (D-19): **ignored** (default). `.png` / `.jpg` files in song folders are never loaded, which avoids decoding untrusted images during a scan and keeps rows uniform. Multi-stem folders show as one normal row.

Broken-song panel: title/artist from `song.ini` or the folder name when unreadable; stat values "-" in `#8A93AD`; all four tiles unavailable; the reason block replaces the best-score block (y 588..700): 4px `#FF4A3D` left border, "!" glyph, reason as Body 28 Bold red (wraps 2 lines), then the fix hint as Label `#8A93AD` (table in Copywriting). The sort / filter still include broken songs.

### Footer

Row A (y 928..976):
- Button "Open Songs Folder": x 64, w 340, h 48. 2px `#1E8CB4` at 60% border, fill `#0D1424` at 60%, text Body 28 Bold. Hover border `#05D9E8`; pressed fill `#123A52`. Hotkey F6 / gamepad Select (Back). Works on first launch before any scan has run (D-20): it creates `user://songs` if missing, then opens it, and never depends on `SongLibrary` state. Opens `OS.shell_show_in_file_manager` on the globalised `user://songs` (created first). If it fails, the scan-status line shows the red message.
- Button "Rescan": x 420, w 160, h 48, same style. Hotkey F5 / gamepad X. While scanning it shows "Scanning..." (disabled style) and ignores input.
- Scan status at x = 604, baseline y = 960 (Label 20), see Scan states. The progress bar (when shown) is 240x8 at x = 604, y = 936 (track `rgba(232,230,240,0.25)`, fill `#05D9E8`), the status text sits under it. Total width limit x <= 1008.
- Credits line, right-aligned to x = 1856, baseline y = 960: "Music: Pro Sensory (Alex McCulloch), CC0, via OpenGameArt.org" (Label 20, `#8A93AD`). Always visible. The two track titles are credited in README and appear as the song titles themselves.

Row B hint line, baseline y = 1008, x = 64 (swaps by last input device, 1.2 rule; entries separated by two spaces, a middle dot, two spaces):
- Keyboard, filter empty: `UP DOWN SONG  ·  LEFT RIGHT DIFFICULTY  ·  ENTER DIVE  ·  F2 SORT  ·  F5 RESCAN  ·  ESC BACK` (about 90 chars, about 1080 px). Must end at x <= 1040 so it does not collide with the path; if it measures wider, drop "F2 SORT" before shrinking text.
- **Songs folder path (D-20), always visible**, right-aligned to x = 1856 on the same baseline y = 1008: `Songs folder: {absolute path}` (Label 20; prefix `#8A93AD`, path `#E8E6F0`), middle-truncated with "..." to at most 800 px (about 66 chars, x >= 1056). Clicking it opens the folder (same as the button).
- Keyboard, filter active: `TYPE TO FILTER  ·  BACKSPACE EDIT  ·  ESC CLEAR FILTER  ·  UP DOWN SONG  ·  ENTER DIVE`
- Gamepad: `D-PAD SONG  ·  LEFT RIGHT DIFFICULTY  ·  A DIVE  ·  Y SORT  ·  X RESCAN  ·  B BACK`

---

## Scan States (D-07, D-08)

The library scans in the background on game start (autoload) and on Rescan. Song Select never waits on it: it shows whatever `SongLibrary` has now and updates live.

| State | Visual |
|-------|--------|
| Cache hit, fast scan (< 300 ms) | No progress strip is shown at all (it appears only after 300 ms to avoid flicker). Final status text only |
| Enumerating (total unknown) | Status "Looking for songs..." and an indeterminate bar: a 64 px fill segment sliding across the 240 px track in 1.2 s loops (static half-filled track under Reduce motion) |
| Scanning | Bar fill = done / total. Text "Scanning {done} / {total}". Rows appear in the list as they arrive |
| Unpacking a zip | Text "Unpacking {name}" (name truncated to 28 chars, then "...") replaces the counter while that job runs |
| Done | No bar. Text "{n} songs" or "{n} songs  ·  {m} unplayable" (singular "1 song"). Persists |
| Folder error | "!" glyph + `#FF4A3D` text: `Could not read library folder "{name}".` (one line per scan; the last one wins, full list in the log) |
| Open folder failed | `Could not open the Songs folder. It is at {path}` (red, "!" glyph), clears after 6 s |
| Corrupt or stale cache | Silent. The scan simply re-imports; no message |

Rescan during a scan is ignored (button disabled). Leaving Song Select does not cancel the scan. Entering Song Select while the scan is running attaches to it.

**Empty library** (no playable songs at all, e.g. bundled content failed to load): the list region shows centred "NO SONGS FOUND" (Heading, y baseline 480) and "Drop Clone Hero song folders or .zip files into the Songs folder, then press Rescan." (Body 28, `#8A93AD`, wraps to 2 lines inside 800 px, first baseline 540). Under it (D-20) the exact location: caption "Your Songs folder is:" (Label 20, `#8A93AD`, baseline 620) and the full absolute path (Body 28, `#E8E6F0`, wraps up to 3 lines inside 800 px, first baseline 660, never truncated here). The Open Songs Folder button is the only accent. The detail panel shows the same sonar background with the stat values "-" and Start Dive disabled "Unavailable".

**No filter match:** list region shows "NO MATCHES" (Heading, baseline 480) and `No song matches "{filter}". Press Esc to clear it.` (Body 28 `#8A93AD`, baseline 540, wraps). Panel as above. Esc clears the filter.

---

## Interaction Contract (D-11, D-12)

### Input map

| Action | Keyboard | Gamepad | Mouse |
|--------|----------|---------|-------|
| Previous / next song | Up / Down. Hold repeat after 400 ms at 10 Hz; after 1.2 s of holding, 20 Hz | D-pad / left stick Up / Down (same repeat) | Wheel scrolls 1 row per notch; click row selects; double-click dives |
| Jump 1 row | `1` = up, `2` = down (only while the filter is empty) | | |
| Jump a page (9 rows) | `3` = up a page, `4` = down a page (only while the filter is empty). PageUp / PageDown also | LB / RB | |
| Top / bottom | Home / End | | |
| Change difficulty | Left / Right (skips unavailable). Wraps never; clamps at ends | D-pad Left / Right | Click a tile |
| Dive | Enter (ignored on broken songs) | A | Click Start Dive |
| Back | Esc: clears a non-empty filter first, otherwise returns to the main menu | B | |
| Filter | Any printable character (not with Ctrl / Alt); Backspace removes one; `/` or Ctrl+F enters typing mode with an empty field (digits then type instead of navigate) | none (no text entry on gamepad; scroll instead) | |
| Cycle sort | F2 | Y | Click sort chip |
| Rescan | F5 | X | Click Rescan |
| Open songs folder | F6 | Select / Back | Click button |

Rules:
- Digits `1`-`4` navigate only while the filter text is empty **and** typing mode is off. Typing mode starts on the first letter / `/` / Ctrl+F and ends on Esc or when Backspace empties the field.
- These keys are fixed on this screen; they are not the rebindable lane bindings (no `BindingStore` use) (R, Pitfall 2).
- F-keys used: F2, F5, F6. F3 (debug) and F11 (fullscreen) keep working. Tab is unused.
- Initial focus: the list, with the last played song selected. Every control is reachable by keyboard or gamepad through the hotkeys above.
- Key echo is ignored for single-fire actions (Enter, Esc, F-keys).
- The selected difficulty is remembered (persisted `last_difficulty`). When moving to a song that lacks it, snap to the nearest available difficulty, preferring the lower one on a tie.

### Selection, preview, dive

- Selection change: panel content updates instantly (no cross-fade), ping ring plays (if allowed), the preview debounce restarts.
- Preview (D-10): starts 0.4 s after the highlight settles, from `preview_start_time` or 30% into the song, fade in 0.4 s, fade out 0.25 s, Music bus, honours `Settings.volume_music`. Loads on a worker thread; a stale result is discarded if the highlight moved. Stops on Esc, dive, leaving the screen, and when the highlight lands on a broken song.
- Dive (Enter / A / click): preview fades out over 0.25 s while the screen fades to `#000000` over 0.15 s (instant cut under Reduce motion), `Gameplay.pending_chart` is set, then the FULL goggles intro plays as in 1.2 (Practice and Autoplay carry through). Second Enter during the fade is ignored.
- Audio load failure at dive time: stay on Song Select, preview row replaced by a red "!" message (Copywriting). It clears on the next navigation. Bundled songs and the Calibration Track keep the existing 1.2 error copy.
- Returning from a run: "Retry Dive" replays the same song and difficulty; "Back to Menu" (unchanged copy) goes to the main menu, and Start Dive reopens Song Select on the song just played (default).

### Main menu changes (D-13)

- Order: **Start Dive**, **Practice Dive (No-Fail)**, Calibrate Sonar, Settings, Autoplay Dive (test), **Open Songs Folder**, Quit Game.
- Start Dive, Practice Dive (No-Fail) and Autoplay Dive (test) open Song Select with the matching run flag.
- The old "Best: ... Accuracy ..." line under Start Dive is **removed** (records are per song and difficulty now, shown in Song Select). The "No record yet" copy moved into the detail panel (default; the menu best-line label node can stay hidden for harness compatibility).
- First launch routing to calibration is unchanged.

### Settings: new "LIBRARY" section (D-05, D-06)

Section order: Controls, Gameplay, Display, Audio, **Library**, Calibration. Rows min 48 px, inherited focus indicator and Label hints.

| Row | Content |
|-----|---------|
| Songs folder | Label caption "Songs folder", value = globalised `user://songs` path (Label 20 `#8A93AD`, middle-truncated), button "Open Songs Folder" |
| Extra library folders | Heading-less list, one row per folder: path (Label 20, middle-truncated, `#E8E6F0`), status (Label 20 right-aligned: "{n} songs", "Not scanned yet", or red "Folder not found"), button "Remove" |
| Add | Button "Add Folder" opens the native folder picker (`DisplayServer.file_dialog_show`, directory mode; fallback Godot `FileDialog` in directory mode). Max 8 folders |
| Hints (Label 20, `#8A93AD`, under the list) | "Extra folders are scanned where they are. Your files are never copied or changed." and "Tip: add your Clone Hero songs folder." and "Songs from added or removed folders update in a background scan when you leave Settings." |

Behaviour: paths are normalised and must exist and be directories; duplicates and the Songs folder itself are rejected with inline red text ("!" glyph, clears after 3 s or next input, 1.0 pattern). Remove needs no confirmation: it only stops scanning the folder (the hint says so), nothing on disk changes. Leaving Settings with a changed list triggers a background rescan.

---

## Low Effects and Reduce Motion

| Item | Full | Low effects | Reduce motion |
|------|------|-------------|---------------|
| Arena (menu mode) | 14 rings, snow 80 | 6 rings, snow 24 | 14 rings at scroll x0.25 (already slow), snow frozen |
| Sonar sweep + ping ring | on | off | off |
| Preview bars | animated | animated | static bars |
| Scan indeterminate slide | on | on | static half fill |
| Smooth list scroll | 120 ms | 120 ms | instant |
| Filter caret blink | 1 Hz | 1 Hz | solid |
| Dive fade | 0.15 s | 0.15 s | instant cut |

Readability of rows, text, tiles and pips is identical in all modes.

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | "Start Dive" (also "Start Practice Dive", "Start Autoplay Dive"; disabled: "Unavailable") |
| Screen title | "SELECT SONG" |
| Filter placeholder | "Type to search title or artist" |
| Library count | "{n} songs" / "1 song"; filtering: "{shown} / {total}" |
| Sort labels | "SORT: TITLE", "SORT: ARTIST", "SORT: BEST SCORE" |
| Footer buttons | "Open Songs Folder", "Rescan" (busy: "Scanning...") |
| Menu entry | "Open Songs Folder" |
| Calibration Track row | "Calibration Track", badge "TEST", artist line "Built-in test chart" |
| Empty artist | "Unknown artist" |
| Panel captions | "LENGTH", "BPM", "NOTES", "DIFFICULTY", "BEST DEPTH - {DIFFICULTY}", "ACCURACY", "SOURCE", "PREVIEW", "CHARTED BY {name}" / "CHARTED BY UNKNOWN" |
| Difficulty names | "EASY", "MEDIUM", "HARD", "EXPERT" |
| Source values | "Bundled", "Songs folder", "Library: {folder name}", "Test chart" |
| Warnings line | "{n} lines in this chart were skipped." (singular "1 line in this chart was skipped.") |
| Empty state: no record | "No record yet. Finish a dive to set one." |
| Empty state: no filter match | Heading "NO MATCHES"; body `No song matches "{filter}". Press Esc to clear it.` |
| Empty state: library empty | Heading "NO SONGS FOUND"; body "Drop Clone Hero song folders or .zip files into the Songs folder, then press Rescan." followed by "Your Songs folder is:" and the full path (see Empty library). Same copy appears in the onboarding row, which ends "...drop Clone Hero song folders or .zip files in. The path is shown below." |
| Onboarding info row | "Add your own songs. Open the Songs folder and drop Clone Hero song folders or .zip files in." |
| Scan status | "Looking for songs..." / "Scanning {done} / {total}" / "Unpacking {name}" / "{n} songs  ·  {m} unplayable" |
| Error: folder unreadable | `Could not read library folder "{name}".` |
| Needs a chart (D-18) | Row badge "NEEDS A CHART"; row hint "The extraction tool will chart this later"; panel title "Needs a chart"; panel body "This is audio only. The extraction tool will chart it in a later update."; Start button "Needs a chart" (disabled) |
| Songs folder path line (D-20) | "Songs folder: {absolute path}" |
| Error: open folder failed | "Could not open the Songs folder. It is at {path}" |
| Error: song audio at dive (user song) | "This song's audio could not be loaded. Choose another song." |
| Error: song audio at dive (bundled / test) | "Song audio could not be loaded. Reinstall the game files or choose another song." (existing) |
| Credits line | "Music: Pro Sensory (Alex McCulloch), CC0, via OpenGameArt.org" |
| Settings section heading | "LIBRARY" |
| Settings rows | "Songs folder", "Extra library folders", "Add Folder", "Remove" |
| Settings status per folder | "{n} songs" / "Not scanned yet" / "Folder not found" |
| Settings errors | "That folder is already in the list." / "That folder does not exist. Pick an existing folder." / "You can add up to 8 library folders." |
| Destructive confirmation | None in this phase. "Remove" only forgets a folder path and "Rescan" is read-only, so neither needs confirmation (the Library hint states that files are never changed) |

### Broken-song reasons (one line in the row; fix hint in the panel)

| Row reason (max about 48 chars) | Panel fix hint |
|---------------------------------|----------------|
| "Opus audio not supported" | "Convert the audio to OGG Vorbis, MP3 or WAV, then press Rescan." |
| "No guitar chart" | "This chart has no lead guitar notes. Only guitar charts work." |
| "Unreadable .chart (line {n})" | "The chart file looks damaged near line {n}. Download the song again." |
| "Audio file missing" | "No song audio found next to the chart. Add song.ogg, song.mp3 or song.wav, then press Rescan." |
| "MIDI charts not supported yet" | "This song only has a .mid chart. Only .chart files work for now." |
| "Unsupported audio format" | "Use OGG Vorbis, MP3 or WAV audio." |
| "Audio could not be read" | "The audio file looks damaged. Replace it, then press Rescan." |
| "Zip could not be unpacked" | "The zip is damaged or has unsafe paths. Unzip it into the Songs folder yourself." |
| "Chart too large" | "This chart file is far larger than any normal song. It was skipped." |

Tone: plain sentences, problem then next step, no blame, diegetic flavour kept to titles and the intro (consistent with 1.2). Songs-folder wording uses "Songs folder" capitalised as a noun.

---

## Harness and Verification Hooks (for planner and auditor)

- Screenshot scenarios (windowed harness): (1) library with 2 bundled + 30 fixture songs, mid-list selection; (2) selected broken song (Opus); (3) mid-scan with progress bar; (4) filter with no match; (5) empty library; (6) filter active with count; (7) long-title / CJK fixture row and panel; (8) Settings > LIBRARY with two folders (one missing); (9) Low effects and Reduce motion variants.
- Suggested assertions: exactly 9 rows drawn; no row text overflows its rect; nothing persistent drawn in the outer 32 px other than the Arena vignette; hint line fits within x <= 1856; selected row y is unchanged when a scan inserts rows above it; digits navigate with empty filter and type with a non-empty one; Enter on a broken row does nothing; Esc order (clear filter, then back); preview starts no sooner than 0.4 s after the last highlight change and is stopped by dive; difficulty snap on missing difficulty; sort orders including "broken last".
- Typography exception count: none. Colour exceptions: none beyond the lane-neon difficulty use declared above.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none (not applicable, Godot project) | not required |
| Third-party UI registries | none | not applicable |
| Vendored assets | none added by the UI. (Bundled music is content, covered by D-14 and the README credits) | not required |

---

## Defaults Log (researcher choices, not in upstream artifacts)

- Layout: 944 px list column (9 rows, pitch 80) + 800 px sonar panel, 64 px screen padding, 48 px column gap. Rows and panel are code-drawn, not an `ItemList`, because rows need two lines, a best score and pips (R's `ItemList` suggestion is for the data path; a virtualised `_draw` list keeps the same performance for thousands of songs).
- Keys `1` / `2` = up / down one row, `3` / `4` = page up / page down (D-11 says "keys 1-4 move through the list" without a mapping). `/` and Ctrl+F start typing mode so numeric searches work. Digits navigate only while the filter is empty (orchestrator resolution).
- F2 sort, F5 rescan, F6 open songs folder; gamepad Y / X / Select. Footer buttons are mouse targets and hotkey surrogates; they are not in the focus ring.
- Album art is ignored (D-19); "Needs a chart" rows (D-18) use a neutral `#8FD98A` badge, not the red broken state, and sort between the Calibration Track and broken songs.
- Calibration Track sorts last among playable songs; broken songs sort after it (orchestrator said "sorted last"; broken rows are inert, so they go below).
- Row best depth = best across all difficulties (this is the "best score" sort key); the panel shows the selected difficulty only.
- Difficulty colours follow lane order (Easy cyan diamond, Medium amber circle, Hard magenta triangle, Expert lime square); the 4px bar under the selected tile and the pip underline are the shape cues.
- Focus indicator stays the inherited `#39FF14`; all other chrome on this screen is teal / secondary so green is not diluted.
- Broken-row reasons stay muted `#8A93AD` with a red "!" glyph; the red reason block appears only in the panel.
- Title Case for "Open Songs Folder" and "Rescan" (matches house button style); the user wrote "Open songs folder" in lower case.
- Main menu best line removed (records are per song / difficulty); "Open Songs Folder" menu entry added before Quit Game.
- Arena menu mode instead of a new background; fallback if Arena is Conductor-coupled.
- Scan progress strip appears only after 300 ms.
- Filter: all whitespace-separated terms must match, title or artist, case-insensitive, no match highlighting.
- Preview equaliser bars driven by Music bus peak; sonar sweep and ping ring decorative and cuttable.
- Settings > LIBRARY: max 8 folders, native folder picker with `FileDialog` fallback, background rescan on leaving Settings, Remove without confirmation.
- Fade-to-black 0.15 s on dive; Start Dive reopens on the last played song and difficulty (persisted `last_song_id`, `last_difficulty`).
- Font system fallback for non-Latin titles.
- Hint line uses words instead of arrow glyphs.
- Credits line shown always in the footer, shortened to fit under the panel.

## Notes for the checker (non-blocking)

- Typography: 4 sizes, 2 weights, no exceptions. Heading UPPERCASE is applied to the panel song title, which uppercases user data for display only.
- Colour: green `#39FF14` is limited to the inherited focus indicator; teal list and lane-neon use are enumerated. Red appears only for errors.
- Spacing: all values are multiples of 4; row pitch 80 and the 944 / 800 column widths are multiples of 4.
- Open question for the planner: whether the Calibration Track is hidden in release builds (D-13 discretion). This spec keeps it visible, last among playable songs, with the "TEST" badge (orchestrator resolution).
- Visual verification (row legibility, long and non-Latin titles, panel background versus text contrast, scroll feel, scan insertion stability) needs the windowed harness (`tools/playtest/run_all.ps1`).

---

## Checker Sign-Off

- [x] Dimension 1 Copywriting: PASS
- [x] Dimension 2 Visuals: PASS
- [x] Dimension 3 Color: PASS
- [x] Dimension 4 Typography: PASS
- [x] Dimension 5 Spacing: PASS
- [x] Dimension 6 Registry Safety: PASS

**Approval:** pending

## Checker amendments (orchestrator, 2026-10-08)
- **Keyboard hint line:** the shorter fallback (without "F2 SORT") is the **default**, so the hint line ends at x≤1040 and clears the Songs-folder path. If it still overflows when measured, move the path to its own footer row.
- **Copy:**
  - Folder-read error: `Could not read library folder "{name}". Check that it still exists, then press Rescan Library.`
  - Buttons: "Rescan Library", "Remove Folder".
  - Onboarding row: use the empty-library string (with "The path is shown below.") in both places.
- **Focal point:** the selected song row and the Start Dive button.
