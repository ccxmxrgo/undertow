---
phase: 3
slug: offline-versus
status: draft
shadcn_initialized: false
preset: none
created: 2026-10-15
mode: auto (no questions asked; user asleep; every choice is consistent with 02.2 and recorded in the Defaults Log)
extends: ".planning/phases/02.2-visual-design-overhaul/02.2-UI-SPEC.md (approved 2026-10-10). Everything there stays in force unless a row below says otherwise."
---

# Phase 3 - UI Design Contract: Offline Versus

> **Authority:** `03-SPEC.md` (locked) > `03-CONTEXT.md` (D-01..D-33 from `03-RESEARCH.md`) > this file > `02.2-UI-SPEC.md`. Where this file refines a D-xx default (panel height, buff chip home, target readout), the refinement and its reason are in the Defaults Log (section 16). The planner should treat this file as the layout source.
> **Platform:** Godot 4.7.2, GDScript, `gl_compatibility`, 1920x1080 base, `canvas_items` / `keep`. All pixel values are at the 1920x1080 base.
> **Sources:** (S-n) = 03-SPEC requirement n. (D-n) = 03-RESEARCH/03-CONTEXT decision. (U-x.y) = 02.2-UI-SPEC section. (V) = checked in the repo or computed this session. (default) = choice made here, listed in section 16.
> **Fantasy:** your sub's sonar cockpit, now with rivals in the water. Rival subs appear as periscope readouts on the left, the comms log on the right, threats arrive as red sonar contacts, and rewards load into the torpedo socket.

---

## 1. Design System

| Property | Value |
|----------|-------|
| Tool | none (Godot project; shadcn does not apply). Registry gate: not applicable |
| Preset | not applicable |
| Component library | Unchanged from U-1: `Palette`, `UiKit` (`style_panel`, `make_button`, `draw_chip`, `draw_brackets`, `register_fx`, `pop_in`, `FocusMarker`), `UiIcons`, `NotePainter`, gauges, `AbyssBackdrop`, `ScreenTransition`. New views go in `src/ui/versus/` (D-28 structure) |
| Icon library | `UiIcons` 24x24 vector glyphs with 2 px strokes. Phase 3 adds 24 glyphs (section 4). No emoji or Unicode arrows anywhere (Oxanium and Share Tech Mono lack them; Pitfall 7) |
| Fonts | Unchanged: Oxanium 700 (Heading/Display), Share Tech Mono 400 (Label/Body, embolden 0.5 for bold) |
| Shaders | No new shaders. Ink Cloud's soft edge is drawn with polygons and a gradient texture, not a shader (stays within the 3-shader budget of U-1) |
| Particles | `CPUParticles2D` only, pooled (U-12) |
| New render layers (gameplay) | Inserted into the U-1 order: `Arena` > `HighwaySurface` > `FxLayer` > `Feedback` > `HighwayNotes` > **`InkCloudLayer`** > **`InkTopLayer`** > `CockpitFrame` > `Hud` (now also: **`RewardSocket`** on top of `TorpedoSocket`, **`TargetReadout`**, **`StatusChips`**) > **`VersusHud`** (`PeriscopeColumn`, `Killfeed`, `AlertSlot`, `EventBanner`, `EdgeFlash`, `RewardPopup`) > `GogglesIntro` > overlays > `ScreenTransition`. All non-interactive: `mouse_filter = IGNORE`, `UiLayout.fill_rect` for full-screen canvases |

Every new node that animates or draws optional effects calls `UiKit.register_fx(self)` and implements `apply_effect_settings()` and `effect_counts()` (project contract). The node list is in section 12.

---

## 2. Spacing Scale

Unchanged tokens `Palette.SP_*` (U-2):

| Token | Value | Usage in this phase |
|-------|-------|---------------------|
| xs | 4px | Icon-to-text gaps in killfeed lines, reticle offset outside panels, hull-bar segment gap is 2 (stroke-class exception below) |
| sm | 8px | Gap between periscope panels, between killfeed lines, between medal badges and chip stack rows (40 pitch = 32 + 8) |
| md | 16px | Periscope panel inner padding, alert slot padding, match-setup row label inset |
| lg | 24px | Glass panel padding on match setup and versus results |
| xl | 32px | Gap between match-setup panels; outer frame margin |
| 2xl | 48px | Compact control height (segmented selectors, training stepper) |
| 3xl | 64px | Screen-edge padding; button height; match-setup row height |

Exceptions (declared):
- Periscope panel height 88 and killfeed line height 40 (both multiples of 4, not tokens). Reason: they have to fit the free vertical bands measured in section 6.1.
- Hull-bar segment gap 2 px and countdown ring widths 2 to 4 px are strokes, not spacing (U-2 rule).
- Main menu pitch stays 64 (current code: `ITEM_H` 56, `ITEM_PITCH` 64) (V).
- Results row height 96 (2 x 48).

Edges, cuts and brackets: unchanged (U-2). HUD glass panels in this phase use `CUT_SM` (8 px) instead of `CUT_MD` because they are 40 to 88 px tall.

---

## 3. Design Tokens

### 3.1 Colour (Palette only; no new hues)

Phase 3 adds **two constants and zero new hues** to `src/ui/palette.gd`:

| New constant | Value | Why |
|--------------|-------|-----|
| `HUD_GLASS_ALPHA` | `0.92` | Fill alpha of `ABYSS_700` for in-game versus panels (periscope, killfeed, alert slot, event banner). At the U-4.1 82%, `WARNING_RED` text over a worst-case `WALL_TEAL` arena ring measures 4.18:1 (fails). At 92% it measures 4.79:1 (passes) (V, computed this session) |
| `JAM_GREY` | `= TEXT_MID` (`#A9B4CC`, alias) | Sonar Jam gem colour (D-15). It is an alias so `test_color_literals` sees no new literal and the existing contrast rows apply |

**60 / 30 / 10 (unchanged):** 60% `ABYSS_900` (arena, screen backgrounds), 30% glass and surfaces (`ABYSS_700` panels at 82% / 92%, `HIGHWAY_BASE`, consoles), 10% light (`SONAR` chrome, lane neons on the board, gold and red signals).

| Role | Token | Hex |
|------|-------|-----|
| Dominant (60%) | `ABYSS_900` | `#03060D` |
| Secondary (30%) | `ABYSS_700` at 82% (menus, results) / 92% (in-game versus HUD) | `#0A1A2E` |
| Accent (10%) | `SONAR` | `#05D9E8` |
| Destructive / threat | `WARNING_RED` | `#FF4A3D` |
| Reward | `REWARD_GOLD` | `#FFD36B` |

**`SONAR` reserved for (U-3.1 list items 1-10, plus):** (11) the reward meter arc fill on the torpedo socket and on periscope panels, (12) the buff ring around a held buff icon, (13) the 4 px "this is you" bar on killfeed lines and on the YOU row of versus results, (14) the targeted panel's edge, (15) the Solo Duel progress line, (16) the `info` chips added here (PLACE, IMMUNE, buff chips). Never body text.

**`SONAR_PALE` adds:** the target reticle and target caret, the full-meter breathing arc, the Crossed Wires swap guides, the warhead Perfect confirm flash, the duel Perfect % once it is at or above the win line.

**`WARNING_RED` reserved for (U-3.1 plus):** incoming and active disruptor telegraphs (alert slot `danger` variant, edge flash, panel countdown ring), the ring around a held disruptor icon, warhead rings on the board, the GHOST judgment popup, the Pressure Crack rail tint, the SHIELDED / NO TARGET refusal, IMPLOSION and WRECK labels, and the 4 px bar on killfeed lines where YOU are the victim. Never on a buff.

**`REWARD_GOLD` reserved for (U-3.1 plus):** the bounty glyph, bounty brackets and the BOUNTY ON YOU chip, the Solo Duel banner caption, a won-solo result, the duel prize queue pip, medals, the "1ST" place label and the "YOU WIN" headline. **Gold stays outside the note-path keep-out (U-3.1 rule).** Every gold element in this file is in the left column, right column, consoles, the two top slots (y <= 272) or full-screen results, so the rule holds.

**Lane neons:** unchanged. Board effects in this phase never recolour gems except Sonar Jam (section 7.6) and Ghost Notes (section 7.2), both by design.

### 3.2 Typography (unchanged: 4 sizes, 2 weights)

| Role | Font | Size | Weight | Line height | Phase 3 uses |
|------|------|------|--------|-------------|--------------|
| Label | Share Tech Mono | 20 | 400 | 1.5 | Callsigns, panel status, killfeed lines, chips, captions, reward name under the socket, medal names, hints |
| Body | Share Tech Mono | 28 | 400 (bold = embolden 0.5) | 1.5 | Target name, match-setup rows and buttons, results sub-captions, training stepper value |
| Heading | Oxanium | 40 | 700 | 1.2 | Alert and event banner headlines, reward-ready popup, results place / callsign / numbers, match-setup title |
| Display | Oxanium | 96 | 700 | 1.0 | Not used by new elements (results keeps place in Heading 40, see 9.1) |

Rules carried over: live numerals use Oxanium (tabular) or Share Tech Mono (monospace) inside fixed boxes (no layout shift). Callsigns and captions UPPERCASE with +2 px letter spacing. Killfeed payload names use the spec's Title Case ("Ink Cloud") with +0 spacing; verbs stay lowercase as written in 03-SPEC req 12.

### 3.3 Motion (tokens unchanged, U-3.4)

| Token | Value | New uses |
|-------|-------|----------|
| `DUR_FAST` 120 ms | | Killfeed line shift, refusal flash in, reticle move between panels, icon pop |
| `DUR_BASE` 180 ms | | Panel / line / banner in, chip pop, receptor cross-fade under Reduce motion |
| `DUR_SLOW` 300 ms | | Medal pop sequence, results row rise |
| `DUR_MAX` 400 ms | | Killfeed fade-out, banner fade-out cap |
| Beat-locked | `BeatClock` on `song_time` | Telegraph countdown rings, Crossed Wires slide, Pressure Crack ease, Ink and Jam fade in/out (all 1 beat). These are game-state visuals and follow the song clock, never frame time |

---

## 4. New Glyphs (`UiIcons`, 24x24 grid, 2 px strokes, closed shapes filled where noted)

`UiIcons.NAMES` gains the entries below. All glyphs are drawn at 16, 20, 24 or 32 px by scaling the grid. A test draws each name without error and checks `names()` contains it.

| Name | Used for | Geometry (24 grid) |
|------|----------|--------------------|
| `crossed_wires` | Reward | Two polylines crossing in an X: (3,6)->(10,6)->(14,18)->(21,18) and (3,18)->(10,18)->(14,6)->(21,6) |
| `ghost_notes` | Reward | Dashed diamond outline (4 dashes) centred (12,12) r 8, plus a small solid diamond r 3 at (19,5) |
| `ink_cloud` | Reward | Filled cloud: three overlapping circles r 5 at (7,14) (12,10) (17,14), flat filled base y 14..19 |
| `pressure_crack` | Reward | Double chevron pointing down (speed): (5,5)->(12,11)->(19,5) and (5,12)->(12,18)->(19,12) |
| `sonar_jam` | Reward | Circle r 8 with a diagonal slash (6,18)->(18,6) |
| `depth_charge` | Reward | Filled circle r 6 at (12,14) with a 2x5 fuse stem at (12,3..8) and 3 short spark strokes |
| `decoy_flare` | Reward | Shield outline (6,4)(18,4)(18,12)(12,20)(6,12) with a small filled flame drop inside |
| `ballast_patch` | Reward | Plus sign (12,5..19) and (5..19,12) inside a chamfered square outline |
| `overclock` | Reward | Gauge arc 200 deg r 8 with a needle from (12,14) to (18,8) |
| `arrow_right` | Killfeed "⟶" | Line (3,12)->(19,12) with a filled head (15,8)(21,12)(15,16) |
| `reflect` | Killfeed "↩" | U-turn polyline (19,6)->(8,6) arc down to (8,16)->(14,16) with head at (14,16) pointing right |
| `shield` | Killfeed "blocked", IMMUNE chip | Shield outline (6,4)(18,4)(18,12)(12,20)(6,12) |
| `cross` | Killfeed "collided" | X from two 2 px lines (5,5)-(19,19) and (19,5)-(5,19) |
| `skull` | Killfeed "imploded", wreck debris lines | Head: chamfered square (5,4)-(19,16); two filled 4x4 eye squares at (8,9) (12..16,9); jaw: 3 vertical ticks (9,17..20) (12,17..20) (15,17..20) |
| `bounty` | Bounty marker, chip, killfeed | Crosshair: circle r 7 plus 4 ticks (12,1..5) (12,19..23) (1..5,12) (19..23,12), filled dot r 2 at centre |
| `target` | Target readout | Four corner L-brackets (arms 6) around a 16x16 square, dot r 2 at centre |
| `debris` | Wreck debris (Silt, Groan) | Three filled shards: triangles (4,16)(9,10)(11,18); (11,8)(16,4)(17,11); (14,15)(20,12)(19,20) |
| `versus` | Main menu Versus Bots | Two torpedo capsules (rounded-end lines 2 px) crossing at 30 deg: (3,8)->(21,16) and (3,16)->(21,8) |
| `medal_untouchable` | Medal | `shield` plus a check (8,12)(11,15)(16,9) |
| `medal_uno_reverse` | Medal | Two curved arrows forming a circle (two 150 deg arcs r 8 with heads) |
| `medal_bounty_hunter` | Medal | `bounty` crosshair with a filled star dot replaced by a small diamond r 3 |
| `medal_shredder` | Medal | Lightning bolt filled: (13,2)(6,13)(11,13)(9,22)(18,10)(13,10)(15,2) |
| `medal_head_on` | Medal | Two arrows meeting head to head at (12,12): (2,12)->(10,12) and (22,12)->(14,12) with 3 burst ticks above and below |
| `medal_grudge` | Medal | Three stacked chevrons pointing right at x 6, 11, 16 |
| `medal_dogpiled` | Medal | Filled dot r 3 at centre with three arrows converging from (3,4) (21,4) (12,22) |

### 4.1 Reward table (display data; lives in `src/versus/reward.gd` next to the rule data)

| Id | Kind | HUD name (UPPERCASE) | Killfeed name | Glyph | One-line description (match setup, training stepper) |
|----|------|----------------------|---------------|-------|----------------------------------|
| CROSSED_WIRES | Disruptor | CROSSED WIRES | Crossed Wires | `crossed_wires` | Two lanes trade places for 4 bars. |
| GHOST_NOTES | Disruptor | GHOST NOTES | Ghost Notes | `ghost_notes` | Hollow fake notes for 4 bars. Hitting one costs hull. |
| INK_CLOUD | Disruptor | INK CLOUD | Ink Cloud | `ink_cloud` | Ink hides the bottom of the highway for 4 bars. |
| PRESSURE_CRACK | Disruptor | PRESSURE CRACK | Pressure Crack | `pressure_crack` | Notes scroll 1.5x faster for 4 bars. |
| SONAR_JAM | Disruptor | SONAR JAM | Sonar Jam | `sonar_jam` | Notes lose colour and shape for 3 bars. |
| DEPTH_CHARGE | Disruptor | DEPTH CHARGE | Depth Charge | `depth_charge` | Extra notes on the beat for 2 bars. |
| DECOY_FLARE | Buff | DECOY FLARE | Decoy Flare | `decoy_flare` | Absorbs the next torpedo aimed at you. |
| BALLAST_PATCH | Buff | BALLAST PATCH | Ballast Patch | `ballast_patch` | Repairs 25% of your hull. |
| OVERCLOCK | Buff | OVERCLOCK | Overclock | `overclock` | Goods count as Perfect for 4 bars. |
| (debris) SILT | Wreck debris | SILT | Silt | `debris` | (not in bag) |
| (debris) GROAN | Wreck debris | GROAN | Groan | `debris` | (not in bag) |

Bar counts in the descriptions are read from `VersusConfig` at runtime (never hard-coded in strings), so a retune updates the copy.

---

## 5. Gameplay HUD: Your Sub (left and right consoles)

The 02.2 HUD (U-7.3) is unchanged. Phase 3 adds the elements below into space measured free in the current code (V: `hud.gd`, `streak_counter.gd`, `torpedo_socket.gd`, `multiplier_ring.gd`).

### 5.1 Reward socket (`src/ui/versus/reward_socket.gd`, child of `Hud`, drawn over `TorpedoSocket`) (S-1, S-2, S-4, D-33)

`TorpedoSocket` keeps drawing its recessed circle (U-4.14). `RewardSocket` is a sibling Control at the same rect (272, 928, 80, 80), centre C = (312, 968).

| Part | Spec |
|------|------|
| Meter arc track | 270 degree arc, radius 40, band 4 px (r 38..42), from 135 deg to 405 deg (Godot angles, clockwise; the 90 deg gap faces down). `ABYSS_500` 70% |
| Meter arc fill | Same arc, filled clockwise from 135 deg by `meter / threshold`, `SONAR`. Quarter ticks: 2 x 6 px `TEXT_LO` 60% at 25/50/75% |
| Full (reward held) | Whole arc `SONAR_PALE`, breathing alpha 0.70 <-> 1.00 over 1.6 s (sine). Reduce motion: static 1.00. Low effects: no glow_sm under the arc (Full draws glow_sm `SONAR_PALE` at 0.35 behind the socket) |
| Held icon | Reward glyph 32x32 at (296, 952), `TEXT_HI`. Kind ring at r 34, 2 px: disruptor `WARNING_RED`, buff `SONAR` |
| Earned | Icon pops 0 -> 1.15 -> 1.0 (`DUR_BASE`, back-out), ring flashes `SONAR_PALE` 120 ms. Reduce motion: fade in `DUR_BASE`, no scale |
| Fire pressed, waiting for the next beat | Icon at 50% alpha, ring dashes (8 dashes) until the launch beat |
| Launched (disruptor) | Icon scales 1.0 -> 0.6 and fades over `DUR_FAST`, arc empties to the current meter value over `DUR_BASE`. Reduce motion: fade only |
| Used (buff) | Icon fades over `DUR_FAST`; the buff chip appears in the right console (5.3) |
| Lost on elimination | Ring flashes `WARNING_RED` 200 ms, icon fades `DUR_FAST` |
| Duel prize queue pip | Filled circle r 5, `REWARD_GOLD`, at (346, 934) (top-right of the socket, inside the left console, outside the keep-out). Shown while a Solo Duel prize waits (S-2, S-11) |
| Wreck (debris meter) | Arc fill becomes `TEXT_MID` (not `SONAR`); held icon is `debris` with a `TEXT_MID` ring; after `debris_max_per_wreck` attacks the arc and icon hide and the socket shows only the base TorpedoSocket |

**Name line under the socket:** Label 20, centred x 312, baseline 1036, max width 160 px (box x 232..392), +1 px letter spacing.

| State | Text | Colour |
|-------|------|--------|
| Filling | "{meter}/{threshold}" e.g. "23/57" | `TEXT_LO` |
| Reward held | HUD name, e.g. "INK CLOUD" | `TEXT_HI` |
| Wreck, filling | "DEBRIS {meter}/{threshold}" (truncate to "{meter}/{threshold}" if > 160 px) | `TEXT_LO` |
| Wreck, debris held | "SILT" / "GROAN" | `TEXT_MID` |
| Wreck, used up | "NO DEBRIS LEFT" | `TEXT_LO` |

Clearances (V): perfect-streak value box ends at y ~904; socket arc top is y 926; MAX chip (only at x4) spans x ~114..174, y 1016..1048, which is left of the 232 name box.

### 5.2 Target readout (`src/ui/versus/target_readout.gd`, child of `Hud`) (S-4, D-01..D-03)

Box x 248..392, y 752..840 (left console, the free band between the streak numeral (bottom ~756) and the "PERFECT" caption (top ~836)) (V).

| Part | Spec |
|------|------|
| Caption | Label 20 `TEXT_LO` UPPERCASE at (256, 776): "AUTO TARGET" (AUTO mode), "TARGET" (a locked rival), "ATTACKERS" (ATTACKERS mode), "DEBRIS TARGET" (you are a wreck) |
| Value | Body 28 `TEXT_HI` at (256, 812), max width 136 px, truncated with "...": the resolved callsign ("ORCA"). No living rival: "NONE" `TEXT_LO`. Training: "DRONE" |
| Cycle (H / pad Y) | Value cross-fades `DUR_FAST`; the `target` glyph 16x16 at (372, 764) pulses once (1.0 -> 1.2 -> 1.0, `DUR_FAST`). Reduce motion: no pulse |
| Refused fire (target shielded) | Caption is replaced by "SHIELDED" `WARNING_RED` for 800 ms; `error` blip (U-10.4, declared in-gameplay exception). Reward is kept |
| Refused fire (no target alive) | Caption "NO TARGET" `WARNING_RED` for 800 ms; `error` blip |
| Bounty claimed by you | Caption "BOUNTY +{refund}" `REWARD_GOLD` for 1200 ms (e.g. "BOUNTY +14"); the socket arc jumps up over `DUR_BASE` |

