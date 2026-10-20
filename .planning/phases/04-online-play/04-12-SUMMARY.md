---
phase: 04-online-play
plan: 12
subsystem: ui/versus
tags: [online, results, lobby, NET-04, NET-05, D-19]
requires: ["04-02", "04-04"]
provides:
  - "VersusResultsScreen online variant (data.online)"
  - "signals back_to_lobby_pressed, leave_lobby_pressed, close_lobby_pressed"
  - "set_lobby_closed(), online_state(), dialog()"
affects: ["04-14 (gameplay wires the signals and fills online keys)"]
tech-stack:
  added: []
  patterns: ["opt-in online branch inside setup(data); offline path untouched", "screen-owned ConfirmDialog with Stay focus"]
key-files:
  created: [tests/test_online_results.gd]
  modified: [src/ui/versus/versus_results_screen.gd]
decisions:
  - "Online rows: the local seat's row name is replaced by YOU on each PC (host sends real names)"
  - "Client lobby-closed hint reads ENTER BACK TO MENU / A BACK TO MENU (spec gives no hint for that state; copy reused from HOST LEFT)"
  - "Waiting line upper-cases host_name like the rows; falls back to the host row's name, then 'the host'"
  - "Malformed network values read with typed defaults: left must be a real bool, left_t / host_seat must be numeric"
metrics:
  duration: "~25 min"
  completed: 2026-10-20
  tasks: 1
  files: 2
---

# Phase 4 Plan 12: Online Results Variant Summary

VersusResultsScreen now has an online variant, selected by `data.online`. It shows player names with a YOU row, a host glyph, "LEFT AT {m:ss}" with a link_broken glyph, and an ONLINE chip. The host gets Back to Lobby and Back to Menu, the second behind a CLOSE LOBBY confirm. A client gets Leave Lobby behind a LEAVE LOBBY confirm, plus a waiting line, and `set_lobby_closed()` switches that to the lobby-closed state. Offline output is unchanged: test_versus_results is green without edits.

## setup(data): new optional keys

| Key | Type | Default | Meaning |
|-----|------|---------|---------|
| `online` | bool | false | Turns on the online variant. Only a real `true` counts |
| `is_host` | bool | false | Picks the host buttons or the client buttons |
| `host_seat` | int | 0 | That row gets a 20 px `host` glyph after its name |
| `host_name` | String | "" | Used in "Waiting for {HOST} to return to the lobby." (upper-cased). If empty, falls back to the host row's name, then "the host" |
| row `left` | bool | false | Row status becomes "LEFT AT {m:ss}" in TEXT_LO, with a 16 px `link_broken` glyph before it. This takes precedence over LAST HULL STANDING and IMPLODED |
| row `left_t` | float | 0 | The song time shown as m:ss |

Online, the row whose seat is `local_seat` always reads "YOU", so the host can send real names for every seat. `status_of()` handles `left` for both variants, and offline rows never carry it.

## Signals and API (for 04-14)

- `back_to_lobby_pressed`: the host pressed Back to Lobby, or pressed Esc/B.
- `close_lobby_pressed`: the host pressed Back to Menu and confirmed CLOSE LOBBY.
- `leave_lobby_pressed`: the client pressed Leave Lobby (or Esc) and confirmed LEAVE LOBBY.
- `menu_pressed`: still emitted offline. Online, a client emits it from Back to Menu after `set_lobby_closed()` (Accept or Esc).
- `set_lobby_closed()`: client only; does nothing for the host or offline. It closes any open confirm and sets the waiting line to "The host closed the lobby.". The button becomes "Back to Menu" and the hint becomes "ENTER BACK TO MENU".
- `online_state() -> {online, is_host, lobby_closed, buttons, waiting_line, chips, hint}`.
- `dialog() -> ConfirmDialog` returns the open confirm, or null.
- Fields: `back_to_lobby_button` and `menu_button` for the host; `leave_button` for the client. `rematch_button` and `change_match_button` are null online. `focus_buttons()` returns only the online buttons.
- Geometry: buttons at x 96 / 520, y 752, 400 x 64. The waiting line is Label 20 TEXT_MID at x 520, baseline 792. The ONLINE info chip sits 8 px left of NOT RECORDED.

## Tasks

| Task | Commit | Notes |
|------|--------|-------|
| RED: test_online_results.gd (14 cases) | b1cf6cc | Failed at parse (missing members), as expected |
| GREEN: online variant | 0b88663 | 14/14 pass |

## Verification

- test_online_results: 14/14 passed, 0 orphans.
- test_versus_results: 14/14 passed (offline unchanged).
- test_color_literals 7/7, test_effect_settings 13/13, test_versus_gameplay 12/12, test_fonts 4/4.
- TIMING GATE OK.

## Deviations from Plan

**1. [Rule 1 - Bug] Closed confirm dialogs became orphans.** At first `_close_dialog` removed the dialog from the tree before calling `queue_free`, and gdUnit reported 7 orphans per dialog. The dialog now stays in the tree, hidden and with `PROCESS_MODE_DISABLED`, until the free runs. This is fixed in 0b88663.

There are no other deviations. The lobby-closed hint copy is a small default because the spec does not give one; it is listed under decisions.

## Threat model

- T-04-37: every new key is read through typed helpers (`_flag`, `_int_of`, `_float_of`). A test sends a string `left`, a string `left_t`, empty rows and a minimal `{online:true}`.
- T-04-38: both confirms open with focus on Stay, and Esc/B inside the dialog means Stay. While a dialog is open, the screen ignores Esc.

## Self-Check: PASSED

- src/ui/versus/versus_results_screen.gd: FOUND
- tests/test_online_results.gd: FOUND
- b1cf6cc, 0b88663: FOUND
