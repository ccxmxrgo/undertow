---
phase: 4
slug: online-play
status: draft
shadcn_initialized: false
preset: none
created: 2026-10-20
mode: auto (no questions asked; user asleep; every choice is consistent with 02.2 and 03 and is recorded in the Defaults Log, section 17)
extends:
  - ".planning/phases/02.2-visual-design-overhaul/02.2-UI-SPEC.md (approved 2026-10-10)"
  - ".planning/phases/03-offline-versus/03-UI-SPEC.md (Phase 3 versus HUD, match setup, versus results)"
---

# Phase 4 - UI Design Contract: Online Play

> **Authority:** `04-CONTEXT.md` / `04-RESEARCH.md` decisions D-01..D-24 > this file > `03-UI-SPEC.md` > `02.2-UI-SPEC.md`. Everything in those two files stays in force unless a row below says otherwise. Where this file refines a D-xx default, the reason is in the Defaults Log (section 17).
> **Platform:** Godot 4.7.2, GDScript, `gl_compatibility`, 1920x1080 base, `canvas_items` / `keep`. All pixel values are at the 1920x1080 base.
> **Sources:** (D-n) = 04-RESEARCH/04-CONTEXT decision. (U-x.y) = 02.2-UI-SPEC section. (P3-x.y) = 03-UI-SPEC section. (V) = checked in the repo or computed this session. (default) = choice made here, listed in section 17.
> **Fantasy:** the cockpit gets a radio. Friends' subs are other contacts on the sonar net. Joining is "calling" a host, the lobby is a crew roster, and a link that drops is a contact going silent.
> **Scope of new UI:** main menu entry, Play Online screen (name, port, host, join), connect dialog, lobby, start sync overlay and start countdown, in-match network states (link chip, player left), Leave Match overlay, HOST LEFT dialog, online results and the return to the lobby, Settings ONLINE section, F3 net rows.

---

## 1. Design System

| Property | Value |
|----------|-------|
| Tool | none (Godot project; shadcn does not apply). Registry gate: not applicable |
| Preset | not applicable |
| Component library | Unchanged: `Palette`, `UiKit` (`style_panel`, `make_button`, `draw_chip`, `draw_brackets`, `chamfer_points`, `register_fx`, `pop_in`, `FocusMarker`), `UiIcons`, `UiLayout.fill_rect`, `AbyssBackdrop`, `ScreenTransition`, `ConfirmDialog`. New screens and widgets go in `src/ui/online/` (D-24 structure) |
| New shared widgets | `SonarTextField` (`src/ui/online/sonar_text_field.gd`, section 4.1) and the `danger` chip variant in `UiKit.chip_style` (section 4.2). No other new component types |
| Icon library | `UiIcons` 24x24 vector glyphs, 2 px strokes. Phase 4 adds 6 glyphs (section 5). No emoji or Unicode arrows or check marks (the fonts lack them; P3 Pitfall 7) |
| Fonts | Unchanged: Oxanium 700 (Heading/Display), Share Tech Mono 400 (Label/Body; bold = embolden 0.5) |
| Shaders | None new (3-shader budget of U-1 unchanged) |
| Particles | None new |
| New gameplay render layers | Inserted into the P3-1 order after `VersusHud`: **`StartSyncOverlay`** > **`LeaveOverlay`** > `GogglesIntro` (unused online) > overlays (**`HostLeftDialog`** joins pause/fail/dialogs here) > `ScreenTransition`. The start countdown is a new state of the existing `EventBanner` (no new node). The link chip is a new chip in the existing `StatusChips` stack |

Every new node that animates calls `UiKit.register_fx(self)` and implements `apply_effect_settings()` and `effect_counts()` (project contract). The list is in section 14.

---

## 2. Spacing Scale

Unchanged tokens `Palette.SP_*` (U-2):

| Token | Value | Usage in this phase |
|-------|-------|---------------------|
| xs | 4px | Glyph-to-text gaps (host glyph, signal bars, "!" glyph), chip inner gaps |
| sm | 8px | Gap between stacked controls (pitch = height + 8), roster row gap |
| md | 16px | Panel inner gaps, tile gaps, field text inset, overlay padding |
| lg | 24px | Glass panel padding on Online, Lobby, dialogs |
| xl | 32px | Gap between the two screen panels; outer frame margin |
| 2xl | 48px | Field height, compact button height, segmented tile height, **main menu item height (new)** |
| 3xl | 64px | Screen-edge padding; row height on Online/Lobby; dialog button height |

Declared exceptions (all multiples of 4):
- **Main menu item height 48 and pitch 56** (was 56 / 64; section 7.1). Pitch = height + 8 (U-2 rule).
- Lobby roster rows 64 tall with a 72 pitch (section 9), lobby log line pitch 40, address list line pitch 40.
- Leave overlay height 152 (section 11.4) to cover exactly the alert slot plus the event banner band (y 120..272).
- Strokes (1, 2, 3, 4 px), the caret (2 px) and the signal bars (3 px) are strokes, not spacing (U-2 rule).

Edges, cuts and brackets: unchanged (U-2). Screens and dialogs use `CUT_MD`; fields, chips, tiles and in-game panels use `CUT_SM`.

---

## 3. Design Tokens

### 3.1 Colour (Palette only; zero new hues, zero new constants)

Phase 4 adds **no colour literal and no new Palette constant**. It reuses `PANEL_ALPHA` 0.82 for menus and dialogs and `HUD_GLASS_ALPHA` 0.92 for in-game overlays.

**60 / 30 / 10 (unchanged):** 60% `ABYSS_900` (screen backgrounds, arena), 30% glass and surfaces (`ABYSS_700` panels at 82% on menus / 92% in game, `ABYSS_800` field wells, `ABYSS_600` focused or "you" rows), 10% light (`SONAR` chrome, gold and red signals).

| Role | Token | Hex |
|------|-------|-----|
| Dominant (60%) | `ABYSS_900` | `#03060D` |
| Secondary (30%) | `ABYSS_700` at 82% (menus, lobby, dialogs) / 92% (in-game overlays); `ABYSS_800` (text field wells) | `#0A1A2E` / `#060D1A` |
| Accent (10%) | `SONAR` | `#05D9E8` |
| Destructive / error / network fault | `WARNING_RED` | `#FF4A3D` |
| Reward | `REWARD_GOLD` | `#FFD36B` |

**`SONAR` is reserved for (U-3.1 items 1-10, P3-3.1 items 11-16, plus):** (17) the edge of a focused or editing `SonarTextField`, (18) lit signal bars in the PING column, (19) the "this is you" 4 px bar on your lobby roster row and HOST LEFT standings row, (20) the Tailscale address row's 4 px bar, (21) section captions on the new screens ("YOUR SUB", "HOST", "JOIN", "MATCH", "INVITE", "CONNECT WITH FRIENDS", "HOW TO CONNECT", "LOBBY LOG", "SUBS IN THIS LOBBY {n}/4", "ALL SUBS LINKED"), (22) the start countdown progress line, (23) `info` chips "OK", "HOST", "TAILSCALE", "ONLINE", (24) the READY check glyph and word. Never body text.

**`SONAR_PALE` adds:** the text caret and editing edge of `SonarTextField`, the host's invite address string, the countdown headline "DIVE".

**`WARNING_RED` is reserved for (U-3.1, P3-3.1, plus):** connect error dialog chrome (`danger` panel), the `danger` chip (MISSING, CHANGED, NO HOST SIGNAL), a high-latency PING value with its "!" glyph, the rejected-character flash on a field, the HOST LEFT dialog chrome, the host's "Leaving ends the match for everyone." warning line, status-line errors with the "!" glyph (existing pattern). Never on a ready, OK or success state.

**`REWARD_GOLD` adds:** only the "1ST" place label in the HOST LEFT standings (same rule as P3 results). Gold never appears in the lobby or online screens otherwise. Gold stays outside the note-path keep-out (the HOST LEFT dialog is a modal overlay after the conductor stopped, like pause, so no note is drawn under it).

**No "yellow" warning hue exists.** The research's "yellow high latency note" (Latency Budget) is drawn as `WARNING_RED` value + "!" glyph + log line (Defaults Log 6).

### 3.2 Typography (unchanged: 4 sizes, 2 weights)

| Role | Font | Size | Weight | Line height | Phase 4 uses |
|------|------|------|--------|-------------|--------------|
| Label | Share Tech Mono | 20 | 400 | 1.5 | Captions, hints, chips, column heads, lobby log, status lines, address chip line, countdown caption, F3 rows |
| Body | Share Tech Mono | 28 | 400 (bold = embolden 0.5 for buttons) | 1.5 | Field values, row labels, roster names, ping values, buttons, dialog bodies, address list |
| Heading | Oxanium | 40 | 700 | 1.2 | Screen titles, dialog titles, countdown headline, Leave overlay title |
| Display | Oxanium | 96 | 700 | 1.0 | Not used by new elements |