### 5.3 Status chip stack (right console) (S-6, S-10, D-06, D-07)

The existing chip column (x 1552, U-7.3: NO-FAIL y 824, AUTOPLAY y 864) becomes a top-down stack with a 40 px pitch and 6 slots: y 824, 864, 904, 944, 984, 1024 (each 32 tall; last ends 1056). Max chip width 208 px (x 1552..1760, left of the bathymeter ticks at 1768) (V). Order, top first, only the visible chips take slots:

| # | Chip | Variant | Text | Shown when |
|---|------|---------|------|------------|
| 1 | NO-FAIL | `mode` | "NO-FAIL" | existing rule (Solo Dive always) |
| 2 | AUTOPLAY | `mode` | "AUTOPLAY" | existing rule |
| 3 | PLACE | `info` | "1ST OF 4" .. "4TH OF 4" | versus only; updates on the same game-state update as standings |
| 4 | BOUNTY | `reward` + `bounty` glyph 16 | "BOUNTY ON YOU" | you hold the bounty (S-10) |
| 5 | DECOY | `info` + `decoy_flare` glyph | "DECOY ARMED {n}" (n = bars left) | Decoy Flare armed |
| 6 | OVERCLOCK | `info` + `overclock` glyph | "OVERCLOCK {n}" | Overclock active |
| 7 | BALLAST | `info` + `ballast_patch` glyph | "HULL +25" (the actual percent from config) | 1600 ms after Ballast Patch, then fades `DUR_BASE` |
| 8 | IMMUNE | `muted` + `shield` glyph | "IMMUNE" | during your immunity window (D-07) |

Chips pop in (U-10.1, 1.0 -> 1.06 -> 1.0, `DUR_BASE`) and fade out over `DUR_BASE`; the stack re-packs with a `DUR_FAST` slide (Reduce motion: jump). At most 6 can be visible at once in versus (3..8 minus the two Solo-only chips), so the stack never runs past slot 6. `Hud.chip_rects()` and `keepout_shapes()` return every visible chip.

**Overclock judgment colour:** while Overclock is active, a GOOD popup (U-7.3) is drawn in `SONAR_PALE` instead of `TEXT_MID`. The word stays "GOOD" (honest feedback), and the meter visibly ticks up.

### 5.4 Reward-ready popup (`src/ui/versus/reward_popup.gd`) (S-4)

Shares the streak milestone popup anchor (centred x 208, U-7.3) and queues behind a milestone popup if one is showing (FIFO, no overlap).

| Part | Spec |
|------|------|
| Caption | "REWARD READY · {FIRE KEY}" Label 20 `TEXT_HI` with a 3 px `KEYLINE` outline, centred x 208, baseline 548. {FIRE KEY} is the current `fire` binding label from `BindingStore` ("SPACE" by default, "A" on a gamepad) |
| Name | HUD name, Heading 40 with a 3 px `KEYLINE`, centred x 208, baseline 590; colour `WARNING_RED` for a disruptor, `SONAR_PALE` for a buff |
| Timing | Pop 1.3 -> 1.0 (`DUR_FAST`, back-out), hold 1200 ms, fade 220 ms. **No rise** (it would cross into the periscope column). Reduce motion: no pop, fade only |
| Variants | Duel prize: caption "SOLO PRIZE · {FIRE KEY}". Prize queued (slot full): caption "PRIZE QUEUED", name = the queued reward |

Vertical extent y ~516..598 (V: Heading 40 ascent at 590, pop scale 1.3 at the start only). This is below the periscope column (ends 496) and above the console top (600).

### 5.5 Wreck state (you imploded) (D-22, D-24)

- The hull arc shows 0% with every segment cracked (U-4.7 rule).
- The "HULL CRITICAL" caption slot (centred x 960, baseline 1028, allow-listed board element) shows "WRECK · PERFECTS CHARGE DEBRIS" Label 20 `TEXT_MID` with a 3 px `KEYLINE`. No pulse.
- The socket switches to the debris meter (5.1). The target readout shows "DEBRIS TARGET" + the leader (D-25).
- The PLACE chip freezes at your final place.

---

## 6. Gameplay HUD: Rivals and Events (`VersusHud`)

### 6.1 Measured free space (V, current code)

| Band | Occupied by | Free for Phase 3 |
|------|-------------|------------------|
| Left, y 0..~141 at x 24 | Top-left bezel curve (`CockpitFrame`, ends at (0,200)) | nothing |
| Left, y 216..496 | nothing | **Periscope column** |
| Left, y ~512..598 | Streak milestone popup (centred x 208, baseline 584, rises 32 px) and the reward-ready popup (5.4) | nothing |
| Left, y 600..1080 | Left console | 5.1-5.2 only |
| Centre, y 26..112 | Progress track and top scrim | nothing |
| Centre, x 640..1280, y 120..192 | Lantern-fish band (arena, below HUD) | **Alert slot** (6.3) |
| Centre, x 640..1280, y 200..272 | Section banner | **Event banner** shares it (6.4) |
| Centre, y >= 348 | Note-path keep-out (top edge y 348) | nothing |
| Right, y 216..400 | nothing | **Killfeed** |
| Right, y 600..1080 | Right console | 5.3 only |

Keep-out check (V, from U-7.1 geometry): the expanded polygon's top edge is y 348, and its left edge is x ~806 at y 496. The periscope column (x <= 396 including the caret) and the killfeed (x >= 1544) are at least 400 px clear. The alert slot ends at y 192, 156 px above the keep-out. `test_layout_keepout.gd` must include every node in this section (section 13).

### 6.2 Periscope panels (`src/ui/versus/periscope_panel.gd` x up to 3, in `PeriscopeColumn`) (MATCH-04, S-10, S-11, D-26)

**Rects:** x 24..376 (352 wide), 88 tall, 8 px gap. P1 y 216..304, P2 y 312..400, P3 y 408..496. Panels fill top-down in seat order (bots in seat order; the training drone uses P1). Unused panels are not drawn.

**Panel chrome:** `UiKit.style_panel` look at `CUT_SM`: fill `ABYSS_700` at `HUD_GLASS_ALPHA` 92%, 2 px edge `SONAR` 45%, brackets TR/BL (20 px arms, `SONAR` 80%). No panel glow on Low effects.

**Content (offsets from the panel's top-left (x0, y0)):**

| Part | Position | Spec |
|------|----------|------|
| Scope / tube | Centre (x0+52, y0+44) | Disc r 24 `ABYSS_900` 90%. Tube meter arc: same 270 deg geometry as 5.1 at r 30, band 4 px (r 28..32), track `ABYSS_500` 70%, fill `SONAR`; full = `SONAR_PALE` (static, no breathing on rival panels). Wreck: fill `TEXT_MID` |
| Held reward | Inside the disc | Reward glyph 24x24 `TEXT_HI` with the kind ring at r 22, 2 px (`WARNING_RED` disruptor / `SONAR` buff). **Rivals' held rewards are visible** (D-26). When nothing is held the disc shows scope blips |
| Scope blips (decorative) | Inside the disc | On each rival Perfect: a 3 px `SONAR` dot at a seeded angle and radius 8..20, fading over 400 ms. Max 6 live dots (Full), 2 (Low), Reduce motion: dots appear and fade without the sweep line. Full also draws a sweep line (1 px `SONAR` 35%, one turn per bar) |
| Bounty glyph | (x0+96, y0+14), 16x16 | `bounty` glyph `REWARD_GOLD`, only on the bounty holder; the callsign shifts right 24 px. The panel's TR/BL brackets also turn `REWARD_GOLD` (U-4.1 `reward` variant) |
| Callsign | x0+96 (or +120 with bounty), baseline y0+30 | Label 20 `TEXT_HI` UPPERCASE +2 spacing, max width = up to 8 px left of the place text, measured with the spaced font (about 128 px without the bounty glyph, so 9 chars "BARRACUDA" fit; the old fixed 112 px ignored the +2 spacing, 03-REVIEW WR-06). Wreck: `TEXT_LO` |
| Place | right-aligned x0+272, baseline y0+30 | Label 20: "1ST" `REWARD_GOLD`, "2ND"/"3RD"/"4TH" `TEXT_MID` |
| Hull bar | x0+96..x0+272, y0+40..y0+50 | 10 segments of 16 px with 2 px gaps (176 px). Each segment = 10% hull; the boundary segment at partial alpha. Lit colour: > 50 `SONAR`, 30..50 `TEXT_HI`, <= 30 `WARNING_RED` (static, no pulse: a pulsing rival bar would pull the eye off the highway). Unlit `ABYSS_500` 70%. Damage: lost segment flashes `WARNING_RED` 200 ms (kept U-4.7 timing; Reduce motion: no flash, instant) |
| Wreck | replaces the hull bar | "WRECK" Label 20 `WARNING_RED`, baseline y0+52, plus the `skull` glyph 16 px left of it. Panel edge drops to `TEXT_LO` 35%, brackets `TEXT_LO` 50% |
| Status line | x0+96, baseline y0+76, max 176 px | Label 20. Default: depth "1,240 M" `TEXT_MID`. During a Solo Duel (S-11): "SOLO {p}%" where p = live Perfect % (integer), `SONAR_PALE` when p >= `solo_duel_min_accuracy`, else `TEXT_MID`; "SOLO --%" before the first solo note. Wreck during a duel: "SITTING OUT" `TEXT_LO`. Training drone: "NEXT IN {n} BARS" `TEXT_MID` (n = bars until the drone's next torpedo) |
| Threat block | Centre (x0+316, y0+44) | Countdown ring r 22, 3 px, plus the payload glyph 24x24 `TEXT_HI` inside. States below |

**Threat block states (what is happening TO this rival):**

| State | Ring | Glyph | Other |
|-------|------|-------|-------|
| None | 1 px dashed circle `TEXT_LO` 20% | none | |
| Incoming (in flight, from anyone) | `WARNING_RED`, drains clockwise over the flight (1 beat) | payload glyph | Panel edge flashes `WARNING_RED` 100% at launch, back to normal over 300 ms |
| Active | `WARNING_RED` 60%, drains over the payload duration in bars | payload glyph | |
| Immune | `TEXT_LO` 35%, drains over `immunity_bars` | `shield` `TEXT_LO` | |
| Collision (S-9) | ring bursts: r 22 -> 34, alpha 1 -> 0, 300 ms, `TEXT_HI` | `cross` for 600 ms | Panel edge flashes `TEXT_HI` 200 ms (both colliding panels flash; yours flashes via the alert slot, 6.3) |
| Absorbed by Decoy | none | `decoy_flare` `SONAR` for 600 ms | Decoy is hidden on rival panels until it absorbs something (default, section 16) |
| Reflected back by this rival | ring flashes `SONAR_PALE` | `reflect` for 600 ms | |

Overclock and Decoy on rivals are not shown (hidden information, default). Ballast on a rival shows only as the hull bar refilling.

**Target marker (the rival you will fire at):**
- Panel edge 2 px `SONAR` 100% (instead of 45%).
- Reticle: four L-brackets, 16 px arms, 2 px `SONAR_PALE`, drawn 4 px outside each panel corner.
- Caret: 12x16 filled triangle `SONAR_PALE` pointing left, at x 384..396, vertically centred on the panel.
- Moving the target: the reticle and caret glide to the new panel (`DUR_FAST`, cubic-out). Reduce motion: jump.
- AUTO and ATTACKERS show the reticle on the resolved rival. With no target, no reticle.

**Entrance:** during the intro count-in, panels fade in and slide 16 px from the left, 60 ms stagger. Reduce motion: fade only.

### 6.3 Alert slot (your incoming / active threat) (`src/ui/versus/incoming_alert.gd`) (TORP-04, S-4, S-9, D-04, D-05, D-17)

**Rect:** x 640..1280, y 120..192 (640 x 72), directly above the section banner. Declared centre-band exception (same reasoning as the U-4.9 section banner: above the vanishing point, outside the note path). Chrome: `CUT_SM`, fill `ABYSS_700` 92%, padding 16. Hidden when there is no threat.

| Part | Position |
|------|----------|
| Icon + countdown ring | Ring centre (680, 156), r 24, 3 px; payload glyph 32x32 at (664, 140) `TEXT_HI` |
| Caption (left) | Label 20 at x 720, baseline 146, max 232 px |
| Hint (right) | Label 20 right-aligned at x 1264, baseline 146, max 296 px |
| Headline | Heading 40 `TEXT_HI` at x 720, baseline 184, max 528 px |
| Duration line | 2 px along the panel bottom (y 190..192, x 640..1280), drains left to right over the active duration |

| State | Chrome | Ring | Caption | Hint | Headline |
|-------|--------|------|---------|------|----------|
| INCOMING (launch -> arrival) | `danger`: edge `WARNING_RED` 100%, brackets `WARNING_RED` | `WARNING_RED`, drains over the flight (1 beat) | "INCOMING · {FROM}" `WARNING_RED` | warheads exist: "HIT RINGED NOTES PERFECT" `TEXT_MID`; none: "CANNOT BE REFLECTED" `TEXT_LO`; your Decoy armed: "DECOY WILL ABSORB" `SONAR` | HUD name, e.g. "INK CLOUD" |
| INCOMING reflected at you | as above | as above | "REFLECTED BY {FROM}" `WARNING_RED` | "CANNOT BE REFLECTED" `TEXT_LO` or "DECOY WILL ABSORB" | HUD name |
| INCOMING debris | as above | as above | "WRECK DEBRIS · {FROM}" `WARNING_RED` | "CANNOT BE REFLECTED" | "SILT" / "GROAN" |
| ACTIVE (warheads still open) | edge `WARNING_RED` 60% | `WARNING_RED` 60%, drains over the duration | "ACTIVE · {FROM}" `WARNING_RED` | "REFLECT {k}/{n}" `SONAR_PALE` (k Perfect warheads so far) | HUD name |
| ACTIVE (reflect failed or no warheads) | edge `WARNING_RED` 60% | same | "ACTIVE · {FROM}" | "{n} BARS LEFT" `TEXT_MID` (n rounds up) | HUD name |
| REFLECTED (you sent it back) | default edge `SONAR` | ring flash `SONAR_PALE` | "REFLECTED" `SONAR_PALE` | none | "BACK TO {FROM}" |
| ABSORBED (your Decoy) | default edge | none | "DECOY ABSORBED" `SONAR` | none | HUD name |
| COLLISION (your shot and theirs met) | default edge | burst (6.2) | "HEAD-ON COLLISION" `TEXT_HI` | none | "BOTH DESTROYED" |
| ENDED | fades out | | | | |

Timing: INCOMING appears at the launch beat (fade + slide down 16 px over `DUR_FAST`; Reduce motion: fade). It switches to ACTIVE at arrival with a 120 ms cross-fade. REFLECTED / ABSORBED / COLLISION hold 1200 ms, then fade over 300 ms. ACTIVE fades out at the payload end.

**Telegraph lead:** the alert, the edge flash (6.5), the SFX ping and the warhead rings (7.1) all start on the launch beat, at least 1 beat before arrival (TORP-04). A harness check asserts that the alert's first visible frame is at least `torpedo_travel_beats` before `arrive_t`.

### 6.4 Event banner (Solo Duel, Last Hull Standing, your Implosion) (`src/ui/versus/event_banner.gd`) (S-11, D-22, D-24)

Uses the section banner rect x 640..1280, y 200..272 and its look (U-4.9). It has priority over section names: while an event banner is visible, `SectionBanner` does not show (the section name stays in the progress track). Priority, highest first: IMPLOSION (yours) > LAST HULL STANDING > SOLO DUEL states > section.

| Banner | Chrome | Caption (Label 20, centred x 960, baseline 224) | Headline (Heading 40, centred, baseline 262) | Right caption (Label 20, right-aligned x 1264, baseline 224) | Timing |
|--------|--------|------|------|------|--------|
| SOLO DUEL, 1 bar ahead | glass, brackets `REWARD_GOLD` | "SOLO DUEL" `REWARD_GOLD` | "{min}% PERFECT WINS A REWARD" `TEXT_HI` (min from config, e.g. 85) | "{n} NOTES" `TEXT_MID` | Slide down 24 px + fade `DUR_BASE`; stays until the solo starts |
| SOLO DUEL, live | same | "SOLO DUEL" `REWARD_GOLD` | "YOU {p}%" (`SONAR_PALE` if p >= min, else `TEXT_HI`); "YOU --%" before the first solo note | "LEADER {NAME} {q}%" `TEXT_MID` (best living rival) | Progress line: 2 px `SONAR` across the banner bottom (y 270..272), fills with the solo's time |
| SOLO DUEL, live, you are a wreck | same | "SOLO DUEL" | "WRECKS SIT THIS ONE OUT" `TEXT_MID` | leader as above | |
| SOLO DUEL, result: you won | brackets `REWARD_GOLD`, panel glow `REWARD_GOLD` 18% (Full) | "SOLO DUEL" `REWARD_GOLD` | "YOU WIN THE SOLO" `REWARD_GOLD` | "{p}% PERFECT" `TEXT_MID` | Hold 1600 ms, fade 300 ms. The reward-ready popup (5.4, "SOLO PRIZE") follows |
| SOLO DUEL, result: rival won | glass | "SOLO DUEL" | "{NAME} WINS THE SOLO" `TEXT_HI` | "{q}% PERFECT" `TEXT_MID` | Hold 1600 ms |
| SOLO DUEL, result: no winner | glass | "SOLO DUEL" | "NO WINNER" `TEXT_HI` | "BEST {q}% · NEEDED {min}%" `TEXT_MID`, or "TIED" when the tie-break also tied | Hold 1600 ms |
| LAST HULL STANDING | brackets `REWARD_GOLD` if you won, else glass | "LAST HULL STANDING" `REWARD_GOLD` / `TEXT_HI` | "YOU WIN" `REWARD_GOLD` / "{NAME} WINS" `TEXT_HI` | "SONG PLAYS ON" `TEXT_LO` | Hold 2400 ms, fade 300 ms |
| IMPLOSION (you, mid-match) | `danger` variant | "HULL BREACHED" `WARNING_RED` | "IMPLOSION" `WARNING_RED` | "YOU ARE A WRECK" `TEXT_MID` | Hold 2400 ms. Plus a full-screen red vignette (U-9.2 vignette, `WARNING_RED` 22% at the corners) fading over 600 ms. 8 px horizontal shake of the banner over 120 ms (none under Reduce motion). **No FailScreen; the song continues** |

Reduce motion: every banner fades only (no slide, no shake). Low effects: no panel glow.

### 6.5 Edge flash (`src/ui/versus/edge_flash.gd`, full-screen canvas) (D-04)

- Two vertical strips: x 0..16 and x 1904..1920, full height. Each is a horizontal gradient from `WARNING_RED` at the screen edge to 0 alpha at 16 px inward.
- At the launch beat of a threat aimed at you: alpha 0 -> 0.50 over 60 ms, then decays linearly to 0 by the arrival beat. At arrival: one more pulse to 0.30, decaying over 300 ms.
- Photosensitivity: at most 2 pulses per incoming torpedo and never more than 3 pulses per second (a second threat within 333 ms skips its pulse). Strips cover under 2% of the screen.
- Same in all modes (opacity only, so it is already Reduce-motion safe). Implements `keepout_shapes()` returning the two strip rects (it is a full-screen canvas, W4 rule).

### 6.6 Killfeed (`src/ui/versus/killfeed.gd`) (S-12, D-32)

**Rect:** x 1544..1896, y 216..400. Four line slots, each 352 x 40, at y 216, 264, 312, 360 (pitch 48). **Newest line on top**; older lines shift down one slot. A 5th line pushes the oldest (bottom) out.

| Part | Spec |
|------|------|
| Line chrome | Fill `ABYSS_700` 92%, chamfer `CUT_SM` (TL/BR), no brackets, no edge |
| Content | One HBox, padding left 16 (20 with a bar), right 12, vertical centre at y + 20. Segments: Label 20 text and 16x16 `UiIcons` glyphs, 4 px gaps. Text max width 324 px |
| Colours | Lines without YOU: text and glyphs `TEXT_MID`. Lines with YOU as the actor (or neutral, e.g. collision, duel): 4 px `SONAR` bar on the left edge, text `TEXT_HI`. Lines with YOU as the victim (a disruptor or debris landed on you, you imploded): 4 px `WARNING_RED` bar, text `TEXT_HI`. The `bounty` glyph is always `REWARD_GOLD` |
| Too long | If a line exceeds 324 px, the payload name collapses to its 16 px glyph. If still too long, callsigns truncate with "..." to 6 characters |
| Enter | Fade in + slide 16 px from the right over `DUR_BASE`; the others shift down over `DUR_FAST`. Reduce motion: fade in only, others jump |
| Life | Full opacity 3600 ms, then fade to 0 over 400 ms (4 s total, S-12). The freed slot closes upward over `DUR_FAST` (Reduce motion: jump) |

**Line formats** (exact; `[g]` = glyph; names are callsigns UPPERCASE, the human is "YOU"):

| Event | Line |
|-------|------|
| Disruptor landed | `{A} [arrow_right] {Payload} [arrow_right] {B}` (e.g. "ORCA ⟶ Ink Cloud ⟶ YOU", arrows drawn as glyphs) |
| Reflected | `{B} [reflect] REFLECTED {Payload}` |
| Absorbed by Decoy | `{B} [shield] blocked` |
| Collision | `{A} [cross] {B} collided` |
| Bounty claimed | `[bounty] {A} claimed the bounty on {B}` |
| Solo Duel won | `{A} wins the solo` |
| Implosion | `[skull] {A} imploded` |
| Wreck debris landed (D-25) | `[skull] {A} [arrow_right] {Silt/Groan} [arrow_right] {B}` (from-name in `TEXT_LO` on non-YOU lines) |
| Training (your torpedo hits the drone) | `YOU [arrow_right] {Payload} [arrow_right] DRONE` |

The killfeed reads only from the EventChannel (S-12). Buff use, Ballast and LAST HULL STANDING produce no line.

---

## 7. Board Visuals (Disruptors on Your Highway)

All board visuals are drawn by `Highway`/`HighwayNotes`/`NotePainter` and the new `InkCloudLayer`/`InkTopLayer`. The view reads modifier state from the target's `PayloadStack` each frame and never decides rules (D-28). Effects that change readability are **identical in Full, Low effects and Reduce motion** unless a row says otherwise (S-Constraints: ghost and jam readable on Low).

### 7.1 Warhead notes (Return to Sender) (PAY-06, D-16, D-17)

- Marked at the **launch beat** (D-05), on the first `warhead_count` base notes at or after arrival (whole chords).
- `NotePainter` draws the normal gem plus a **warhead ring**: circle at r + 8, 3 px `WARNING_RED`, with a 2 px `KEYLINE` outside it, and a filled chevron (10 x 6 px, pointing up = "send it back") `WARNING_RED` centred 6 px above the ring top.
- Contrast (V): `WARNING_RED` vs lane strips at x4 tint 4.37..4.82:1 (>= 3:1 for a graphic), and the keyline guarantees the edge on any background.
- Judged Perfect: the ring flashes `SONAR_PALE` (r + 8 -> r + 20, alpha 1 -> 0, 200 ms) and the `REFLECT k/n` counter updates (6.3). Judged Good or Miss: the remaining warhead rings on that payload drop to `TEXT_LO` 50% at once (reflect chance gone).
- Visible in all effect modes and under Sonar Jam. Not drawn on reflected torpedoes or debris (no warheads).

### 7.2 Ghost Notes (`NOTE_GHOST`) (PAY-03, D-11, D-12)

| Layer | Spec |
|-------|------|
| Halo | none (all modes) |
| Keyline | Shape outline at r + 2, 2 px `KEYLINE` (solid, under the dashes) |
| Core | **none** (hollow; the strip shows through) |
| Rim | Lane shape outline at r, 3 px, **dashed**: 8 dashes per shape perimeter, 60% dash / 40% gap, colour `Palette.rim_far(lane)` (far) or `rim_ready(lane)` (ready) |
| Centre mark | none |

- Contrast (V): far rim vs its lane strip 7.72..10.61:1; ready rim 10.41..11.99:1.
- Ghost hit: popup "GHOST" in the judgment popup style (U-7.3), `WARNING_RED` with a 3 px `KEYLINE`; the ghost shatters into 4 dash fragments that drift outward 12 px and fade over 250 ms (Reduce motion: fade only, no drift); the hull arc damage flash plays (U-4.7). No hit burst.
- Ignored ghost: it passes the hit line and fades out over 150 ms below it (no X, no MISS).
- A ghost never has a warhead ring.

### 7.3 Depth Charge notes (`NOTE_DISRUPTOR`) (PAY-05, D-14)

- Drawn exactly like `NOTE_NORMAL` (they are real notes) plus a **charge mark**: a filled circle r = 0.22 r in `ABYSS_900`, with a 1 px `mix(lane, white, 0.55)` ring at the same radius, at the gem centre. The gem stays solid and bright, so "hit it" reads at a glance, unlike the hollow ghost.
- They enter at the far end of the highway (Pitfall 1). A harness check asserts their first drawn depth is >= `Trench.D_FAR`.
- Judgments, bursts and popups are the normal ones.

### 7.4 Ink Cloud (`src/ui/versus/ink_cloud_layer.gd` + `InkTopLayer`) (PAY-04, D-13)

| Part | Spec |
|------|------|
| Band | Opaque `ABYSS_900` polygon over the lane area (f -2..+2) for depth d in [-0.15, 0.35] (`Trench.point` corners; never hard-coded pixels) |
| Top edge (Full) | A 32 px feather above d = 0.35: 6 overlapping `GLOW_TEX` sprites in `ABYSS_900` (normal blend, not additive) drifting sideways +/-12 px over 4 s, so the edge reads as a cloud |
| Top edge (Low effects) | Flat band; a 1 px `TEXT_LO` 35% line at d = 0.35 marks the edge |
| Top edge (Reduce motion) | Feather sprites drawn but static |
| InkTopLayer (above the ink) | Hit line ticks (U-7.4 row 5) at 60%; receptor outlines in the lane colour at 60%, 4 px; receptor press fill (lane colour 40%) so presses still register visually; lane numbers at 90%. Contrast of a 60% receptor outline on `ABYSS_900` (V): 3.28 (magenta) .. 5.15 (lime) >= 3:1 |
| Hidden under the ink | Gems, sustains, bursts and judgment popups inside the band (that is the disruption) |
| In / out | Ink alpha 0 -> 1 over 1 beat at arrival, 1 -> 0 over 1 beat at the end (beat-locked; same under Reduce motion, it is an opacity change) |
| Debris "Silt" | Same visuals with d in [-0.15, 0.20], 1 bar |

### 7.5 Pressure Crack (PAY-01, D-09)

- Scroll multiplier eases 1.0 -> 1.5 over 1 beat (smoothstep) at arrival and back over 1 beat at the end, capped by `pressure_crack_max_speed`.
- Cue: both outer rails (U-7.4 row 3) blend toward `WARNING_RED` (rail colour = `mix(SONAR, WARNING_RED, k)` where k is the ease factor 0..1, so the rail is fully `WARNING_RED` at peak; the earlier 0.6 factor gave a pale pink-grey that read as white, 03-REVIEW WR-11). Rail glow follows the tier rule (none on Low).
- Debris "Groan": x1.25, same cue at k max 0.5.
- No other change; gems are untouched.

### 7.6 Sonar Jam (D-15)

| Part | Spec |
|------|------|
| Gems | Every gem (normal, depth charge, chord) is drawn as a plain circle of radius r: core `JAM_GREY`, keyline as normal, rim `TEXT_HI` 2 px (ready) / `TEXT_MID` (far). No lane shape, no lane colour, no top-light, no halo |
| Sustains | Ribbon `JAM_GREY` 45%, core line `TEXT_HI` 70% |
| Chord bars | Unchanged (`SONAR_PALE` 50%) |
| Unchanged | Receptors, lane strips (lane tint), lane numbers, warhead rings. Position is the counterplay, so position cues stay |
| In / out | Colour cross-fades from lane to `JAM_GREY` over 1 beat (all modes) |
| Contrast (V) | `JAM_GREY` core vs x4 lane strips 6.99..7.71:1; `TEXT_HI` rim 11.79..13.00:1 |

### 7.7 Crossed Wires (D-10)

| Part | Spec |
|------|------|
| Slide | The two swapped lane columns (strip, gems, sustains, receptor) slide to each other's position over 1 beat (cubic in-out), at arrival and back at the end |
| Swap guides | During each slide: two curved arrows (2 px `SONAR_PALE` 70%, 8 px filled heads) arc between the swapped receptors, 40 px below the hit line (y ~970), fading out at the end of the slide |
| While crossed | The two swapped strips get a 2 px dashed `SONAR_PALE` 50% edge on both sides (12 px dash, 8 px gap) so the player can see which lanes are crossed |
| Lane numbers (key labels) | Always show the key that currently hits the receptor above them (U-4.16 "bound key under each receptor"). With the D-10 remap (input follows screen position, switched at the end of the slide), the labels stay at their screen positions and do not slide. If the planner implements the spec's alternative reading (input follows lane colour), the labels slide with their lane instead. The rule "label = key that hits this receptor now" is the contract either way |
| Reduce motion | No slide: the two columns cross-fade (old position out, new position in) over 1 beat; swap guides drawn static for that beat |
| Low effects | Same as Full (gameplay information) |

---

## 8. Solo Dive Training (MATCH-06, D-27)

### 8.1 Rename

"Practice Dive" becomes **"Solo Dive"** in all player-facing copy (menu, start button, chips, results flags, not-recorded line). Code identifiers (`run_practice`, `pending_practice`) may stay. Seven test files assert the old strings (V: `grep` count 7) and must be updated in the same plan.

### 8.2 Song Select training row (Solo Dive mode only)

In Solo Dive mode the detail panel's visualizer area (U-6, x 1080..1832, y 760..816) is replaced by the training row:

| Part | Spec |
|------|------|
| Caption | "TRAINING TORPEDOES" Label 20 `TEXT_LO` at (1080, 760) |
| Stepper | Rect x 1080..1832, y 768..816 (48 tall), compact control look (U-4.2 48 px, chamfer `CUT_SM`): `chevron_left` 24 px at x 1096, value Body 28 `TEXT_HI` centred x 1456, `chevron_right` at x 1792. Value glyph 24 px left of the value text when a single payload is chosen |
| Values (cycle order) | "OFF", "ALL", "CROSSED WIRES", "GHOST NOTES", "INK CLOUD", "PRESSURE CRACK", "SONAR JAM", "DEPTH CHARGE" |
| Description | Replaces the section names line while the stepper value changed in the last 3 s: the reward's one-line description (4.1), "Train without torpedoes." for OFF, "The drone fires every disruptor in turn." for ALL. Label 20 `TEXT_MID` at baseline 728 (8 px above the section names line, so it clears the "TRAINING TORPEDOES" caption at 760; 03-REVIEW WR-12) |
| Input | Keyboard F3 = next, Shift+F3 = previous. Gamepad right trigger = next, left trigger = previous (both currently unused in Song Select, V). The value persists in `Settings` |
| Footer hint (Solo Dive mode) | "UP DOWN SONG  ·  LEFT RIGHT DIFFICULTY  ·  F3 TRAINING  ·  ENTER DIVE  ·  ESC BACK"; gamepad "D-PAD SONG  ·  LEFT RIGHT DIFFICULTY  ·  LT RT TRAINING  ·  A DIVE  ·  B BACK" |
| Start button | "Start Solo Dive" |

### 8.3 In-dive training HUD

- Chips: NO-FAIL (forced) and "SOLO DIVE" `mode` chip (replaces "PRACTICE DIVE").
- Periscope P1 = "DRONE": hull bar replaced by "TRAINING" Label 20 `TEXT_LO`; status line "NEXT IN {n} BARS"; threat block shows your torpedoes hitting the drone.
- Your socket, target readout ("DRONE"), alert slot, warheads, killfeed and buffs work exactly as in versus. No PLACE or BOUNTY chips. No Solo Duel.
- Training OFF: no drone panel, no killfeed, no socket changes beyond the meter (the meter, bag and buffs still run so the player can learn them).

---

## 9. Screens

### 9.1 Main menu (U-5 update)

Nine items now (V: current menu has 8 at `ITEM_TOP` 416, pitch 64, height 56). New layout: `ITEM_TOP` **392**, pitch 64, height 56 -> tops 392..904 (last ends 960). Focus description baseline **1000** (was 960), status line baseline **1040** (was 1000). The last-dive card (x 1376..1856, y 840..1000) is unchanged. The calibration prompt and logo are unchanged.

| # | Item | Icon | Variant | Description (focus line) |
|---|------|------|---------|--------------------------|
| 1 | Start Dive | `dive` | primary | "Pick a song and dive. Your hull is on the line." |
| 2 | **Versus Bots** | `versus` | default | "Race up to 3 bot subs down the trench. Last hull standing wins." |
| 3 | **Solo Dive (No-Fail)** | `lifebuoy` | default | "Dive without imploding, with optional training torpedoes. Records are not saved." |
| 4 | Chart a Song | `chart` | default | kept |
| 5 | Calibrate Sonar | `sonar` | default | kept |
| 6 | Settings | `sliders` | default | kept |
| 7 | Autoplay Dive (test) | `auto` | default | kept |
| 8 | Open Songs Folder | `folder` | default | kept |
| 9 | Quit Game | `power` | default | kept |

Focus wraps top <-> bottom (kept). Entrance stagger: 8 gaps x 40 ms = 320 ms would exceed the U-3.4 cap, so `STAGGER_MENU` drops to 35 ms (8 x 35 = 280 ms).

### 9.2 Match setup (`scenes/match_setup.tscn`, `src/ui/versus/match_setup_screen.gd`) (MATCH-01, D-18)

Reached from Versus Bots, and from "Change Match" on versus results. Background `AbyssBackdrop` `table`. Sonar wipe in and out (U-9.7).

| Region | Rect / position | Content |
|--------|-----------------|---------|
| Title | (64, 104) | "VERSUS" Heading 40 `TEXT_HI` |
| Subtitle | (64, 140) | "Offline match against bot subs. Last hull standing wins." Label 20 `TEXT_MID` |
| Settings panel | x 64..944, y 176..904 (glass, U-4.1) | Caption "MATCH" Label 20 `SONAR` at (96, 216) |
| Row Song | x 96..912, y 240..304 (64 tall, button look) | Label "Song" Body 28 `TEXT_MID` at x 120; value Body 28 `TEXT_HI` at x 400 truncated at 456 px; `chevron_right` at x 872. Accept opens Song Select in pick mode (8.4) |
| Row Difficulty | y 312..376 | Label "Difficulty" at x 120; value = `difficulty` chip at x 400 with `chevron_left`/`chevron_right` at x 368 / x 872. Left/Right cycles the difficulties the song has |
| Row Rivals | y 384..448 | Label "Rivals" at x 120; segmented selector: 3 tiles 96 x 48 at x 400, 504, 608 (y 392..440), text "1", "2", "3" Body 28 |
| Row Bot skill | y 456..520 | Label "Bot skill" at x 120; 3 tiles 160 x 48 at x 400, 568, 736 (y 464..512): "ROOKIE", "REGULAR", "VETERAN" Label 20 |
| Skill description | x 120, baseline 560 | Label 20 `TEXT_MID` (copy in 14) |
| Divider | y 592, x 96..912 | 2 px `SONAR` 35% |
| How it works | caption (120, 632) "HOW REWARDS WORK" Label 20 `SONAR`; 4 lines Label 20 `TEXT_MID` at baselines 672 / 704 / 736 / 768 | Copy in 14; key names come from `BindingStore` |
| Start Match | x 96..912, y 808..872 (64 tall), primary variant, key hint "ENTER" | Disabled (U-4.2 disabled) when no song is chosen |
| Preview panel | x 976..1856, y 176..904 (glass) | Album cover 256 at (1008, 208); title Heading 40 at x 1288, baselines 248 / 296 (2 lines + "..."), max 544 px; artist Body 28 `TEXT_HI` baseline 336; difficulty chip y 352..384 at x 1288; "{N} NOTES · REWARD EVERY {T} PERFECTS" Label 20 `TEXT_MID` baseline 424 (T = live threshold for the chosen chart); divider y 464 |
| Roster | caption "SUBS IN THIS MATCH" Label 20 `TEXT_LO` (1008, 504); rows 56 tall, pitch 64, at y 520, 584, 648, 712 | Each row: callsign Body 28 `TEXT_HI` at x 1032 ("YOU" first, then bot callsigns in seat order); right-aligned at x 1824 a `mode` chip with the skill ("VETERAN") or `info` chip "YOU". Rows appear/disappear with the Rivals value (fade `DUR_BASE`) |
| Hint | (64, 960) | "UP DOWN MOVE  ·  LEFT RIGHT CHANGE  ·  ENTER SELECT  ·  ESC BACK" Label 20 `TEXT_LO`; gamepad "D-PAD MOVE  ·  LEFT RIGHT CHANGE  ·  A SELECT  ·  B BACK" |

Selector tiles: idle = button idle (U-4.2); **selected** = fill `ABYSS_600` 92%, 2 px `SONAR` edge, text bold `TEXT_HI`, plus a 24 x 4 `SONAR` bar under the tile (shape cue, like U-4.11); **row focused** = focus marker on the row (U-4.3), with the selected tile also showing its focus glow.

**Focus order (Up/Down, wraps):** Song -> Difficulty -> Rivals -> Bot skill -> Start Match. Initial focus: Start Match when a song is set, otherwise Song. Left/Right changes the focused row's value (`move` blip); on Song and Start Match it does nothing. Accept on Song opens song pick, on Start Match starts the match (sonar wipe -> goggles intro). Esc / B returns to the main menu (no confirm; nothing is lost). Defaults: last used values in `Settings`; first run = 3 rivals, REGULAR, last played song.

### 9.3 Song pick mode (Song Select reused)

Opened from Match setup. Same screen, with: header `info` chip "VERSUS" right-aligned to x 744 (16 px left of the sort chip at x 760), y 72..104; the primary button reads "Pick Song" (Enter / A); Esc / B returns to match setup without changing the song. Training row hidden.

### 9.4 Versus results (`src/ui/versus/versus_results_screen.gd`) (MATCH-05, S-13, D-22, D-23)

Opaque, like U-8 (`AbyssBackdrop` `calm` at 100% + `ABYSS_900` 55%). Versus never writes records (D-23).

| Region | Rect / position | Content |
|--------|-----------------|---------|
| Header | x 96..1824, y 64..176 | "MATCH COMPLETE" Label 20 `SONAR` +4 spacing at (96, 88). Headline Heading 40 at (96, 136): "YOU WIN" `REWARD_GOLD` or "{NAME} WINS" `TEXT_HI` (or "DRAW" `TEXT_HI` for a shared first place). Body 28 `TEXT_MID` at (96, 172): "{title} · {artist}", then the `difficulty` chip 16 px after it. Right: `muted` chip "NOT RECORDED" right-aligned to x 1824, y 72..104; "Versus matches do not set records." Label 20 `TEXT_LO` right-aligned x 1824, baseline 136; "SEED {n}" Label 20 `TEXT_LO` right-aligned x 1824, baseline 168 (D-18 repro) |
| Standings panel | x 96..1824, y 208..712 (glass) | Column captions Label 20 `TEXT_LO`, baseline 248: "PLACE" x 128, "SUB" x 248, "DEPTH" right-aligned x 776, "ACCURACY" right-aligned x 960, "LANDED" centred x 1072, "REFLECTED" centred x 1184, "MEDALS" x 1264 |
| Rows (1..4, in placement order) | y 272, 376, 480, 584; each 96 tall (8 px gap) | See row table |
| Buttons | y 752..816 | "Rematch" (primary) x 96..496; "Change Match" x 520..920; "Back to Menu" x 944..1344. Initial focus Rematch. Left/Right and Up/Down move focus (U-8 rule) |
| Hint | (96, 872) | "ENTER SELECT  ·  ESC BACK TO MENU" / "A SELECT  ·  B BACK TO MENU" Label 20 `TEXT_LO` |
| Your medals legend | x 96, baselines 920 / 952 / 984 / 1016 | Caption "YOUR MEDALS" Label 20 `TEXT_LO` (baseline 920); then one line per medal YOU earned, Label 20 `TEXT_MID`: "{MEDAL NAME}: {rule text}" (copy in 14). None: "No medals this time. Reflect a torpedo, win a solo or survive a dogpile to earn one." |

**Row layout (row top = yr):**

| Column | Spec |
|--------|------|
| Row chrome | YOU row: fill `ABYSS_600` 92% + 4 px `SONAR` bar on the left edge (same "this is you" language as the killfeed). Other rows: no fill. 1 px `SONAR` 20% divider between rows |
| Place | Heading 40 at x 128, baseline yr + 60: "1ST" `REWARD_GOLD`, others `TEXT_HI`. Shared place shows the same ordinal |
| Sub | Callsign Heading 40 `TEXT_HI` at x 248, baseline yr + 48 (max 384 px). Status Label 20 at x 248, baseline yr + 80: "LAST HULL STANDING" `SONAR_PALE` / "SURVIVED · HULL {h}%" `TEXT_MID` / "IMPLODED AT {m:ss}" `WARNING_RED` |
| Depth | Heading 40 `SONAR` right-aligned x 744, baseline yr + 60; " M" Label 20 `TEXT_LO` at x 752 |
| Accuracy | Heading 40 `TEXT_HI` right-aligned x 960, baseline yr + 60 ("98.4%", U-4.13 formula) |
| Landed / Reflected | Heading 40 `TEXT_HI` centred x 1072 / x 1184, baseline yr + 60 (reflected = disruptors this player reflected; a reflected shot does not count as landed for the shooter, CONTEXT) |
| Medals | Up to 3 medal badges at x 1264, 1444, 1624 (168 px columns). Badge: 48 x 48 octagon (16 px cuts on all four corners, declared badge exception like U-4.13) centred in its column at yr + 8..yr + 56, fill `ABYSS_600` 92%, 2 px `REWARD_GOLD` edge, medal glyph 24 px `REWARD_GOLD` centred. Name Label 20 `TEXT_HI` UPPERCASE centred in the column, baseline yr + 84 (max 168 px; "BOUNTY HUNTER" is 13 characters, about 156 px). No medals: "-" Label 20 `TEXT_LO` at x 1264, baseline yr + 60 |

**Entrance (total <= 900 ms, any input skips to the final state):** header fades in (`DUR_BASE`); rows rise 16 px + fade in, 60 ms stagger in placement order; then medals pop (scale 1.4 -> 1.0, alpha 0 -> 1, `DUR_BASE` back-out, 60 ms stagger, row by row); the winner's place label gets glow_sm `REWARD_GOLD` (Full only). Reduce motion: fades only. Low effects: no glow.

**Gamepad/keyboard:** only the 3 buttons are focusable; the table is read-only. "Rematch" = same song, difficulty, rivals and skill with a new seed. "Change Match" = Match setup with the current values. "Back to Menu" = main menu. Esc / B = Back to Menu.

### 9.5 Pause in versus (U-9.1 update)

Same panel and layout. Run line: "{title} · {DIFFICULTY} · VERSUS · {nn}%". Buttons: "Resume Match" (primary), "Restart Match", "Settings", "Leave Match". Bots pause with the song clock (D-23). Confirm dialogs (U-9.6, destructive variant, initial focus on the safe button):

| Action | Title | Body | Confirm / Cancel |
|--------|-------|------|------------------|
| Restart Match | "RESTART" | "Restart this match from the beginning? Everyone's progress will be lost." | "Restart Match" / "Keep Playing" |
| Leave Match | "LEAVE MATCH" | "Leave this match? It ends now and nothing is saved." | "Leave Match" / "Stay" |

Solo Dive pause keeps the solo copy (U-14) with "Dive" wording.

### 9.6 End of song in versus

No FailScreen in versus. At song end: the standard end hold, then a sonar wipe to Versus results (U-9.7). If the human imploded, the song still plays to the end (D-22) and results come at the song end.

---

## 10. Input and Focus (gameplay)

| Action | Keyboard | Gamepad | Effect | Feedback |
|--------|----------|---------|--------|----------|
| Fire (`fire`) | Space | A | Uses the held reward (S-4) | 5.1 socket states; refusal 5.2 |
| Cycle target (`target_cycle`) | H | Y | AUTO -> each living rival in seat order -> ATTACKERS -> AUTO (D-01) | 5.2 value + 6.2 reticle |
| Pause | Esc | Start | U-9.1 | |

Both actions already exist in the InputMap and the rebind UI (V, research). All HUD hints show the current binding label, never a hard-coded key. Fire and target presses are ignored (no blip) when there is nothing to fire; the target cycle still works without a reward so players can pre-aim.

---

## 11. Accessibility and Readability of Telegraphs

1. **Never colour alone** (U-13 rule 4), applied to every new signal:
   - disruptor vs buff: icon + name + ring colour;
   - incoming: word "INCOMING", countdown ring shape, edge flash, SFX ping, warhead ring + chevron on the board;
   - target: reticle + caret + brighter edge + name in the target readout;
   - bounty: crosshair glyph + "BOUNTY ON YOU" text + gold brackets;
   - you in lists: 4 px bar + brighter text + the word "YOU";
   - ghost vs real: hollow dashed vs solid filled;
   - depth charge vs normal: centre charge mark;
   - Sonar Jam: circles + keylines remain; positions and receptors unchanged.
2. **Telegraph lead >= 1 beat** (TORP-04): all four cues (alert slot, edge flash, SFX, warhead rings) start on the launch beat. At 200 BPM that is 300 ms of warning, the shortest supported case.
3. **Text contrast:** every new text sits on `ABYSS_700` 92% glass, a console, or a `KEYLINE` outline. Worst case (V, `WALL_TEAL` at 100% behind the glass): `TEXT_LO` 5.21:1, `WARNING_RED` 4.79:1; `TEXT_HI`/`TEXT_MID`/`SONAR`/`SONAR_PALE`/`REWARD_GOLD` are higher (11.30 / 6.70 / 8.03 / 11.99 / 9.82 measured at the lower 82% alpha).
4. **Low effects never removes information:** ghosts, warhead rings, jam circles, ink edges, swap guides, countdown rings and edge flashes are identical or have a flat equivalent (section 12).
5. **Reduce motion keeps gameplay information:** Crossed Wires changes from a slide to a cross-fade over the same beat, and no cue is dropped.
6. **Photosensitivity:** no element flashes more than 3 times per second; edge flash rules in 6.5; the full-meter breathing is 1.6 s.
7. **Readable at a glance:** rival panels never pulse or blink in a loop (only one-shot flashes), so the periphery stays calm while you read notes.
8. **Readability harness shots** (added to the U-15 set): each disruptor at scroll 1x and 3x in Full and Low; Sonar Jam + warheads; Ink Cloud with a held sustain; Crossed Wires mid-slide and settled; alert slot in each state; 3 periscope panels with bounty + target on the same panel; killfeed with 4 lines (one long line collapsed); Solo Duel live; versus results with 4 rows and 3 medals; match setup; training stepper.

---

## 12. Low Effects and Reduce Motion (additions to the U-11 master table)

Each node below registers via `UiKit.register_fx` and reports `effect_counts()`. `test_effect_settings.gd` enumerates them.

| Node / effect | Full | Low effects | Reduce motion |
|---------------|------|-------------|---------------|
| `RewardSocket` full-arc breathing | breathing + glow_sm | breathing, no glow | static |
| `RewardSocket` earn pop / launch shrink | on | on | fade only |
| `RewardPopup` | pop + hold + fade | same | fade only |
| `TargetReadout` glyph pulse | on | on | off |
| `StatusChips` pop / re-pack slide | on | on | fade / jump |
| `PeriscopePanel` sweep line + blips | sweep, 6 blips | no sweep, 2 blips | no sweep, blips fade in place |
| `PeriscopePanel` glow | panel glow 18% | none | static |
| Reticle / caret glide | glide `DUR_FAST` | glide | jump |
| Collision ring burst | on | on | fade only (no radius change) |
| `AlertSlot` slide in | slide + fade | slide + fade | fade |
| `EventBanner` slide / shake / glow | on | no glow | fade only, no shake |
| `EdgeFlash` | on | on | on (opacity only) |
| Killfeed enter slide / shift | on | on | fade / jump |
| Warhead Perfect flash | on | on | on (no ring growth: alpha flash only) |
| Ghost shatter | fragments drift | fragments drift | fade only |
| Ink edge | drifting feather | flat band + edge line | static feather |
| Ink / Jam fade in-out | 1 beat | 1 beat | 1 beat |
| Crossed Wires | slide + guides | slide + guides | cross-fade + static guides |
| Pressure Crack rail tint | tint + tier glow | tint, no glow | tint |
| Results medal pop / winner glow | on | pop, no glow | fade only |
| In-match IMPLOSION vignette | on | on | on (fade) |

Performance: Phase 3 adds at most 1 shared ring/flash pool per board and no new particle systems except the reused ghost-shatter fragments (drawn in `_draw`, not particles). The U-12 budget (p95 <= 4.35 ms Full) still applies with 3 bots running, measured on the dense passage with Ink Cloud active.

---

## 13. Layout and Contract Tests (for the planner)

| Test | Extension |
|------|-----------|
| `test_layout_keepout.gd` | Scan `VersusHud` (all children) and the new `Hud` children. `PeriscopeColumn`, `Killfeed`, `AlertSlot`, `EventBanner`, `EdgeFlash`, `RewardPopup` implement `keepout_shapes()` if full-screen. Assert exact rects: periscope P1..P3 = (24,216,352,88), (24,312,352,88), (24,408,352,88); killfeed = (1544,216,352,184); alert slot = (640,120,640,72); event banner = (640,200,640,72); target readout = (248,752,144,88); reward socket = (272,928,80,80) |
| `test_color_literals.gd` | Covers `src/ui/versus/**` automatically (scans `src/ui/**`) |
| `test_contrast.gd` | Add rows: C20 `JAM_GREY` vs x4 strips (min 6.99, needs 4.5); C21 jam rim `TEXT_HI` vs strips (min 11.79); C22 warhead `WARNING_RED` vs strips (min 4.37, needs 3.0 graphic); C23 ghost rim far vs strip (min 7.72, needs 4.5); C24 HUD glass worst case (`ABYSS_700` 92% over `WALL_TEAL`): `TEXT_LO` 5.21, `WARNING_RED` 4.79 (needs 4.5); C25 ink receptor outline (lane 60% over `ABYSS_900`) min 3.28 (needs 3.0) |
| `test_effect_settings.gd` | Enumerates the section 12 nodes |
| `test_ui_icons.gd` (or existing icon test) | All section 4 names draw |
| `test_killfeed.gd` | One line per event type with the exact formats in 6.6; 5th line pushes the oldest; 4 s life; overlong line collapses the payload name to a glyph; every text character `has_char` in Share Tech Mono |
| `test_visual_sync.gd` | Gem on the hit line at its time under Crossed Wires (after the slide) and Pressure Crack |
| Harness | Alert visible >= 1 beat before arrival; depth-charge first draw at the far end; screenshot set in 11.8 |

---

## 14. Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | "Start Match" (match setup). Results: "Rematch". Pause: "Resume Match". Solo Dive: "Start Solo Dive". Song pick: "Pick Song" |
| Main menu | "Versus Bots": "Race up to 3 bot subs down the trench. Last hull standing wins." · "Solo Dive (No-Fail)": "Dive without imploding, with optional training torpedoes. Records are not saved." |
| Match setup | Title "VERSUS"; subtitle "Offline match against bot subs. Last hull standing wins."; caption "MATCH"; rows "Song", "Difficulty", "Rivals", "Bot skill"; tiles "1" "2" "3", "ROOKIE" "REGULAR" "VETERAN"; caption "SUBS IN THIS MATCH"; "{N} NOTES · REWARD EVERY {T} PERFECTS" |
| Skill descriptions | Rookie: "Loose timing and frequent misses. Rarely earns a reward." · Regular: "Solid timing. Earns a reward now and then." · Veteran: "Tight timing. Earns about 3 rewards a song." |
| How rewards work | "Unbroken Perfects fill your torpedo tube. A full tube loads a random reward." · "{FIRE} fires it. Disruptors hit your target. Buffs help you." · "{TARGET} switches target: AUTO, each rival, ATTACKERS." · "Hit the red-ringed notes Perfect to send a torpedo back." |
| Match setup empty state | Song row value "No songs installed" `TEXT_LO`; skill description line replaced by "Add songs with Open Songs Folder on the main menu." Start Match disabled |
| Match setup error | Song failed to load at start: existing copy "This song's audio could not be loaded. Choose another song." shown in the status line (Label 20 `WARNING_RED` with "!" glyph) at (64, 1000) |
| Socket | "{m}/{t}", reward HUD names (4.1), "DEBRIS {m}/{t}", "SILT", "GROAN", "NO DEBRIS LEFT" |
| Reward popup | "REWARD READY · {FIRE}", "SOLO PRIZE · {FIRE}", "PRIZE QUEUED" |
| Target readout | "AUTO TARGET", "TARGET", "ATTACKERS", "DEBRIS TARGET", "NONE", "DRONE", "SHIELDED", "NO TARGET", "BOUNTY +{n}" |
| Chips | "1ST OF 4" (ordinals 1ST/2ND/3RD/4TH, "OF {n}"), "BOUNTY ON YOU", "DECOY ARMED {n}", "OVERCLOCK {n}", "HULL +25", "IMMUNE", "SOLO DIVE" |
| Judgment additions | "GHOST" |
| Alert slot | "INCOMING · {FROM}", "REFLECTED BY {FROM}", "WRECK DEBRIS · {FROM}", "ACTIVE · {FROM}", "HIT RINGED NOTES PERFECT", "CANNOT BE REFLECTED", "DECOY WILL ABSORB", "REFLECT {k}/{n}", "{n} BARS LEFT" (1 -> "1 BAR LEFT"), "REFLECTED", "BACK TO {FROM}", "DECOY ABSORBED", "HEAD-ON COLLISION", "BOTH DESTROYED" |
| Event banner | "SOLO DUEL", "{min}% PERFECT WINS A REWARD", "{n} NOTES", "YOU {p}%", "YOU --%", "LEADER {NAME} {q}%", "WRECKS SIT THIS ONE OUT", "YOU WIN THE SOLO", "{NAME} WINS THE SOLO", "NO WINNER", "BEST {q}% · NEEDED {min}%", "TIED", "{p}% PERFECT", "LAST HULL STANDING", "YOU WIN", "{NAME} WINS", "SONG PLAYS ON", "HULL BREACHED", "IMPLOSION", "YOU ARE A WRECK" |
| Wreck caption | "WRECK · PERFECTS CHARGE DEBRIS" |
| Periscope | callsign, "1ST".."4TH", "{n} M", "SOLO {p}%", "SOLO --%", "SITTING OUT", "WRECK", "TRAINING", "NEXT IN {n} BARS" ("NEXT IN 1 BAR") |
| Killfeed | Formats in 6.6 (spec wording: "REFLECTED", "blocked", "collided", "claimed the bounty on", "wins the solo", "imploded") |
| Callsigns | Human "YOU". Bots, assigned in this order per match: MAKO, ORCA, BARRACUDA, LAMPREY, NARWHAL, MORAY (D-21; the first 1-3 used, shuffled by the match seed). Training: "DRONE" |
| Training stepper | "TRAINING TORPEDOES", "OFF", "ALL", disruptor HUD names; descriptions (4.1), "Train without torpedoes.", "The drone fires every disruptor in turn." |
| Versus results | "MATCH COMPLETE", "YOU WIN" / "{NAME} WINS" / "DRAW", "NOT RECORDED", "Versus matches do not set records.", "SEED {n}", columns "PLACE" "SUB" "DEPTH" "ACCURACY" "LANDED" "REFLECTED" "MEDALS", statuses "LAST HULL STANDING", "SURVIVED · HULL {h}%", "IMPLODED AT {m:ss}", buttons "Rematch", "Change Match", "Back to Menu", hint as U-8, "YOUR MEDALS" |
| Medal names and rules (legend) | "UNTOUCHABLE: 2 or more disruptors were fired at you and none took effect." · "UNO REVERSE: most reflections in the match." · "BOUNTY HUNTER: most bounties claimed." · "SHREDDER: won a Solo Duel." · "HEAD-ON: your torpedo collided with a rival's." · "GRUDGE: landed 3 or more disruptors on the same rival." · "DOGPILED: every rival targeted you at least once." |
| Results empty state | "No medals this time. Reflect a torpedo, win a solo or survive a dogpile to earn one." Medal column: "-" |
| Solo Dive renames | Chip "SOLO DIVE"; results flag chip "SOLO DIVE"; not-recorded line "Not recorded. Solo, Autoplay and No-Fail dives do not set records." |
| Destructive confirmations | Restart Match: "Restart this match from the beginning? Everyone's progress will be lost." (Restart Match / Keep Playing). Leave Match: "Leave this match? It ends now and nothing is saved." (Leave Match / Stay). No other destructive actions in this phase |

Tone: short, plain, military-sonar terse in captions; sentence case in body lines. Numbers come from config at runtime, never baked into strings.

---

## 15. Implementation Map

| File / node | Purpose |
|-------------|---------|
| `src/ui/palette.gd` | + `HUD_GLASS_ALPHA`, `JAM_GREY` |
| `src/ui/ui_icons.gd` | + section 4 glyphs |
| `src/ui/note_painter.gd` | + `NOTE_GHOST`, `NOTE_DISRUPTOR`, jam variant, warhead ring overlay |
| `src/ui/highway.gd` / `highway_notes.gd` | lane_pos slide, swap guides, rail tint, jam cross-fade |
| `src/ui/versus/ink_cloud_layer.gd` (+ `InkTopLayer`) | 7.4 |
| `src/ui/versus/reward_socket.gd`, `target_readout.gd`, `reward_popup.gd` | 5.1, 5.2, 5.4 |
| `src/ui/hud.gd` | chip stack 5.3, wreck caption 5.5, Overclock GOOD colour (via `Feedback`) |
| `src/ui/versus/periscope_panel.gd`, `periscope_column.gd` | 6.2 |
| `src/ui/versus/incoming_alert.gd`, `event_banner.gd`, `edge_flash.gd`, `killfeed.gd` | 6.3 - 6.6 |
| `src/ui/versus/match_setup_screen.gd` + `scenes/match_setup.tscn` | 9.2 |
| `src/ui/versus/versus_results_screen.gd` | 9.4 |
| `src/ui/main_menu.gd`, `song_select.gd`, `pause_menu.gd` | 9.1, 8.2 / 9.3, 9.5 |

---

## 16. Defaults Log (choices made here, with reasons)

1. **Periscope panels 88 px tall in y 216..496 (refines D-26's ~112 px in y 216..584).** The 02.2 streak milestone popup (centred x 208, baseline 584, rising 32 px) and the new reward-ready popup occupy y ~512..598. A 584 bottom would overlap them.
2. **Buff chips live in the right-console chip stack, not "above the socket" (refines D-33).** The space above the socket holds the PERFECT readout (x 264..356, y 836..904). The chip stack already exists and has 6 free 32 px slots.
3. **Target mode readout in x 248..392, y 752..840 (refines D-01 "under the socket").** Under the socket only y 1012..1080 is left, and it holds the name line. The chosen box is the only free block in the left console near the socket.
4. **Alert slot at y 120..192, a second top slot.** The event banner (section banner rect) is needed for Solo Duel, Last Hull Standing and Implosion, which can overlap an incoming torpedo. Two stacked slots never fight. Both are outside the keep-out, like the 02.2 section banner.
5. **In-game glass at 92% (`HUD_GLASS_ALPHA`).** Red text at 82% fails 4.5:1 over a bright wall ring (4.18). At 92% it passes (4.79).
6. **Rivals' held rewards are visible; their Decoy and Overclock are hidden.** Seeing a loaded tube creates tension and lets players react ("ORCA has Ink Cloud"). A visible Decoy would make it useless.
7. **Killfeed newest on top.** The top of the column is nearest the eye line of the top slots, and the spec's "pushes out the oldest" then removes from the bottom.
8. **Victim lines use a red bar, actor lines a SONAR bar.** The spec only asks for "highlighted". Two colours plus the word YOU say who hit whom without reading the whole line.
9. **Debris lines name the wreck owner with a skull (refines D-25's literal "WRECK").** With 2 or more wrecks, "WRECK" alone is ambiguous.
10. **Reward-ready popup reuses the milestone anchor with no rise.** It keeps all left-side popups in one place and never crosses into the periscope column.
11. **Practice Dive renamed Solo Dive.** MATCH-06 and D-27 call the mode Solo Dive. One name avoids two words for the same mode. The 7 affected test strings are listed for the planner.
12. **Match setup before song pick, with song pick as a sub-mode of Song Select.** Rematch and Change Match need a home that remembers the bots. Reusing Song Select avoids a second song browser.
13. **Main menu re-spaced (top 392, description 1000, status 1040)** to fit 9 items without shrinking buttons.
14. **Training payload stepper on F3 / LT-RT.** Arrow keys and face buttons are taken in Song Select. Triggers and F3 are free (V).
15. **Overclock GOOD drawn in `SONAR_PALE`, word unchanged.** This is honest feedback that also shows the buff working.
16. **Ink hides judgment popups too.** The spec says the band is "blacked out". Receptor outlines, presses and the hit line ticks are redrawn so players can still play by timing.
17. **Crossed Wires key labels follow the "key that hits this receptor" rule.** 03-SPEC's counterplay line ("follow colour/shape") and D-10's position remap read differently. The label rule is correct under either, and the planner should keep the D-10 remap (labels stay put). Flagged for UAT.
18. **Results place in Heading 40, not Display 96.** Four 96 px rows would not fit Display plus medals. The YOU bar and the gold "1ST" carry the emphasis.
19. **Medal badges are 48 px octagons in gold.** This reuses the declared badge exception (U-4.13), and medals are rewards, so gold fits.

## Notes for the checker (non-blocking)

- Typography: still 4 sizes (20/28/40/96) and 2 weights. Display 96 is not used by new elements.
- Colour: no new hues; 2 constants (`HUD_GLASS_ALPHA`, alias `JAM_GREY`). Reserved-for lists extended explicitly in 3.1. Gold stays outside the keep-out.
- Spacing: tokens unchanged; panel height 88, line height 40 and row height 96 are declared exceptions (multiples of 4).
- Open questions for the end-of-phase UAT: (1) Is the alert slot at y 120 noticed in time, or is the edge flash plus warhead rings doing the work? (2) Should Decoy be visible on rival panels? (3) Crossed Wires input reading (Defaults Log 17). (4) Are rival held-reward icons distracting?

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none (not applicable, Godot project) | not required |
| Third-party UI registries | none | not applicable |
| Vendored assets | none new (glyphs are first-party vector code) | not applicable |

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending
