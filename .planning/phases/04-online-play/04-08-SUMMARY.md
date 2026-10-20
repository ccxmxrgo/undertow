---
phase: 04-online-play
plan: 08
subsystem: ui
tags: [ui, versus, event-banner, chips, killfeed, periscope, online]
requires:
  - 04-02 (GameEvent.PLAYER_LEFT {seat, reason})
  - 04-04 (UiKit.chip_style("danger"), UiIcons link_broken)
provides:
  - EventBanner.start_countdown / countdown_text_at / countdown_progress / flight_text
  - EventBanner.show_waiting / hide_waiting / waiting_right_text
  - StatusChips.set_link_weak / is_link_weak, Hud LINK chip (slot 0) + overflow rule
  - Killfeed PLAYER_LEFT line with IMPLODED replace-in-place
  - PeriscopePanel LEFT state (is_left / hull_word / meter_visible)
affects: [04-14 online versus wiring]
tech-stack:
  added: []
  patterns: [online-only states reachable only from new API calls or new events]
key-files:
  created:
    - tests/test_online_views.gd
  modified:
    - src/ui/versus/event_banner.gd
    - src/ui/versus/status_chips.gd
    - src/ui/hud.gd
    - src/ui/versus/killfeed.gd
    - src/ui/versus/periscope_panel.gd
decisions:
  - "Countdown and waiting are new EventBanner.Kind values COUNTDOWN (priority 4) and WAITING (priority 1), appended to the enum so existing values are unchanged"
  - "The countdown hold, fade and end follow song time in observe() (fade from 0.6 s, gone at 0.9 s); step() only runs the entry and the cross-fades"
  - "The Hud overflow rule (drop BALLAST, then IMMUNE) only applies while the LINK chip is on, so the Phase 3 cut-off is unchanged offline"
  - "The PLAYER_LEFT state sets is_wreck() too (LEFT is the wreck state with a different word); the place, held reward and meter stop updating"
  - "Killfeed matching uses the event 't' (song time) and falls back to the line age when either time is missing"
metrics:
  duration: ~35 min
  completed: 2026-10-20
---

# Phase 4 Plan 08: Online states in the in-match views Summary

This plan adds the online states to the Phase 3 in-match views. The event banner gets a MATCH START countdown driven by song time ("DIVE IN 3/2/1", then "DIVE") and a MATCH COMPLETE / WAITING FOR RESULTS state. Clients get a danger chip, "NO HOST SIGNAL", at the top of the right-console stack. PLAYER_LEFT now shows a LEFT periscope state and a "left the match" killfeed line, which replaces that seat's IMPLODED line in place. Every new state is reached only through a new API call or the new event, so the offline views behave as before.

## Tasks

| # | Task | Commit |
|---|------|--------|
| 1 | Event banner countdown and waiting states; link chip in StatusChips and Hud | 839ff05 |
| 2 | PLAYER_LEFT in the killfeed and periscope panel | be605b0 |

## API notes for 04-14 (online versus wiring)

**EventBanner** (`versus_hud`'s event banner):
- `start_countdown(start_receipt_song_t: float, flight_beats: int)`: call it when START is received. Pass the song time at receipt (negative) and the lobby flight in beats. After that, feed `observe(song_time)` every frame as you already do. The digits, "DIVE", the fade and the removal at 0.9 s all follow song time. A receipt time of 0.9 or later never shows the banner.
- `static countdown_text_at(t) -> String` gives "DIVE IN n", "DIVE" or "". `countdown_progress() -> float` goes from 1 at receipt to 0 at song time 0. `static flight_text(n)` gives "FLIGHT n BEATS" or "FLIGHT 1 BEAT".
- `show_waiting(still_diving: int)`: call it when the end hold finishes and RESULTS has not arrived. Pass n from the DONE messages on the host and 0 on clients (which leaves the right caption empty). Calling it again updates the banner in place. `hide_waiting()` fades the banner out. Call it on RESULTS, before the wipe.
- New kinds: `EventBanner.Kind.COUNTDOWN` and `Kind.WAITING`.

**StatusChips / Hud**:
- `StatusChips.set_link_weak(on: bool)`: clients only. Call it with true when no host packet has arrived for at least 1.0 s and with false when packets resume. Never call it on the host. `is_link_weak()` reads the state back.
- `Hud.CHIP_LINK == "LINK"` is now first in `CHIP_ORDER`, and `Hud.CHIP_OVERFLOW_DROP == ["BALLAST", "IMMUNE"]`. `chip_rects()` and `keepout_shapes()` include the chip automatically.

**Killfeed / PeriscopePanel**: both read `GameEvent.PLAYER_LEFT` from the bound channel, so no extra wiring is needed. The replace-in-place match uses the event `t` field (song time) of IMPLODED and PLAYER_LEFT. RemoteReferee and NetClientChannel must keep `t` on both events. PeriscopePanel exposes `is_left()`, `hull_word()` ("LEFT" / "WRECK" / "TRAINING" / "") and `meter_visible()`. `is_wreck()` is also true in the LEFT state, so target re-resolution treats a seat that left like a wreck.

## Verification

- tests/test_online_views.gd: 16/16 pass. It covers the countdown digits and the 0.95 s end, the progress line, priority over the section banner and LAST_STANDING, a late receipt, the waiting copy, the link chip (first slot, BALLAST then IMMUNE overflow, note-path keep-out), the killfeed replacement at +0.2 s, a new line at +1.5 s, PLAYER_LEFT alone, the unknown-seat guard (seat 3 in a 2-player match), the periscope LEFT state and has_char for every new string.
- Unchanged and green: test_versus_alerts (27), test_hud_gauges (61), test_killfeed (16), test_periscope_panel (22), test_versus_gameplay (12) and test_layout_keepout (8).
- tools/check_timing_gate.ps1: TIMING GATE OK.

## Deviations from Plan

**1. [Rule 2 - Copy] "1 SUB STILL DIVING" singular.** UI-SPEC lists only "{n} SUBS STILL DIVING". For n == 1 the banner uses the singular form, following the "FLIGHT 1 BEAT" precedent.

**2. [Rule 2 - Robustness] Extra LEFT-state guards.** After PLAYER_LEFT, METER and REWARD_EARNED for that seat are ignored, so the hidden meter and held reward cannot come back, and the threat block is cleared. The panel and killfeed also ignore PLAYER_LEFT for seats they do not render (T-04-25).

The link chip has no glyph. With the 16 px glyph, "NO HOST SIGNAL" would risk going over the 208 px chip cap. UI-SPEC 11.5 does not ask for a glyph.

## Self-Check: PASSED

- The created and modified files exist. Commits 839ff05 and be605b0 are on origin/main.