Rules carried over: live numerals (ping, timers, countdown digits, port) use Share Tech Mono (monospace) or Oxanium (tabular) inside fixed boxes, so values never shift layout. Captions UPPERCASE with +2 px letter spacing. Player names are always shown UPPERCASE (D-20 upper-cases them at entry). The 01.2 Cinematic 176 exception is **not** used online (no goggles intro, D-07).

### 3.3 Motion (tokens unchanged, U-3.4)

| Token | New uses |
|-------|----------|
| `DUR_FAST` 120 ms | Field edge colour change, caret jump, Leave overlay in/out, signal bar change, chip re-pack |
| `DUR_BASE` 180 ms | Roster row in/out, ready check pop, lobby log line in, connect dialog stage cross-fade, sync overlay fade out, HOST LEFT panel in, link chip pop |
| `DUR_SLOW` 300 ms | Countdown banner fade out after "DIVE", sonar wipes (existing) |
| `DUR_MAX` 400 ms | Cap for every new transition |
| Loops | Caret blink 1.0 s period (0.5 on / 0.5 off); connect ping ring 1.0 s period. Both are static under Reduce motion |
| Song-clock driven | Countdown digits and its progress line follow `song_time` (negative during the lead-in), never frame time |

---

## 4. New Shared Widgets

### 4.1 `SonarTextField` (`src/ui/online/sonar_text_field.gd`, extends `Control`, wraps a `LineEdit`)

Used for player name, port and host address. One widget, three configurations:

| Config | Charset (filter on type and paste) | Case | Max length | Placeholder | Commit validation |
|--------|-----------------------------------|------|-----------|-------------|-------------------|
| `name` | `A-Z 0-9 space _ -` | upper-cased on entry | 12 | "DIVER" | Trim; empty -> revert to the previous value; collapse double spaces |
| `port` | `0-9` | n/a | 5 | "47474" | 1024..65535, else revert + status error (section 15) |
| `address` | `a-z A-Z 0-9 . - : [ ]` | kept as typed | 64 | "100.x.y.z or host name" | Trim; empty allowed (Join Match disabled) |

**Look (all three configs):**

| Part | Spec |
|------|------|
| Well | 48 tall, chamfer `CUT_SM` (TL/BR), fill `ABYSS_800` 100%. Width given by the row (section 8, 9, 12) |
| Edge idle | 2 px `SONAR` 45% (3.05:1 on glass, meets 3:1; the button-idle 30% edge measures 2.03:1, too faint for a field boundary) (V) |
| Edge focused (not editing) | 2 px `SONAR` 100% + row focus marker (U-4.3) |
| Edge editing | 2 px `SONAR_PALE` 100%; panel glow `SONAR` 28% on Full, none on Low |
| Value | Body 28 `TEXT_HI`, left inset 16 px, vertically centred. Placeholder Body 28 `TEXT_LO` (6.35:1 on `ABYSS_800`) (V) |
| Caret | 2 x 32 px `SONAR_PALE`, blinks 0.5 s on / 0.5 s off while editing. Reduce motion: steady |
| Counter | While editing, right-aligned 16 px inside the well: "{n}/{max}" Label 20 `TEXT_LO` (name and address only) |
| Overflow | Text longer than the well scrolls horizontally so the caret stays visible; when not editing the value is truncated with "..." |
| Rejected character | `error` blip (U-10.4) and the edge flashes `WARNING_RED` for 200 ms (Reduce motion: same, it is a colour change). The character is not inserted |

**Interaction contract (keyboard, gamepad, mouse):**

| State | Input | Effect |
|-------|-------|--------|
| Focused, not editing | Up / Down (D-pad) | Move focus (screen order) |
| Focused, not editing | Enter / A, or mouse click | Start editing, caret at the end, `confirm` blip |
| Editing | Typed characters | Insert at the caret (filtered by charset; name upper-cased) |
| Editing | Backspace / Delete | Delete before / after the caret |
| Editing | Left / Right (keys or D-pad) | Move the caret. Gamepad Right at the end of the text appends "A" (name), "0" (port) or "." (address) if below max length |
| Editing | D-pad Up / Down | Cycle the character at the caret through the charset in order (gamepad text entry); `move` blip |
| Editing | Gamepad X | Delete the character before the caret |
| Editing | Ctrl+V | Paste clipboard text, filtered and truncated to max length |
| Editing | Enter / A | Commit (validate), stop editing, `confirm` blip |
| Editing | Esc / B | Revert to the value before editing, stop editing, `back` blip. Esc never leaves the screen while a field is editing |
| Editing | Focus lost (mouse click elsewhere) | Commit |

Gamepad X (`JOY_BUTTON_X`) is unbound in every existing screen (V: project.godot input map binds A, B, Y, LB, RB, LT, RT, Start). The gamepad charset cycle order is: `A..Z`, `0..9`, space, `_`, `-` (name); `0..9` (port); `0..9`, `.`, `:`, `a..z`, `-`, `[`, `]` (address).

### 4.2 `danger` chip variant (`UiKit.chip_style("danger")`)

| Variant | Edge | Fill | Text | Used for |
|---------|------|------|------|----------|
| `danger` | `WARNING_RED` 100% | `ABYSS_700` 80% | `WARNING_RED` | SONG "MISSING" / "CHANGED" in the lobby, "NO HOST SIGNAL" in the in-match chip stack |

Contrast: `WARNING_RED` on the chip composite 5.29:1 (menu glass) (V). Same geometry as U-4.4 (32 tall, padding 12, `CUT_SM`, Label 20 UPPERCASE +1 px spacing).

---

## 5. New Glyphs (`UiIcons`, 24x24 grid, 2 px strokes)

`UiIcons.NAMES` gains:

| Name | Used for | Geometry (24 grid) |
|------|----------|--------------------|
| `online` | Main menu "Play Online" | Two filled dots r 3 at (4,17) and (20,17); two arcs centred (12,17): r 6 from 200 to 340 deg and r 11 from 205 to 335 deg (signal between two subs) |
| `host` | Host marker in the roster, results and HOST LEFT rows | Mast (12,9)->(12,21), base (7,21)->(17,21), filled dot r 2 at (12,8), arcs centred (12,8): r 5 and r 9 from 220 to 320 deg (broadcast) |
| `signal` | PING column | Four vertical bars 3 px wide, bottoms at y 20, x 4 / 9 / 14 / 19, heights 4 / 8 / 12 / 16. Drawn with a `lit` count 0..4: lit bars `SONAR` (or `WARNING_RED` when high latency), unlit `ABYSS_500` 70% |
| `link_broken` | Player left (periscope, killfeed, results, lobby log), connection lost | Two chain links: chamfered rects (2,9)-(11,15) and (13,9)-(22,15) outlines with a gap at x 11..13, plus a slash (10,20)->(14,4) |
| `copy` | "Copy Address" and "Paste" buttons | Two chamfered square outlines: (4,8)-(16,20) and (8,4)-(20,16), the front one filled `ABYSS_800` so the back one reads behind it |
| `warning` | Inline "!" on PING, start gate reasons, status errors (replaces the ad-hoc "!" text on new screens) | Triangle outline (12,3)(22,20)(2,20), filled bar (11,9)-(13,15), filled dot r 1.5 at (12,17.5) |

A test draws each new name without error and checks `names()` contains it.

---

## 6. Screen Flow

```
Main menu --"Play Online"--> PLAY ONLINE screen
   |-- Host Match --> (server opens) --> LOBBY (host)
   |-- Join Match --> Connect dialog: CONNECTING -> CHECKING VERSION -> SYNCING CLOCKS --> LOBBY (client)
   |                         \-> error state (Try Again / Back)
LOBBY --host Start Match--> sonar wipe --> GAMEPLAY (online)
   GAMEPLAY: StartSyncOverlay (LOADING / WAITING) --START--> countdown banner (DIVE IN 3/2/1, DIVE) --> song
             Esc / Start --> Leave overlay (non-pausing)
             host gone / no signal 4 s --> HOST LEFT dialog --> Main menu
             LOAD timeout / START late --> everyone back to LOBBY with a log line
   song end --> VERSUS RESULTS (online variant)
        host "Back to Lobby" --> everyone wipes to LOBBY (same roster, Ready cleared)
        host "Back to Menu" (confirm CLOSE LOBBY) --> clients get "The host closed the lobby." on PLAY ONLINE
        client "Leave Lobby" (confirm) --> PLAY ONLINE
```

All screen changes use the existing sonar wipe (U-9.7). Reduce motion: 160 ms cross-fade (existing).

---

## 7. Main Menu Entry (03 UI-SPEC 9.1 update)

### 7.1 Ten items, re-spaced

Ten items no longer fit at height 56 / pitch 64 above the description line (V: 392 + 9 x 64 + 56 = 1024 > description top ~976). New layout:

| Constant | Was | Now |
|----------|-----|-----|
| `ITEM_H` | 56 | **48** (the U-4.2 compact button height) |
| `ITEM_PITCH` | 64 | **56** (48 + 8) |
| `ITEM_TOP` | 392 | 392 (unchanged) |
| Item tops | 392..904 | 392, 448, 504, 560, 616, 672, 728, 784, 840, 896 (last ends **944**) |
| `DESC_BASELINE` / `STATUS_BASELINE` | 1000 / 1040 | unchanged |
| `Palette.STAGGER_MENU` | 35 ms | **30 ms** (9 gaps x 30 = 270 ms, inside the U-3.4 300 ms stagger cap) |
| Focus marker bar | height - 16 | 32 px (follows the rule) |
| Key hint box ("ENTER" on Start Dive) | 120 x 56 | 120 x 48 |

Logo (y 168..320), tagline (baseline 360), last-dive card (x 1376..1856, y 840..1000) and calibration prompt are unchanged. The last item ends 32 px above the description's ascent top (~976), so `test_menu_flow` "last item ends above the description" still holds.

| # | Item | Icon | Variant | Description (focus line) |
|---|------|------|---------|--------------------------|
| 1 | Start Dive | `dive` | primary | kept |
| 2 | Versus Bots | `versus` | default | kept |
| 3 | **Play Online** | `online` | default | "Host or join friends over Tailscale or LAN." |
| 4 | Solo Dive (No-Fail) | `lifebuoy` | default | kept |
| 5 | Chart a Song | `chart` | default | kept |
| 6 | Calibrate Sonar | `sonar` | default | kept |
| 7 | Settings | `sliders` | default | kept |
| 8 | Autoplay Dive (test) | `auto` | default | kept |
| 9 | Open Songs Folder | `folder` | default | kept |
| 10 | Quit Game | `power` | default | kept |

`MainMenu.menu_buttons()` returns 10 buttons in this order; `online_button` is the new member. Focus wraps top <-> bottom (kept). Accept on Play Online: sonar wipe to the Play Online screen. The new description is 43 characters (about 660 px at Body 28), inside `DESC_W` 760 (V).

Tests to update in the same plan: `test_menu_flow.gd` `MENU_TEXTS`, `MENU_ICONS`, `MENU_TOPS` (392 + 56 i), size (512, 48), `menu_buttons().size()` 10, `STAGGER_MENU` 0.030, `MENU_DESCRIPTIONS`.

---

## 8. Play Online Screen (`scenes/online_menu.tscn`, `src/ui/online/online_menu.gd`) (NET-01, NET-07, D-14, D-15, D-20)

Background `AbyssBackdrop` `table`. Same two-panel frame as match setup (P3-9.2).

| Region | Rect / position | Content |
|--------|-----------------|---------|
| Title | (64, 104) baseline | "PLAY ONLINE" Heading 40 `TEXT_HI` |
| Subtitle | (64, 140) baseline | "Host a match or join a friend. 2 to 4 subs, same song, same game version." Label 20 `TEXT_MID` |
| Left panel | x 64..944, y 176..904 (glass, U-4.1) | Rows below |
| Caption | (96, 216) | "YOUR SUB" Label 20 `SONAR` |
| Row 0 Name | x 96..912, y 240..304 (64 tall, button look like match setup rows) | Label "Name" Body 28 `TEXT_MID` at x 120; `SonarTextField` `name` well x 400..896, y 248..296 |
| Row 1 Port | y 312..376 | Label "Port" at x 120; `SonarTextField` `port` well x 400..560 (160 wide), y 320..368 |
| Row hint | x 120, baseline 408 | Label 20 `TEXT_LO`, follows focus: Name: "Shown to friends. Up to 12 letters, digits, spaces, _ or -." Port: "UDP port. Host and friends must use the same number. Default 47474." Other rows: empty |
| Divider | y 432, x 96..912 | 2 px `SONAR` 35% |
| Caption | (96, 472) | "HOST" Label 20 `SONAR` |
| Host line | x 120, baseline 504 | "Open a lobby on this PC. Friends join with your address." Label 20 `TEXT_MID` |
| Row 2 Host Match | x 96..912, y 520..584 | Button 64, **primary** variant, icon `host`, key hint "ENTER" |
| Divider | y 608 | 2 px `SONAR` 35% |
| Caption | (96, 648) | "JOIN" Label 20 `SONAR` |
| Row 3 Address | x 96..912, y 664..728 | Label "Address" at x 120; `SonarTextField` `address` well x 400..896, y 672..720. Prefilled with `Settings.net_last_address` |
| Row 4 buttons | y 744..808 | "Paste" x 96..296 (200 wide, default, icon `copy`); "Join Match" x 312..912 (default, icon `online`). Join Match is disabled (U-4.2 disabled) while the address is empty |
| Join line | x 120, baseline 848 | Label 20 `TEXT_LO`: "Ask the host for their address. Tailscale addresses start with 100." |
| Right panel | x 976..1856, y 176..904 (glass) | Section 8.1 |
| Hint | (64, 960) | Keys: "UP DOWN MOVE  ·  ENTER SELECT OR EDIT  ·  CTRL+V PASTE  ·  ESC BACK"; gamepad: "D-PAD MOVE  ·  A SELECT OR EDIT  ·  X DELETE  ·  B BACK". While a field is editing: "TYPE TO EDIT  ·  ENTER DONE  ·  ESC UNDO" / "D-PAD UP DOWN LETTER  ·  LEFT RIGHT MOVE  ·  X DELETE  ·  A DONE  ·  B UNDO" |
| Status line | (64, 1000), max 1180 px | Label 20; prompts `TEXT_MID`, errors `WARNING_RED` with the `warning` glyph 16 px at the left (main menu pattern) |
| Version | right-aligned x 1856, baseline 1040 | "VERSION {v}" Label 20 `TEXT_LO` (`application/config/version`; matches the D-21 handshake so friends can compare builds) |

### 8.1 Right panel: connect with friends

| Item | Position | Spec |
|------|----------|------|
| Caption | (1008, 216) | "CONNECT WITH FRIENDS" Label 20 `SONAR` |
| Sub-caption | (1008, 256) | "THIS PC'S ADDRESSES" Label 20 `TEXT_LO` |
| Address rows | up to 4, rows 40 tall at y 272, 312, 352, 392 (x 1008..1824) | Address Body 28 at x 1032, baseline row top + 30. Order: Tailscale (`100.64.0.0/10`) first, then private LAN (10/8, 172.16/12, 192.168/16), then others. Loopback and link-local (169.254/16) are never listed |
| Tailscale row | | Fill `ABYSS_600` 92% + 4 px `SONAR` bar on the left edge (the "this one" language of P3). Address `SONAR_PALE`. `info` chip "TAILSCALE" right-aligned to x 1808 |
| LAN row | | No fill. Address `TEXT_MID`. `muted` chip "LAN" right-aligned to x 1808 |
| Under the list | x 1008, baseline 464 | Tailscale present: "Give the Tailscale address to friends." Label 20 `TEXT_MID`. None: "No Tailscale address. Friends outside your home network need Tailscale." Label 20 `TEXT_LO`. No address at all: "No network address found. Check that this PC is online." Label 20 `WARNING_RED` + `warning` glyph |
| Divider | y 488, x 1008..1824 | 2 px `SONAR` 35% |
| Caption | (1008, 528) | "HOW TO CONNECT" Label 20 `SONAR` |
| Steps | x 1008, baselines 568 / 608 / 648 / 688 | Label 20 `TEXT_MID`, copy in section 15 (numbered "1." .. "4."; the port number is read from the Port field) |
| Guide | x 1008, baseline 736 | "Full guide: ONLINE_SETUP.md in the game folder." Label 20 `TEXT_LO` |
| Firewall | x 1008, baseline 776 | "First time hosting? Click Allow when Windows Firewall asks." Label 20 `TEXT_LO` |

Address rows are read-only (not focusable). The list refreshes when the screen opens and every 5 s while it is open (Tailscale may connect after launch).

### 8.2 Focus order and behaviour

**Order (Up/Down, wraps):** Name -> Port -> Host Match -> Address -> (Paste | Join Match) -> Name. On row 4, Left/Right moves between Paste and Join Match; Up from either goes to Address; Down from either wraps to Name. A disabled Join Match is skipped (Paste keeps focus).

**Initial focus:**
1. First visit (`Settings.player_name_set` false): Name field, already **editing**, value "DIVER" selected; status line prompt "Pick a name your friends will see, then press Enter." (`TEXT_MID`). Committing sets `player_name_set` (D-20 "asked once").
2. Otherwise: Join Match when a saved address exists, else Host Match.

**Accept actions:**
- Host Match: open the server on the Port value (D-01). Success: sonar wipe to the Lobby (host). Failure: status-line error (section 15), focus stays.
- Paste: read the clipboard into Address (filtered, truncated), `confirm` blip; empty or fully filtered clipboard: `error` blip, status "Clipboard has no address to paste.".
- Join Match: save address and port to Settings, then open the Connect dialog (8.3).
- Esc / B (no field editing): sonar wipe back to the main menu (no confirm; nothing is lost).

Status messages that arrive from elsewhere (kicked, lobby closed, lost connection in the lobby) are shown on the status line when this screen opens, and focus starts on Join Match.

### 8.3 Connect dialog (`src/ui/online/connect_dialog.gd`) (D-21, D-06, Pitfall 9)

Same geometry as `ConfirmDialog` (U-9.6): backdrop `ABYSS_900` 70%; panel x 600..1320, y 380..700 with the opaque `ABYSS_900` 94% backing; title Heading 40 at (632, 444) baseline; divider y 460; body Body 28 `TEXT_MID` wrapping in 656 px from baseline 500; buttons 304 x 64 at y 604 (x 632 and x 984).

| Part | Spec |
|------|------|
| Progress chrome | Default glass (`style_panel()` default), brackets `SONAR` 80% |
| Ping ring | Centre (1272, 428), 2 px `SONAR`: r 8 -> 28 and alpha 1 -> 0 over 1.0 s, repeating (Full and Low). Reduce motion: static ring r 20 at alpha 0.6 |
| Elapsed | Right-aligned x 1288, baseline 568: "{n} S" Label 20 `TEXT_LO` (whole seconds since Join) |
| Progress button | One button "Cancel" at x 984 (safe slot), default variant, focused. Cancel / Esc / B: disconnect, close the dialog, focus back on Join Match |
| Error chrome | `danger` panel variant, brackets `WARNING_RED` 80%, divider `WARNING_RED` 35%; ping ring hidden |
| Error buttons | "Try Again" at x 632 (primary variant, initial focus), "Back" at x 984 (default). Esc / B = Back |

**Stages (cross-fade `DUR_BASE` between them; Reduce motion: instant swap):**

| Stage | Title | Body | Ends when |
|-------|-------|------|-----------|
| 1 | "CONNECTING" | "Calling {address}:{port}. This can take a few seconds." | ENet connected (else error after 8 s) |
| 2 | "CHECKING VERSION" | "Connected. Checking that you both run the same game build." | Auth accepted (else refusal error; `auth_timeout` 3 s) |
| 3 | "SYNCING CLOCKS" | "Lining up your clock with {HOST}'s for a synced start." | 16-ping burst done (about 1 s), then sonar wipe to the Lobby |

Error copy is in section 15. IPv6 addresses are shown in brackets: "[{address}]:{port}".

---

## 9. Lobby Screen (`scenes/lobby.tscn`, `src/ui/online/lobby_screen.gd`) (NET-01, NET-02, D-08, D-11, D-12, D-15)

Background `AbyssBackdrop` `table`. Two panels like match setup. The host and clients see the same layout; host-only controls are read-only text for clients.

| Region | Rect / position | Content |
|--------|-----------------|---------|
| Title | (64, 104) | "LOBBY" Heading 40 `TEXT_HI`; for the host an `info` chip "HOST" 16 px after the title (chip y 76..108) |
| Subtitle | (64, 140) | Host: "You are hosting. Friends join with {address}:{port}." Client: "Connected to {HOST}'s lobby." Label 20 `TEXT_MID` ({address} = the Tailscale address if any, else the first LAN address) |
| Left panel | x 64..944, y 176..904 (glass) | Match settings, invite, start/ready |
| Right panel | x 976..1856, y 176..904 (glass) | Roster and lobby log |
| Hint | (64, 960) | Host keys: "UP DOWN MOVE  ·  LEFT RIGHT CHANGE  ·  ENTER SELECT  ·  ESC CLOSE LOBBY"; host pad: "D-PAD MOVE  ·  LEFT RIGHT CHANGE  ·  A SELECT  ·  B CLOSE LOBBY". Client keys: "ENTER READY  ·  ESC LEAVE LOBBY"; client pad: "A READY  ·  B LEAVE LOBBY" |
| Status line | (64, 1000) | Label 20, errors `WARNING_RED` + `warning` glyph (e.g. song failed to load) |

### 9.1 Left panel: match

| Item | Rect / position | Host | Client |
|------|-----------------|------|--------|
| Caption | (96, 216) | "MATCH" Label 20 `SONAR` | same |
| Row Song | x 96..912, y 240..304 | Label "Song" Body 28 `TEXT_MID` at x 120; value "{title} · {artist}" Body 28 `TEXT_HI` at x 400, truncated at 456 px; `chevron_right` at x 872. Accept opens Song Select pick mode (9.4). No song: "Choose a song" `TEXT_LO` | Same text, no chevron, not focusable. No song: "Host is choosing a song" `TEXT_LO` |
| Row Difficulty | y 312..376 | Label "Difficulty"; `difficulty` chip at x 400; `chevron_left` / `chevron_right` at x 368 / 872. Left/Right cycles the difficulties the song has | Chip only |
| Row Torpedo flight | y 384..448 | Label "Torpedo flight"; segmented selector, 2 tiles 208 x 48 at x 400 and x 624 (y 392..440): "2 BEATS", "1 BEAT LAN" (Label 20). Selected tile style = P3-9.2 (fill `ABYSS_600` 92%, 2 px `SONAR` edge, 24 x 4 `SONAR` bar under it) | Selected tile shown, other tile at 50% alpha, not focusable |
| Flight description | x 120, baseline 488 | Label 20 `TEXT_MID`: 2 beats "Torpedoes fly 2 beats. Safe for internet play." 1 beat "Torpedoes fly 1 beat. For same-room LAN only; warnings get shorter online." | same |
| Divider | y 520 | 2 px `SONAR` 35% | same |
| Caption | (96, 560) | "INVITE" Label 20 `SONAR` | "CONNECTION" Label 20 `SONAR` |
| Invite address | x 120, baseline 604 | "{address}:{port}" Body 28 `SONAR_PALE` (max 560 px) | "HOST {HOST}" Body 28 `TEXT_HI` |
| Second line | x 120, baseline 636 | Label 20 `TEXT_LO`: "Tailscale address. Friends on your LAN can use {lan}." / "LAN address. Friends outside your network need Tailscale." | Label 20 `TEXT_MID`: "PING {n} MS · CLOCK SYNCED" (or "PING -- MS · SYNCING CLOCK") |
| Row Copy Address | x 96..416, y 656..704 (compact 48) | Button "Copy Address", icon `copy`. Accept copies "{address}:{port}" to the clipboard; the button text reads "Copied" for 1600 ms (`confirm` blip) | Not shown |
| Gate reason | x 120, baseline 784, max 792 px | Label 20 (copy 15): `TEXT_LO` while blocked, `TEXT_MID` when startable. Blocked reasons with a person in them (missing song, high latency) carry the `warning` glyph | Client reason line (copy 15) |
| Primary button | x 96..912, y 808..872 (64) | "Start Match" primary, key hint "ENTER". Disabled (U-4.2) until the start gate passes | "Ready Up" (not ready) / "Cancel Ready" (ready, icon `check`), primary. Disabled while your SONG is not OK |

**Start gate (host, D-12), checked in this order; the first failing rule is the reason line:**
1. At least 2 subs present.
2. A song is chosen.
3. Every present sub's clock sync is done (5 or more samples, D-06).
4. Every present sub's SONG is OK.
5. Every client is Ready (the host is implicitly ready; Defaults Log 3).

A song or difficulty change clears every Ready (D-12) and adds a log line. A flight change does not clear Ready (it is not a song change), but it is logged.

### 9.2 Right panel: roster

| Item | Rect / position | Spec |
|------|-----------------|------|
| Caption | (1008, 216) | "SUBS IN THIS LOBBY {n}/4" Label 20 `SONAR` |
| Column heads | baseline 256 | Label 20 `TEXT_LO`: "NAME" x 1032, "PING" right-aligned x 1440, "SONG" x 1480, "READY" x 1664 |
| Rows | 4 rows, x 1008..1824, 64 tall, tops 272 / 344 / 416 / 488 (pitch 72) | Seat order (host = seat 0 first, then clients in join order, D-12) |

**Row content (row top = yr):**

| Column | Spec |
|--------|------|
| Row chrome | Your row: fill `ABYSS_600` 92% + 4 px `SONAR` bar on the left edge. Other rows: no fill, 1 px `SONAR` 20% divider below. Host-focused row (kick target): button focus style (U-4.2 focus) + focus marker |
| Host glyph | `host` 20 px at x 1008+12, centred on the row, `SONAR`, host row only |
| Name | Body 28 `TEXT_HI` at x 1032, baseline yr + 42, max 240 px (12 characters fit, V: 12 x ~15.4 px). De-duplicated names from the host (D-20: "DIVER2") |
| Ping | `signal` glyph 20 px at x 1320 + value Body 28 right-aligned at x 1440: "{n} MS" (round-trip, from the host's samples, refreshed at 1 Hz). Lit bars: <= 60 ms 4, <= 120 ms 3, <= 200 ms 2, else 1. Host row: "-" `TEXT_LO`, no glyph. Before 5 samples: "SYNC" `TEXT_LO`, glyph with 0 lit. High latency (`D + L + F > 250 ms`, research Latency Budget): value `WARNING_RED`, bars `WARNING_RED`, `warning` glyph 16 px at x 1296 |
| Song | Chip at x 1480: "OK" `info`; "MISSING" `danger` (no library entry with the fingerprint); "CHANGED" `danger` (fingerprint found but `versus_sig` differs, D-11); "CHECKING" `muted` (result not back yet); "NO SONG" `muted` (host has not picked) |
| Ready | At x 1664: ready = `check` glyph 20 px `SONAR` + "READY" Label 20 `SONAR`; not ready = "WAITING" Label 20 `TEXT_LO`; host row = "HOST" Label 20 `TEXT_MID` (implicitly ready) |
| Kick hint | Host only, on the focused client row: "ENTER KICK" / "A KICK" Label 20 `TEXT_LO` right-aligned at x 1808 replacing nothing (READY column ends by x ~1760) |
| Open seat | Row with 1 px dashed `TEXT_LO` 35% outline (12 px dash, 8 px gap), "OPEN SEAT" Label 20 `TEXT_LO` at x 1032 (baseline yr + 40), "Waiting for a friend to join." Label 20 `TEXT_LO` at x 1312 |

Row in (join): fade in + slide 16 px from the right, `DUR_BASE`. Row out (leave/kick): fade `DUR_BASE`, then rows below close up over `DUR_FAST`. Ready change: the check pops (`UiKit.pop_in`). Reduce motion: fades only, rows jump.

### 9.3 Lobby log

| Item | Position | Spec |
|------|----------|------|
| Divider | y 576, x 1008..1824 | 2 px `SONAR` 35% |
| Caption | (1008, 616) | "LOBBY LOG" Label 20 `SONAR` |
| Lines | x 1008, baselines 656 / 696 / 736 / 776 / 816 / 856, max 816 px | Label 20 `TEXT_MID`; newest at the bottom; a 7th line scrolls the oldest out (fade `DUR_FAST`). Lines naming a fault (missing song, load timeout, late start, high latency, kick) carry the `warning` glyph and use `TEXT_HI`. New line fades in `DUR_BASE` (all modes) |

The log is local to the screen session and is rebuilt (empty) on each lobby entry except for the return messages in section 13.

### 9.4 Song pick mode (host)

P3-9.3 pick mode, with the header chip `info` "ONLINE" instead of "VERSUS". Accept "Pick Song" returns to the Lobby with the song set; Esc / B returns without a change. While the host is in Song Select the lobby stays connected (NetSession is an autoload) and clients see the log line "Host is choosing a song.".

### 9.5 Focus order and behaviour

**Host (Up/Down, wraps):** Song -> Difficulty -> Torpedo flight -> Copy Address -> Start Match -> client roster rows (occupied only, seat order) -> Song. Left/Right changes the value on Difficulty and Torpedo flight (`move` blip); elsewhere it does nothing. A disabled Start Match is still focusable so the reason line is read next to it (Accept on it plays `error`). Initial focus: Start Match when a song is set, else Song.

**Client:** only the Ready button is focusable (initial focus). Accept toggles Ready (`confirm` blip). Up/Down do nothing.

**Kick (host):** Accept on a client row opens a `ConfirmDialog`: "REMOVE {NAME}" / "Remove {NAME} from the lobby? They can join again." / "Remove" / "Keep". Initial focus on Keep.

**Esc / B:** host opens "CLOSE LOBBY" confirm; client opens "LEAVE LOBBY" confirm (copy 15). Confirmed: disconnect and sonar wipe to the Play Online screen.

**Lobby lock (D-12):** from LOAD until back in the lobby, joins are refused with "MATCH IN PROGRESS" (8.3).

---

## 10. Starting the Match (D-07)

### 10.1 Launch

Host Accept on Start Match: `confirm` blip, every peer sonar-wipes to gameplay at once (LOAD). Online gameplay always uses `IntroTimeline.Mode.NONE` (no goggles intro, no "3 2 1" cinematic numerals).

### 10.2 Start sync overlay (`src/ui/online/start_sync_overlay.gd`, gameplay layer) (D-07)

Shown from scene entry until START is received and the lead-in is scheduled. The conductor has not begun, so no notes are on the board; this is the only time an in-game element may sit inside the note-path keep-out (declared exception, test in section 16).

| Part | Spec |
|------|------|
| Panel | x 600..1320, y 340..740 (720 x 400), glass at `HUD_GLASS_ALPHA`, `CUT_MD`, brackets `SONAR` 80%. No backdrop dim (the idle arena stays visible) |
| Title | Heading 40 `TEXT_HI` at (632, 404) baseline: "LOADING SONG" while this PC builds the chart, then "LINKING SUBS" |
| Divider | y 420, x 632..1288, 2 px `SONAR` 35% |
| Body | Body 28 `TEXT_MID` at (632, 468): "Waiting for {n} of {m} subs to load." (n = not yet LOADED); when everyone is loaded: "All loaded. Waiting for the start signal." |
| Roster lines | 4 lines, baselines 516 / 556 / 596 / 636: name Label 20 `TEXT_HI` at x 632 (your line "YOU"); status right-aligned x 1288: "LOADED" `SONAR` with `check` glyph 16 px left of it, or "LOADING" `TEXT_LO` |
| Hint | (632, 708) baseline | "ESC LEAVE MATCH" / "START LEAVE MATCH" Label 20 `TEXT_LO` |
| Exit | On START: fade out over `DUR_BASE` (all modes), then freed. The countdown banner (10.3) appears in the same frame |

Failure paths (host decides, everyone returns to the Lobby by sonar wipe; the reason appears as a lobby log line, copy 15): LOAD timeout 15 s; a client reported START_LATE (lead-in < 0.5 s); the song failed to load on a peer.

### 10.3 Start countdown (new `EventBanner` state "MATCH START") (D-07, NET-03)

Uses the event banner rect x 640..1280, y 200..272 and its chrome (P3-6.4). Highest priority while `song_time < 0`; it is never shown after song_time 0 + 900 ms.

| Part | Spec |
|------|------|
| Chrome | Glass at 92%, brackets `SONAR` 80% |
| Caption | "ALL SUBS LINKED" Label 20 `SONAR`, centred x 960, baseline 224 |
| Headline | Heading 40, centred x 960, baseline 262: "DIVE IN 3", "DIVE IN 2", "DIVE IN 1" (`TEXT_HI`), digit = `ceil(-song_time)` clamped 1..3; at song_time >= 0: "DIVE" `SONAR_PALE` |
| Right caption | "FLIGHT {n} BEATS" ("FLIGHT 1 BEAT") Label 20 `TEXT_MID`, right-aligned x 1264, baseline 224 |
| Progress line | 2 px `SONAR` across the banner bottom (y 270..272), drains right to left from the START receipt to song_time 0 |
| Timing | In: fade + slide down 24 px over `DUR_BASE` (P3 banner motion). Digit change: cross-fade `DUR_FAST`. "DIVE" holds 600 ms, then fades over `DUR_SLOW` |
| Reduce motion | Fade in only; digits swap without cross-fade |
| Low effects | No panel glow |

Periscope panels fade in (P3-6.2 entrance) when the banner appears. Lane input is enabled at `conductor.begin` (existing `_begin_count_in` contract). The digits follow song time, so every PC shows "DIVE" within the sync error (target <= 20 ms, D-24).

---

## 11. In-Match Network UI

All Phase 3 in-match views are unchanged; they read events from the channel (D-03, D-13). Online differences:

### 11.1 Names and seats

- Rival callsigns are player names (D-20). The local seat is still "YOU" everywhere offline shows "YOU" (killfeed, alert slot FROM, results).
- Periscope panels fill top-down in seat order, skipping your own seat (P3-6.2 rule). Truncation is the existing measured truncation with "..." (a 12-character name may show 9-10 characters on a panel; the full name is in the lobby and results).
- PLACE chip "OF {n}" uses the number of subs in the match.

### 11.2 Fire refusal (D-13)

Online, the SHIELDED / NO TARGET refusal (P3-5.2: caption swap 800 ms + `error` blip) is driven by `FIRE_REFUSED{seat == me}` instead of a return code. The visual is identical; it simply appears one round trip later.

### 11.3 Player left (D-16, NET-05)

When `PLAYER_LEFT{seat}` arrives:

| View | Change |
|------|--------|
| Periscope panel of that seat | Like the P3 wreck state, with a different word: hull bar replaced by "LEFT" Label 20 `TEXT_LO` at baseline y0+52 with `link_broken` glyph 16 px `TEXT_LO` left of it. Status line "DISCONNECTED" `TEXT_LO`. Panel edge `TEXT_LO` 35%, brackets `TEXT_LO` 50%. Held reward and tube meter hidden. Place freezes |
| Killfeed | Line `[link_broken] {A} left the match` (`TEXT_MID`, no bar; `link_broken` glyph `TEXT_MID`). The `IMPLODED` line for the same seat produced by the same disconnect (`on_failed`) is **replaced in place** by this line if PLAYER_LEFT arrives within 1.0 s of it, so the feed never shows both |
| Target | If that seat was your locked target, the existing target rules re-resolve it (no new UI) |
| Results | Row status "LEFT AT {m:ss}" `TEXT_LO` (instead of "IMPLODED AT"), `link_broken` glyph 16 px before it |

### 11.4 Leave Match overlay (`src/ui/online/leave_overlay.gd`) (D-18)

Esc (keyboard) or Start (gamepad) in an online match opens this overlay. **The conductor keeps running and lane input stays live behind it.** It does not dim the screen.

| Part | Spec |
|------|------|
| Rect | x 640..1280, y 120..272 (640 x 152): covers the alert slot and event banner band, entirely above the note-path keep-out (top edge y 348). While open, the alert slot and event banner keep updating underneath and reappear on close; edge flash and warhead rings still telegraph threats |
| Chrome | `danger` variant at `HUD_GLASS_ALPHA` 92% (edge `WARNING_RED` 60%, brackets `WARNING_RED` 80%), `CUT_SM` |
| Title | "LEAVE MATCH?" Heading 40 `TEXT_HI` at x 656, baseline 168 |
| Ping readout (clients) | "PING {n} MS" Label 20 `TEXT_LO`, right-aligned x 1264, baseline 160 |
| Body | Label 20 at x 656, baseline 196, max 608 px. Client: "The song keeps playing. Leaving makes your sub a wreck." `TEXT_MID`. Host: "You are the host. Leaving ends the match for everyone." `WARNING_RED` |
| Buttons | 48 tall (compact), y 208..256: "Leave Match" destructive variant x 656..952; "Stay" default x 968..1264. **Initial focus: Stay** |
| In / out | Fade + slide down 16 px over `DUR_FAST`; out: fade `DUR_FAST`. Reduce motion: fade only |

**Input while open:** `ui_left` / `ui_right` move focus between the two buttons; `ui_accept` (Enter, Space, A) activates the focused button; `ui_cancel` (Esc, B) or Start = Stay. These presses are consumed by the overlay: Space and gamepad A do **not** fire a torpedo while the overlay is open (Defaults Log 9). Lane keys (1-4, LB/LT/RT/RB by default) and target cycle (H / Y) are not consumed and keep playing.

**Confirmed Leave Match:** client: disconnect (the host eliminates the seat, D-16), sonar wipe to the main menu. Host: MATCH_ABORT (D-17), close, sonar wipe to the main menu. No second confirm (the overlay is the confirm).

The overlay also opens during the start sync overlay and the countdown (same behaviour).

### 11.5 Link chip (clients only) (D-17 watchdog)

A new chip in the P3-5.3 right-console stack, **slot priority 0 (top)**:

| State | Chip | Shown when |
|-------|------|------------|
| Healthy | hidden | a packet from the host arrived in the last 1.0 s |
| Weak | `danger` "NO HOST SIGNAL" | no packet from the host for >= 1.0 s; hides (fade `DUR_BASE`) as soon as packets resume |
| Lost | (chip replaced by the HOST LEFT dialog in its "CONNECTION LOST" form, 11.6) | 4 s without a packet (watchdog), or `server_disconnected` |

Overflow rule: the stack still has 6 slots (y 824..1056). If the link chip would make a 7th visible chip, the lowest-priority chips hide first: BALLAST, then IMMUNE. `Hud.chip_rects()` and `keepout_shapes()` include the link chip. Pop in/out as P3 chips.

The host has no link chip. Late landings, RTT, horizon and skew are **not** shown to players in the HUD; they are F3 debug rows (section 11.8).

### 11.6 HOST LEFT dialog (`src/ui/online/host_left_dialog.gd`) (D-17, NET-06)

Shown on clients on `MATCH_ABORT`, on `server_disconnected`, or after the 4 s watchdog. The conductor is stopped first (audio stops), lane input disabled.

| Part | Rect / position | Spec |
|------|-----------------|------|
| Backdrop | full screen | `ABYSS_900` 85% (the pause backdrop) |
| Panel | x 480..1440, y 240..840 (960 x 600) | `danger` variant at 82% over the opaque `ABYSS_900` 94% backing (ConfirmDialog pattern), `CUT_MD` |
| Title | (512, 304) baseline | Heading 40 `TEXT_HI`: "HOST LEFT" (MATCH_ABORT received) or "CONNECTION LOST" (watchdog or socket drop without MATCH_ABORT) |
| Divider | y 320, x 512..1408 | 2 px `WARNING_RED` 35% |
| Body | x 512, from baseline 368, wraps in 896 px | Body 28 `TEXT_MID` (copy 15) |
| Caption | (512, 440) | "LAST KNOWN STANDINGS" Label 20 `TEXT_LO` |
| Rows | 4 rows, x 512..1408, 56 tall, tops 456 / 520 / 584 / 648 | Place Body 28 at x 528 ("1ST" `REWARD_GOLD`, others `TEXT_HI`); name Body 28 `TEXT_HI` at x 624 (your row "YOU", fill `ABYSS_600` 92% + 4 px `SONAR` bar); `host` glyph 20 px after the host's name; status Label 20 right-aligned x 1392: "HULL {h}%" `TEXT_MID` / "WRECK" `WARNING_RED` / "LEFT" `TEXT_LO`. Order = last STATUS standings received |
| Button | x 512..912, y 744..808 | "Back to Menu" primary, focused. Accept, Esc or B: sonar wipe to the main menu |
| Hint | right-aligned x 1408, baseline 784 | "ENTER BACK TO MENU" / "A BACK TO MENU" Label 20 `TEXT_LO` |
| Motion | | Panel fades in and rises 16 px over `DUR_BASE`. Reduce motion: fade only. Low effects: no panel glow |

Nothing is saved (versus never writes records, P3 D-23).

### 11.7 End of song (D-19)

After the local song ends, show the standard end hold. If results have not arrived when the hold ends, the HUD shows a centred line in the section-banner slot (event banner rect, glass): caption "MATCH COMPLETE" Label 20 `SONAR`, headline "WAITING FOR RESULTS" Heading 40 `TEXT_HI`, right caption "{n} SUBS STILL DIVING" Label 20 `TEXT_MID` (n from DONE messages; host side) or empty (clients). On RESULTS: sonar wipe to the online results.

### 11.8 F3 net rows (`src/ui/online/net_debug_rows.gd`, inside `DebugOverlay`; debug overlay is colour-allow-listed)

Appended under the existing F3 text, Label 20 `TEXT_MID`, one line each (panel height grows from 420 to 580 to fit):

```
NET {HOST|CLIENT}  SEAT {k}  PEERS {n}
RTT P50 {a} MS  P90 {b} MS  OFFSET {c} US
HORIZON D {d} MS  LATE INPUTS {e}
SKEW {f} MS  LANDED LATE LAST {g} / MAX {h} MS
REJECTED PACKETS {i}  EVENT SEQ {j}
```

Host shows per-peer RTT on line 2 as "RTT {name} {p90} MS" for each peer, up to 3, separated by two spaces. Not shown in release builds (existing rule).

---

## 12. Online Results and Return to Lobby (P3-9.4 variant) (D-19)

Same screen and layout as P3-9.4 with these differences:

| Element | Online |
|---------|--------|
| Names | Player names; your row "YOU" (P3 language unchanged). `host` glyph 20 px after the host's name in the Sub column |
| Status column | Adds "LEFT AT {m:ss}" `TEXT_LO` with `link_broken` glyph (11.3) |
| Header chips | `muted` "NOT RECORDED" kept; adds `info` chip "ONLINE" 8 px left of it |
| Buttons (host) | "Back to Lobby" primary x 96..496 (initial focus); "Back to Menu" x 520..920. Back to Menu opens the "CLOSE LOBBY" confirm (copy 15) |
| Buttons (client) | "Leave Lobby" x 96..496 (default variant, initial focus). Waiting line Label 20 `TEXT_MID` at x 520, baseline 792: "Waiting for {HOST} to return to the lobby." |
| Hint | Host: "ENTER SELECT  ·  ESC BACK TO LOBBY" / "A SELECT  ·  B BACK TO LOBBY". Client: "ESC LEAVE LOBBY" / "B LEAVE LOBBY" |
| Esc / B | Host = Back to Lobby. Client = "LEAVE LOBBY" confirm |
| Host chose Back to Lobby | Every client sonar-wipes to the Lobby automatically (same roster, every Ready cleared, same song and difficulty kept; research Open Question 3) |
| Host closed the lobby | Clients' waiting line becomes "The host closed the lobby." `TEXT_MID`; their button text becomes "Back to Menu"; Accept goes to the main menu |
| Rematch / Change Match | Not shown online (the lobby is the rematch path) |

---

## 13. Settings: ONLINE Section (D-20, D-15)

A new glass section **ONLINE** after AUDIO (before LIBRARY), same U-9.3 row style (rows 56 tall, label Body 28 `TEXT_MID` at x 96, controls from x 440).

| Row | Control | Hint (Label 20 `TEXT_LO`) |
|-----|---------|---------------------------|
| Player name | `SonarTextField` `name`, well x 440..952 (512 wide), 48 tall | "Shown to friends in online matches. Up to 12 letters, digits, spaces, _ or -." |
| Online port | `SonarTextField` `port`, well x 440..600 | "UDP port used to host and join. Default 47474." |

Focus joins the existing Settings Up/Down order between Audio and Library. Editing follows 4.1 (Esc while editing reverts and stays in Settings). Values save through `Settings` (`player_name`, `player_name_set`, `net_last_port`); load validation clamps length, charset and port range like existing keys.


---

## 14. Low Effects and Reduce Motion (additions to U-11 and P3-12)

Each node below registers via `UiKit.register_fx` and reports `effect_counts()`. `test_effect_settings.gd` enumerates them.

| Node / effect | Full | Low effects | Reduce motion |
|---------------|------|-------------|---------------|
| `SonarTextField` caret blink | blink 1.0 s | blink | steady caret |
| `SonarTextField` editing glow | panel glow 28% | none | static glow 28% |
| `SonarTextField` reject flash | red edge 200 ms | same | same (colour only) |
| `ConnectDialog` ping ring | expanding ring | expanding ring | static ring r 20, alpha 0.6 |
| `ConnectDialog` stage cross-fade | `DUR_BASE` | same | instant |
| Lobby roster row in/out | fade + slide 16 | same | fade; rows jump |
| Lobby ready check pop | pop | pop | fade |
| Lobby log line in | fade | fade | fade |
| "Copied" button text | swap + `confirm` blip | same | same |
| `StartSyncOverlay` | fade out `DUR_BASE` | same | same |
| `EventBanner` MATCH START | slide + fade, digit cross-fade | no glow | fade in, digit swap |
| `LeaveOverlay` | slide + fade | slide + fade | fade |
| Link chip | pop / fade | same | fade |
| `HostLeftDialog` | rise + fade, panel glow | rise + fade, no glow | fade |
| Periscope LEFT transition | as P3 wreck | as P3 wreck | as P3 wreck |
| Sonar wipes (new screens) | existing | existing | existing 160 ms cross-fade |

Performance: the new screens are static menus. In game, Phase 4 adds one overlay node at a time (sync overlay, leave overlay, host-left dialog) and one chip; no particles and no shaders. The U-12 budget (p95 <= 4.35 ms Full) is unchanged.

---

## 15. Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTAs | "Host Match" (Play Online), "Join Match", "Start Match" (lobby host), "Ready Up" / "Cancel Ready" (lobby client), "Back to Lobby" (online results host), "Try Again" (connect error), "Back to Menu" (HOST LEFT) |
| Main menu | Item "Play Online"; description "Host or join friends over Tailscale or LAN." |
| Play Online | Title "PLAY ONLINE"; subtitle "Host a match or join a friend. 2 to 4 subs, same song, same game version."; captions "YOUR SUB", "HOST", "JOIN"; rows "Name", "Port", "Address"; hints "Shown to friends. Up to 12 letters, digits, spaces, _ or -." / "UDP port. Host and friends must use the same number. Default 47474."; host line "Open a lobby on this PC. Friends join with your address."; join line "Ask the host for their address. Tailscale addresses start with 100."; buttons "Host Match", "Paste", "Join Match"; "VERSION {v}" |
| First-visit prompt | "Pick a name your friends will see, then press Enter." |
| Connect panel (right) | "CONNECT WITH FRIENDS", "THIS PC'S ADDRESSES", chips "TAILSCALE" / "LAN", "Give the Tailscale address to friends." / "No Tailscale address. Friends outside your home network need Tailscale." / "No network address found. Check that this PC is online."; "HOW TO CONNECT"; steps "1. Everyone installs Tailscale (free) and joins the host's tailnet." · "2. The host picks Host Match and shares the Tailscale address above." · "3. Friends type that address, keep port {port}, and pick Join Match." · "4. Same Wi-Fi or LAN? Use the LAN address instead."; "Full guide: ONLINE_SETUP.md in the game folder."; "First time hosting? Click Allow when Windows Firewall asks." |
| Connect dialog stages | "CONNECTING" / "Calling {address}:{port}. This can take a few seconds." · "CHECKING VERSION" / "Connected. Checking that you both run the same game build." · "SYNCING CLOCKS" / "Lining up your clock with {HOST}'s for a synced start." · "{n} S" · button "Cancel" |
| Connect errors (title / body) | "NO ANSWER" / "No answer from host after 8 s. Check that the host allowed UNDERTOW through Windows Firewall and that you are both connected in Tailscale." · "ADDRESS NOT FOUND" / "Could not find {address}. Check the spelling, or use the host's 100.x.y.z Tailscale address." · "DIFFERENT VERSIONS" / "The host runs UNDERTOW {host_version} and you run {my_version}. Everyone needs the same build." · "LOBBY FULL" / "This lobby already has 4 subs." · "MATCH IN PROGRESS" / "The host is in a match. Try again when they are back in the lobby." · "CONNECTION LOST" / "The link to the host dropped while joining. Try again." Buttons "Try Again" / "Back" |
| Host errors (status line) | "Could not open port {port}. Another program or another UNDERTOW is using it. Pick another port." · "Could not start hosting (error {code}). Check your network and try again." |
| Field errors (status line) | "Port must be between 1024 and 65535." · "Clipboard has no address to paste." |
| Return messages (Play Online status line) | "The host removed you from the lobby." · "The host closed the lobby." · "Lost the connection to the host's lobby." |
| Lobby | Title "LOBBY", chip "HOST"; subtitles "You are hosting. Friends join with {address}:{port}." / "Connected to {HOST}'s lobby."; caption "MATCH"; rows "Song", "Difficulty", "Torpedo flight"; tiles "2 BEATS", "1 BEAT LAN"; flight lines "Torpedoes fly 2 beats. Safe for internet play." / "Torpedoes fly 1 beat. For same-room LAN only; warnings get shorter online."; "Choose a song" / "Host is choosing a song"; captions "INVITE" / "CONNECTION"; "{address}:{port}"; "Tailscale address. Friends on your LAN can use {lan}." / "LAN address. Friends outside your network need Tailscale."; "HOST {HOST}"; "PING {n} MS · CLOCK SYNCED" / "PING -- MS · SYNCING CLOCK"; "Copy Address" / "Copied"; "Start Match"; "Ready Up" / "Cancel Ready" |
| Lobby roster | "SUBS IN THIS LOBBY {n}/4"; heads "NAME", "PING", "SONG", "READY"; "{n} MS", "-", "SYNC"; chips "OK", "MISSING", "CHANGED", "CHECKING", "NO SONG"; "READY", "WAITING", "HOST"; "ENTER KICK" / "A KICK"; "OPEN SEAT", "Waiting for a friend to join." |
| Start gate reasons (host) | "Waiting for at least 1 friend to join." · "Pick a song first." · "Syncing clocks..." · "{NAME} is missing the song." / "{n} subs are missing the song." · "{NAME} has a different version of this song." · "Waiting for {NAME} to ready up." / "Waiting for {n} subs to ready up." · startable: "All subs ready. Start when you like." |
| Client reason line | "Waiting for the host to pick a song." · "You are missing this song. Add it to your Songs folder and restart UNDERTOW, or ask the host for another song." · "Your copy of this song differs from the host's. Ask the host for another song." · "Ready Up when you are set." · ready: "Waiting for the host to start." |
| Lobby log | "{NAME} joined." · "{NAME} left." · "{NAME} was removed by the host." · "Host is choosing a song." · "Host picked {title} ({DIFFICULTY}). Ready cleared." · "Torpedo flight set to {n} beats." ("1 beat") · "{NAME} is ready." · "{NAME} is missing this song." · "High latency to {NAME} ({n} ms). Torpedo warnings may be shorter than 1 beat." · "{NAME} could not load the song in time. Back in the lobby." · "The start signal reached {NAME} too late. Back in the lobby." · "{NAME} could not load this song. Back in the lobby." · "Match ended. Ready up for another." |
| Song pick chip | "ONLINE" |
| Start sync overlay | "LOADING SONG" / "LINKING SUBS"; "Waiting for {n} of {m} subs to load." / "All loaded. Waiting for the start signal."; "LOADED" / "LOADING"; "ESC LEAVE MATCH" / "START LEAVE MATCH" |
| Countdown | "ALL SUBS LINKED", "DIVE IN 3" / "DIVE IN 2" / "DIVE IN 1", "DIVE", "FLIGHT {n} BEATS" / "FLIGHT 1 BEAT" |
| In match | Periscope "LEFT", "DISCONNECTED"; killfeed "{A} left the match"; chip "NO HOST SIGNAL"; end wait "MATCH COMPLETE", "WAITING FOR RESULTS", "{n} SUBS STILL DIVING" |
| Leave overlay | "LEAVE MATCH?", "PING {n} MS"; client "The song keeps playing. Leaving makes your sub a wreck."; host "You are the host. Leaving ends the match for everyone."; buttons "Leave Match" / "Stay" |
| HOST LEFT dialog | Titles "HOST LEFT" / "CONNECTION LOST"; bodies "{HOST} left, so the match ended. Nothing is saved." / "No signal from {HOST} for 4 seconds. The match ended on this PC. Nothing is saved."; "LAST KNOWN STANDINGS"; statuses "HULL {h}%", "WRECK", "LEFT"; button "Back to Menu"; hint "ENTER BACK TO MENU" / "A BACK TO MENU" |
| Online results | chip "ONLINE"; status "LEFT AT {m:ss}"; buttons "Back to Lobby", "Back to Menu", "Leave Lobby"; "Waiting for {HOST} to return to the lobby." / "The host closed the lobby."; hints as section 12 |
| Settings | Section "ONLINE"; rows "Player name", "Online port"; hints "Shown to friends in online matches. Up to 12 letters, digits, spaces, _ or -." / "UDP port used to host and join. Default 47474." |
| Empty states | Lobby with only the host: 3 "OPEN SEAT" rows + gate "Waiting for at least 1 friend to join."; no song: "Choose a song"; no addresses: "No network address found. Check that this PC is online."; empty clipboard: "Clipboard has no address to paste."; empty lobby log: "Lobby open. Share your address to invite friends." (host) / "You joined {HOST}'s lobby." (client) as the first line |
| Destructive confirmations (`ConfirmDialog`, destructive confirm, safe initial focus) | **CLOSE LOBBY** (host Esc in lobby, host Back to Menu on results): "Close the lobby? Everyone is sent back to Play Online." / "Close Lobby" / "Stay" · **LEAVE LOBBY** (client Esc in lobby, client Leave Lobby on results): "Leave this lobby? You can join again with the same address." / "Leave Lobby" / "Stay" · **REMOVE {NAME}** (host kick): "Remove {NAME} from the lobby? They can join again." / "Remove" / "Keep" · **Leave Match** in game uses the Leave overlay itself as the confirm (11.4) |

Tone: unchanged (short, plain, sonar-terse captions; sentence case in body lines). Names, addresses, ports, versions and counts are runtime values, never baked into strings. Every string uses only characters present in Share Tech Mono and Oxanium (no arrows, check marks or emoji; the "·" middle dot is present, U-3.2 V). A test asserts `has_char` for every new constant string.

---

## 16. Layout and Contract Tests (for the planner)

| Test | Extension |
|------|-----------|
| `test_menu_flow.gd` | 10 items, tops 392 + 56 i, size 512 x 48, `STAGGER_MENU` 0.030, Play Online at index 2 with icon `online`, last item bottom 944 < description top |
| `test_layout_keepout.gd` | Add `LeaveOverlay` exact rect (640, 120, 640, 152), entirely outside the keep-out. Add the link chip to the largest-state chip scan (still 6 rects max, overflow rule 11.5). `StartSyncOverlay` (600, 340, 720, 400) is the declared exception: assert it is hidden before `conductor.begin` returns + `DUR_BASE` (no note can be drawn while it is visible) |
| `test_overlay_layout.gd` | `HostLeftDialog` panel (480, 240, 960, 600), button (512, 744, 400, 64); connect dialog uses `ConfirmDialog` geometry |
| `test_online_menu.gd` (new) | Region rects of section 8, focus order 8.2 (including the Paste/Join row and a disabled Join), first-visit editing focus, Tailscale row first and highlighted for a `100.64.0.0/10` address, link-local and loopback hidden, field charset/length/port validation, Esc while editing does not leave the screen |
| `test_lobby_screen.gd` (new) | Region rects of section 9, host vs client controls, start gate order and reason copy, Ready cleared on song change, roster column positions, MISSING/CHANGED chips, high-latency red + glyph, kick confirm, log max 6 lines |
| `test_online_gameplay.gd` | Sync overlay text states, countdown digit from song time (-2.4 -> "DIVE IN 3", -0.2 -> "DIVE IN 1", 0 -> "DIVE"), Leave overlay non-pausing (song_time advances, lane press judged, Space does not fire while open), PLAYER_LEFT periscope + killfeed replacement, link chip at 1 s, HOST LEFT vs CONNECTION LOST titles |
| `test_color_literals.gd` | Covers `src/ui/online/**` automatically |
| `test_contrast.gd` | C26 `TEXT_HI` / `TEXT_LO` on field well `ABYSS_800` (15.74 / 6.35, min 4.5); C27 field idle edge `SONAR` 45% on glass (3.05, min 3.0); C28 `WARNING_RED` on `danger` chip composite (5.29, min 4.5); C29 `WARNING_RED` on `ABYSS_600` 92% row (4.66, min 4.5; high-latency ping on your own row); C30 `SONAR_PALE` on `ABYSS_600` row (13.37) (V, computed this session) |
| `test_effect_settings.gd` | Enumerates the section 14 nodes |
| `test_ui_icons.gd` | Section 5 names draw |
| `test_fonts.gd` (or a new string test) | Every new constant string `has_char` in its font |

---

## 17. Defaults Log (choices made here, with reasons)

1. **Main menu item height 48, pitch 56 (was 56 / 64), stagger 30 ms.** Ten items at the old pitch end at 1024 and collide with the description line. 48 is the existing compact button height, so no new token. The logo, tagline, description and status line stay put, which keeps the menu tests' anchors and the last-dive card valid.
2. **Play Online sits third, right after Versus Bots.** The two versus modes are adjacent, and Start Dive stays first and primary.
3. **The host is implicitly ready; only clients toggle Ready.** The host's Start Match press is the host's ready. D-12's "every present player is Ready" then reads as "every client". It saves the host a pointless step.
4. **Start also waits for clock sync (5 samples).** D-07 schedules the start from the clock offset; starting before sync would start peers apart. It normally finishes within a second of joining, so the gate rarely shows.
5. **One Play Online screen holds name, port, host and join**, instead of separate Host and Join screens. The name and port apply to both actions, and one screen keeps the path to a match at two presses. The name prompt is the same field in editing mode on first visit (D-20 "asked once") rather than a separate dialog.
6. **High latency uses `WARNING_RED` + `warning` glyph + a log line, not yellow.** The palette has no yellow and adding a hue breaks the no-new-hues rule. Gold is reserved for rewards and sits too close to lane-2 amber.
7. **No UPnP button in v1.** D-14 marks it optional; many routers have UPnP off and it fails under CGNAT. The screen space goes to the Tailscale address list and the firewall line, which solve the common case.
8. **Gamepad text entry by D-pad character cycling (plus X delete) inside the same field.** Addresses are mostly pasted or typed, but a pad-only player can still set a name and a short address without an on-screen keyboard component. Gamepad X is unbound everywhere (V).
9. **Leave overlay sits in the top band (y 120..272), not centred, and consumes Space / A.** Centring it would cover the highway while the song keeps playing. Consuming ui_accept means pressing fire with the overlay open chooses the focused button (Stay by default) instead of firing; lane keys stay live, which is what D-18 "input stays live" protects.
10. **Countdown lives in the event banner slot, in seconds, not as big centre numerals.** The lead-in is about 3 s but not beat-aligned, and notes can enter the highway during it, so a centre numeral would sit in the note path. The banner slot is outside the keep-out and already the place for match-level messages.
11. **Sync overlay is the only in-game element inside the keep-out, and only before the conductor begins.** No notes exist on the board then. A test asserts it is gone before any note can draw.
12. **Network quality is not in the HUD for healthy links.** Players get a link chip only when the host goes silent for 1 s. RTT, horizon, skew and landed-late numbers are F3 rows (D-10 says measure first). Ping is visible in the lobby and in the Leave overlay. This keeps the periphery calm (P3-11 rule 7).
13. **PLAYER_LEFT replaces the IMPLODED killfeed line for the same seat.** The disconnect path calls `on_failed`, which emits IMPLODED first; two lines for one event would read as two things happening.
14. **HOST LEFT and CONNECTION LOST are one dialog with two titles.** A client cannot tell a crashed host from its own dropped link; D-16 gives both the same treatment. The title is honest about what this PC saw.
15. **Clients' Leave Lobby goes to Play Online; HOST LEFT goes to the main menu (D-17).** From the lobby, players most likely want to rejoin, and Play Online keeps the saved address. D-17 names Back to Menu for the abort path, so it is kept there.
16. **Online results replace Rematch / Change Match with Back to Lobby.** The lobby is where the song, difficulty and Ready live online (D-19).
17. **Roster ping is the host-measured round trip, refreshed at 1 Hz.** It is the number that matters for D and is the same on every PC, so friends can talk about it.
18. **Field idle edge at `SONAR` 45%, not the button-idle 30%.** 30% measures 2.03:1 on glass, under the 3:1 minimum for a component boundary; 45% measures 3.05:1 (V).

## Notes for the checker (non-blocking)

- Typography: still 4 sizes (20/28/40/96) and 2 weights; Display 96 and the Cinematic exception are not used by new elements.
- Colour: no new hues and no new Palette constants. One new chip variant (`danger`) built from existing tokens. Reserved-for lists extended explicitly in 3.1.
- Spacing: tokens unchanged; menu 48/56, roster 64/72, log pitch 40 and the 152 px overlay are declared exceptions (multiples of 4).
- Open questions for the end-of-phase UAT: (1) Is the Leave overlay's position noticed, and is consuming fire acceptable? (2) Is D-pad character cycling usable for names? (3) Is the 1 s threshold for NO HOST SIGNAL too twitchy over Tailscale relays? (4) Does the countdown in the banner slot feel like a proper start, or do players miss the cinematic numerals?

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none (not applicable, Godot project) | not required |
| Third-party UI registries | none | not applicable |
| Vendored assets | none new (glyphs are first-party vector code; no fonts or art added) | not applicable |

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending
