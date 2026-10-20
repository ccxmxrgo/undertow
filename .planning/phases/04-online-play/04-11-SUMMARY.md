---
phase: 04-online-play
plan: 11
subsystem: online-ui
tags: [ui, main-menu, online-menu, connect-dialog, tailscale, focus, tests]
requires: [Settings net keys (04-03), NetAddress (04-03), SonarTextField + online glyphs (04-04), NetSession lobby half (04-06)]
provides:
  - "MainMenu.online_button (item 3, 'Play Online', icon online) + launch_online() + MainMenu.ONLINE_SCENE"
  - "Main menu at ITEM_H 48 / ITEM_PITCH 56 (last item ends at 944), Palette.STAGGER_MENU 0.030"
  - "OnlineMenu (src/ui/online/online_menu.gd) + scenes/online_menu.tscn"
  - "ConnectDialog (src/ui/online/connect_dialog.gd)"
affects: [04-15 lobby screen (LOBBY_SCENE target, Play Online as the return screen)]
tech-stack:
  added: []
  patterns: [match_setup_screen structure (consts, rects, navigate/session injection, gui_input row handling, debug_state seams), dialog that owns the join so synchronous connect_error is never missed]
key-files:
  created:
    - src/ui/online/online_menu.gd
    - src/ui/online/connect_dialog.gd
    - scenes/online_menu.tscn
    - tests/test_online_menu.gd
  modified:
    - src/ui/main_menu.gd
    - src/ui/palette.gd
    - tests/test_menu_flow.gd
    - tests/test_gamepad_menus.gd
decisions:
  - "ConnectDialog owns the join. start() connects connect_stage / connect_error first and then calls session.join(), because join() can emit connect_error('resolve'|'lost') before it returns"
  - "Unknown connect_error codes (bad_name, anything new) show the CONNECTION LOST copy. UI-SPEC 15 has no bad_name copy"
  - "Address and Paste accept 'host:port' and '[v6]:port', the string the lobby's Copy Address produces, and split it into the Address and Port fields. A bare address keeps the Port field"
  - "Return messages: lost is shown as an error (red plus glyph), kicked and closed as info (TEXT_MID). Focus goes to Join Match, or to Address when no address is saved"
  - "A return message takes precedence over the first-visit name prompt"
  - "The focus marker follows the focused field well rather than the row. The row backdrop switches to the button 'focus' style while its field has focus"
  - "ConnectDialog adds no FocusMarker of its own. It lives inside OnlineMenu, whose marker already follows its buttons"
metrics:
  duration: "~50 min"
  completed: 2026-10-20
  tasks: 2
  files: 8
requirements: [NET-01, NET-07]
---

# Phase 4 Plan 11: Play Online entry, screen and connect dialog Summary

This plan adds a tenth main menu item, "Play Online", and re-spaces the menu to 48/56 with a 30 ms stagger. It also adds the Play Online screen: name, port, Host Match, address with Paste and Join Match, and a right panel that lists this PC's addresses Tailscale first, the HOW TO CONNECT steps and the firewall line. The connect dialog walks CONNECTING, CHECKING VERSION and SYNCING CLOCKS, and shows the UI-SPEC error states with Try Again and Back.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | 1b8a45f | feat(04-11): Play Online as the tenth main menu item, 48/56 re-spacing, 30 ms stagger |
| 2 | 62f0465 | feat(04-11): Play Online screen and connect dialog |

## What was built

**Main menu (UI-SPEC 7.1)**
- `online_button` is item 3: "Play Online", icon `online`, default variant.
- Its description is "Host or join friends over Tailscale or LAN."
- `launch_online()` clears the run flags and `MatchSetup.pending`, then calls `_go(ONLINE_SCENE)`.
- ITEM_H is 48 and ITEM_PITCH is 56, so the tops run 392..896 and the last item ends at 944.
- The key hint box is 120 x 48. The focus marker bar follows the "height - 16" rule, giving 32 px.
- `Palette.STAGGER_MENU` is 0.030.

**OnlineMenu (`class_name OnlineMenu`)**
- All rects are consts in design pixels, taken from UI-SPEC 8 and 8.1.
- It has three SonarTextFields (name, port, address) and three buttons: Host Match (primary, `host` icon, ENTER/A hint), Paste (`copy`) and Join Match (`online`; disabled while the address is empty).
- Focus follows 8.2 and wraps: Name, Port, Host Match, Address, then the Paste | Join row. Left and Right move along the row, and a disabled Join is skipped. Keys are handled in each control's `gui_input` signal and ignored while a field is editing.
- First visit: the Name field starts out editing and the status line shows the prompt. Committing cleans the name, sets `player_name_set`, saves and emits `settings_changed`.
- Later visits: focus starts on Join Match when a saved address exists, otherwise on Host Match.
- Host Match calls `session.host(port)`.
  - OK: saves the port and navigates to `LOBBY_SCENE`.
  - `ERR_CANT_CREATE` or `ERR_ALREADY_IN_USE`: shows "Could not open port {port}...".
  - Any other error: shows "Could not start hosting (error {code})...".
  - If the session is not offline, it calls `leave()` first.
- Paste reads the injectable `clipboard_fn`, filters to the address charset and cuts to 64 characters. An empty result shows "Clipboard has no address to paste."
- Join Match saves `net_last_address` (through `Settings.clean_address`) and `net_last_port`, then opens ConnectDialog. When the dialog emits `joined`, the screen navigates to `LOBBY_SCENE`.
- Esc or B navigates to the main menu only when no field is editing and no dialog is open.
- The address list comes from `NetAddress.display_list(addrs_fn.call())`.
  - Tailscale rows: ABYSS_600 fill at 92%, a 4 px SONAR bar, a SONAR_PALE address and an `info` TAILSCALE chip.
  - LAN rows: TEXT_MID address and a `muted` LAN chip.
  - The line under the list has three states.
  - The list refreshes on open and every 5 s through `tick()`.
- The four steps read the port from the Port field. "VERSION {v}" is right-aligned to x 1856.
- Injectables: `navigate`, `session`, `addrs_fn`, `clipboard_fn`.
- Test seams: `debug_state()` returns {focus, status, status_role, rows, join_enabled, addresses, address_line, row_hint, hint, steps, version, dialog}. Also `focus_row_for_test()` and `press_key_for_test()`.

**ConnectDialog (`class_name ConnectDialog`)**
- It uses ConfirmDialog geometry (its PANEL_RECT is asserted equal to ConfirmDialog's).
- Stage titles and bodies come from UI-SPEC 15. Changing stage cross-fades over DUR_BASE, or swaps instantly under Reduce motion.
- The ping ring is centred at (1272, 428) and grows from r 8 to r 28 while fading from alpha 1 to 0 every second. Under Reduce motion it is static at r 20, alpha 0.6.
- The elapsed counter reads "{n} S".
- Cancel (also Esc or B) calls `session.leave()` and emits `closed`.
- Error state: danger panel, red brackets and divider, ring hidden, and the title and body for the code. `{host_version}` and `{my_version}` are filled in for the version error. Try Again is primary and focused and re-joins; Back is the Esc action.
- IPv6 addresses are shown in brackets.
- The effect contract is in place: `register_fx`, `apply_effect_settings()`, and `effect_counts()` returning {ping_ring, stage_fade}.
- `debug_state()` returns {mode, stage, title, body, elapsed, error_code, buttons, focus, ring_visible}.

## Verification

- test_menu_flow: 44/44
- test_gamepad_menus: 17/17
- test_effect_settings: 14/14
- test_overlay_layout: 32/32
- test_online_menu: 26/26, 0 orphans. It covers:
  - the region rects
  - focus order, the Paste/Join row and the disabled-Join skip
  - the first-visit prompt and the name save
  - the address list, its three states and the 5 s refresh
  - the port range revert with its status copy
  - the address charset
  - Esc while editing, both through the seam and as a real pushed key
  - paste, including host:port and the empty clipboard
  - host success, the double-press guard, and both host error texts
  - join saving Settings in a temp file and opening the dialog
  - the stages, including the {HOST} name
  - every error title, Try Again and its re-join count
  - the synchronous resolve error followed by Back
  - Cancel
  - IPv6 brackets
  - ping ring and Reduce motion
  - return messages
  - has_char for every constant string
  - no PRESET_FULL_RECT
- test_color_literals: 7/7. test_sonar_text_field: 20/20. test_review_fixes: 15/15. One run failed, but only while 04-10's net_session.gd was mid-edit and did not parse; it passes after 04-10's commit.
- `grep -c PRESET_FULL_RECT` returns 0 for both new sources. `grep -c "STAGGER_MENU := 0.030" src/ui/palette.gd` returns 1.
- `tools/check_timing_gate.ps1`: TIMING GATE OK.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Correctness] host:port addresses are split**
- **Found during:** Task 2
- **Issue:** The lobby (UI-SPEC 9) shows and copies the invite as "{address}:{port}". Pasting that into Address and pressing Join would pass "100.x.y.z:47474" as the host to resolve, which fails as ADDRESS NOT FOUND.
- **Fix:** `OnlineMenu.split_host_port(text, default_port)` handles "a.b.c.d:port" and "[v6]:port". A bare IPv6 address, a hostname with an invalid port, and an out-of-range port are left alone. Paste fills both fields, and Join applies the same split.
- **Files modified:** src/ui/online/online_menu.gd, tests/test_online_menu.gd
- **Commit:** 62f0465

**2. [Rule 1 - Bug] Orphans from the closed dialog**
- **Found during:** Task 2
- **Issue:** Calling `remove_child` and then `queue_free` left the dialog outside the tree until the end of the frame. gdUnit reported 22 orphans and the suite exited with 101.
- **Fix:** The dialog is hidden and freed with `queue_free` while still a child. Its `_unhandled_input` now ignores Esc once it is closed.
- **Commit:** 62f0465

### Notes
- The plan asked for the ConnectDialog to use ConfirmDialog geometry. It is a separate class with the same constants rather than a subclass, because ConfirmDialog builds a fixed destructive/safe pair in `setup()`.
- The LF/CRLF churn is normalised by `core.autocrlf`. Import noise (`*.import`, `default_bus_layout.tres`) was not committed.

## Notes for 04-15 (Lobby screen)
- Play Online is at `res://scenes/online_menu.tscn`. The lobby's "left_lobby(code)" and "Leave Lobby" should navigate there. OnlineMenu reads `session.take_return_message()` on open, so the session's return code shows up without any handoff. Focus starts on Join Match, which is enabled because `Settings.net_last_address` was saved on Join.
- OnlineMenu navigates to `OnlineMenu.LOBBY_SCENE` ("res://scenes/lobby.tscn"):
  - after a successful `host()`, where the session is already in LOBBY as host;
  - after the connect dialog sees `connect_stage("lobby")`, where the session is in LOBBY as a client.
- The host's invite string should use `NetAddress.host_port(NetAddress.invite_address(IP.get_local_addresses()), port)`. OnlineMenu.split_host_port accepts exactly that format on paste.
- OnlineMenu does not call `session.leave()` on Esc to the main menu. The session is OFFLINE there unless something upstream left it connected; Host Match calls `leave()` first if it is not offline.
- The menu's FocusMarker also follows controls inside child dialogs. Child overlays should not add a second marker.

## Known Stubs
None. LOBBY_SCENE points at a scene that plan 04-15 creates in a later wave. Until then the navigation seam is exercised in tests only, which is the documented contract.

## Threat Flags
None beyond the plan's threat model. T-04-34: the address charset is enforced by SonarTextField and the Paste filter, and the address is cleaned with `Settings.clean_address` on save. T-04-36: Cancel works at every stage, and the 8 s NO ANSWER comes from NetSession.

## Self-Check: PASSED
- Files present: src/ui/online/online_menu.gd, src/ui/online/connect_dialog.gd, scenes/online_menu.tscn, tests/test_online_menu.gd, src/ui/main_menu.gd, src/ui/palette.gd.
- Commits 1b8a45f and 62f0465 are on origin/main.
