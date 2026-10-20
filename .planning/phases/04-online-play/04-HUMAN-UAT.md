---
status: pending
phase: 04-online-play
source: [04-18-SUMMARY.md, 04-17-SUMMARY.md, 04-15-SUMMARY.md, 04-09-SUMMARY.md, 04-06-SUMMARY.md, 04-UI-SPEC.md "Notes for the checker"]
started: 2026-10-20T00:00:00Z
updated: 2026-10-20T22:00:11Z
---

# Phase 4 Human UAT

## Current Test

Everything automated is green (see 04-18-SUMMARY.md): unit and harness tests, real ENet on 127.0.0.1, and the 4-process localhost smoke (`tools/net_smoke.ps1`, NET SMOKE OK). What only a human can check is the **real internet**, which needs Tailscale. Tailscale is **not installed** on the dev PC, and Claude creates no accounts, so step one is yours: install Tailscale on your PC and on at least one friend's PC (each signs in with their own account), then invite the friend into your tailnet.

Test 13 (the final checkpoint of plan 04-18) covers tests 1-8 in one sitting with one friend. Tests 9-11 can be answered during or after it. Test 12 is carried over from Phase 3.

## Tests

| # | Test | How | Expected | Status |
|---|------|-----|----------|--------|
| 1 | Real-internet match over Tailscale on 2+ PCs (NET-01, NET-07) | First **install Tailscale** on the dev PC and a friend PC (each signs in with their own account; the host invites the friend into the tailnet, or uses Share on the host machine). Both unzip UNDERTOW v0.7.0. Host: Play Online > Host Match, read the TAILSCALE address. Friend: type it, keep port 47474, Join Match. Play a whole song. Repeat with 3-4 PCs if possible | The friend sees CONNECTING, CHECKING VERSION, SYNCING CLOCKS, then LOBBY. The match plays to the shared results. Record how Tailscale connected (direct or DERP relay: `tailscale status`) and the lobby PING | pending |
| 2 | Lobby ready and song-match display (NET-02) | In the lobby, pick a song that the friend does not have (for example a song you imported). Then pick one of their copies that differs, if you have one. Then a bundled song | Rows show NAME, PING, SONG, READY. The missing song shows MISSING on the friend's row and the host's start gate names them. A different copy shows CHANGED. A bundled song shows OK, and Start Match unlocks once everyone is ready | pending |
| 3 | Synced start by ear (NET-03) | Start Match. Count the DIVE IN 3 / 2 / 1 out loud on voice chat, and listen for the song start on both PCs. During the song press F3 (the zip is a debug build) and note SKEW on each PC | The countdown agrees on both PCs, and the music starts together by ear. Record F3 SKEW (the localhost smoke measured a 2.1-3.4 ms start spread; the clock-sync error bound is 10 ms worst case, see follow-up F-2) | pending |
| 4 | Torpedo telegraph and 2-beat flight feel (NET-04, CONTEXT open item) | Fire torpedoes at each other with the default 2 BEATS flight. Then switch the lobby to 1 BEAT LAN for one song and compare | The INCOMING warning comes at least 1 beat before impact, and the payload lands on the beat. Decide: does the 2-beat online flight feel fast enough, or too slow next to the 1-beat LAN flight? (04-09 measured that 1 beat fails the 1-beat warning at the D/L cap link, so 1 beat stays LAN-only) | pending |
| 5 | Landed-late visibility and landing prediction (D-10, deferred) | During test 4, watch for disruptor notes that pop in instead of scrolling in. Press F3 and note LANDED LATE MAX on the target PC | Record LANDED LATE MAX (localhost smoke: 0.0 ms). Decide whether landing prediction is needed (D-10 was "measure first"). See follow-up F-1 for the known pop-in case at the cap link | pending |
| 6 | Disconnect mid-song (NET-05) | Friend: Esc > Leave Match mid-song. Also try once by quitting the friend's game from the taskbar (or pulling the friend's network cable) | The host and other friends see LEFT on that sub's panel and a "{name} left the match" killfeed line. The match continues for the rest. The results list the leaver as LEFT AT {m:ss} | pending |
| 7 | Host leaves (NET-06) | Rematch. The host quits mid-song (Esc > Leave Match). Then rematch again and **pull the host's network cable** (or turn off its Wi-Fi) mid-song | Quit: friends see HOST LEFT with the last known standings. Cable: friends see NO HOST SIGNAL after about 1 s, then CONNECTION LOST after 4 s. The 4 s host-loss watchdog has only been unit-tested so far (the smoke's drop scenario covers a client loss through the ENet peer timeout), so this is its first real check | pending |
| 8 | Windows Firewall prompt on first host (A4, Pitfall 9) | On a PC that has never hosted UNDERTOW.exe from this folder, pick Host Match | Windows asks once; Allow on Private networks lets friends join over Tailscale. Record whether it asked, and whether Tailscale needed Public as well. If you clicked Cancel, check that friends get NO ANSWER and that the ONLINE_SETUP.md fix works. (The localhost smoke never prompted, as expected for 127.0.0.1) | pending |
| 9 | UI-SPEC open questions 1-4 | (1) Esc in a match: is the Leave overlay's position noticed, and is it OK that Space does not fire while it is open? (2) Name entry with a gamepad: is D-pad character cycling usable? (3) Over Tailscale (especially a DERP relay), does the 1 s NO HOST SIGNAL chip flicker too often? (4) Does the DIVE IN countdown in the banner slot feel like a proper start, or do you miss big cinematic numerals? | An answer (keep / change) for each of the 4 questions | pending |
| 10 | Overclock / Ballast arriving late on clients (Pitfall 11) | Use Overclock and Ballast Patch as a client during tests 4-7 | The buff takes effect without a visible hiccup, and the HUD on the client agrees with the host. Note any delay you can feel | pending |
| 11 | Friend PC test of zip v0.7.0 and ONLINE_SETUP.md clarity | Send `build/dist/UNDERTOW-playtest-v0.7.0.zip` (sha256 edd41e3a5114902d9bc59138ad669aed1d6d7f203cdff6e9a7ba5cb3b99db7cd, 63.06 MB). The friend follows ONLINE_SETUP.md on their own and fills in TESTER-CHECKLIST.txt section 4e ONLINE | The friend gets connected using only the guide. Note every step that was unclear and every error title they saw | pending |
| 12 | D-UAT-01 (tests/test_bot_frequency.gd), carried over from Phase 3 | See 03-HUMAN-UAT.md "D-UAT-01". Unchanged in Phase 4: the test still fails on the one bot that earns 5 rewards (HRT seat 3) and was not loosened | Decide as described in 03-HUMAN-UAT.md | pending |
| 13 | Final checkpoint of plan 04-18: human verification of online play over the real internet (non-blocking) | 1. Install Tailscale on your PC and a friend's PC (each signs in with their own account). Invite the friend into your tailnet. 2. Both run UNDERTOW v0.7.0 (the zip). On your PC: Play Online > Host Match and note the TAILSCALE address. Friend: Play Online > type that address > Join Match. 3. In the lobby, check that both rows show PING, SONG OK and READY. Pick a song the friend lacks once and check that MISSING shows. 4. Start Match. Check the DIVE IN 3/2/1 countdown and that the music starts together (call it out on voice chat). 5. Fire torpedoes at each other. Check that the warning comes at least 1 beat before impact and the payload lands on the beat. Press F3 (debug build) and note SKEW and LANDED LATE MAX. 6. Friend: Esc > Leave Match mid-song. The host should see LEFT and the match continues. Rematch, then the host quits mid-song. The friend should see HOST LEFT. 7. Answer the questions in this file | Reply "approved" or list the issues. Then update this file and run /gsd:verify-work 4, or plan gap closure for the issues. This checkpoint was recorded as pending and did not block the phase (the user was away) | pending |
| 14 | Rebuilt v0.7.0 zip (446 MB, with the Autocharter pack) on a friend PC (added by the verifier, 2026-10-20) | Send the rebuilt `build/dist/UNDERTOW-playtest-v0.7.0.zip` (467,661,357 bytes, sha256 dde997fc5e2ef203fb44329511add8c6775b04fc5cef287b767eef9570ba1ca4). The friend unzips it, runs UNDERTOW.exe, and opens the Autocharter once. Use this zip for tests 1-11 instead of the 63 MB one named in test 11 | The game starts without Godot installed, the Autocharter pack installs from the bundled "Autocharter Pack" folder without downloading (if it does download, it comes from github.com/ccxmxrgo/Undertow-autocharter releases, which the verifier confirmed is live with matching hashes), and online play works as in tests 1-7 | pending |

## Friend zip

- File: `build/dist/UNDERTOW-playtest-v0.7.0.zip` (built locally by `tools/dist.ps1`, not uploaded anywhere)
- Size: 66,120,297 bytes (63.06 MB); UNDERTOW.exe inside is 129.77 MB
- sha256: edd41e3a5114902d9bc59138ad669aed1d6d7f203cdff6e9a7ba5cb3b99db7cd
- Contents: UNDERTOW.exe (pck embedded, debug export so F3 works), README.txt, TESTER-CHECKLIST.txt, ONLINE_SETUP.md

## Follow-ups found by automation (decide fix or accept)

- **F-1 Overlay margin cap at the D cap (04-09).** `HostInputQueue.MARGIN_CAP_S` = 0.3 s is too small at the D-05 cap (D 0.2 s) with L_p90 0.15 s: the target receives LANDED at about arrive_t + D + L + F = +0.367 s. When payload_span's beat ceiling gives no extra room, overlay notes start their highway travel about 50 ms before LANDED arrives, so they pop in about 50 ms late. This only happens when D + L_p90 + 33 ms > 0.3 s (bad links); inside the D-09 budget (for example D 0.143, L 0.07) the minimum slack was +0.058 s. Fix options: raise the cap (for example to D_max + L_p90 + one frame), or accept. Test 5 tells whether it is visible on real links.
- **F-2 Clock-sync bound loosened in tests (04-06).** Under MemTransport's uniform +-20 ms per-leg jitter, the D-06 estimator (median of the 5 lowest-RTT samples of a 16-ping burst) measured -6.5 to +5 ms over 12 seeds. The tests assert a 10 ms hard bound (jitter/2) and a 2 ms median; a +-2 ms link holds 2 ms on every seed. ClockSync was not changed. Test 3 (F3 SKEW over Tailscale) tells whether real jitter stays inside this.
- **F-3 "Host is choosing a song." is not sent while the host is in Song Select (04-15).** Clients see that lobby log line only at join time. NetSession has no public call for it. If wanted, a later plan adds a `host_choosing()` notice. Cosmetic.
- **F-4 Host-loss watchdog only unit-tested (04-17).** The 4 s CONNECTION LOST path has no real-process test; the smoke's drop scenario kills a client. Covered by test 7 (pull the host's cable).
- **F-5 No lossy-link run (04-17).** The smoke runs on a clean localhost link. Lossy links are covered only in-process (04-09: 2% loss, jitter +-30 ms, host log identical). An optional manual run with a loss tool such as clumsy (2-5% loss, 50-150 ms) on one client would close this; it is not required for the phase.

## Decisions needed

- Test 4: keep the 2-beat online flight, or change it.
- Test 5 and F-1: is landing prediction (D-10) or a larger margin cap needed?
- Test 9: the 4 UI-SPEC open questions.
- Test 12: D-UAT-01 (from Phase 3).

## Verifier addendum (2026-10-20, 04-VERIFICATION.md)

- **Zip rebuilt.** The friend zip was rebuilt after the 04-REVIEW fixes and now carries the Autocharter pack: 467,661,357 bytes, sha256 `dde997fc5e2ef203fb44329511add8c6775b04fc5cef287b767eef9570ba1ca4` (UNDERTOW.exe sha256 `8255783720904515582721edaa562bfb36a5c05372c249f4858aa1627db4d1e7`). The 63 MB sha in test 11 and in "Friend zip" above is the pre-fix build; use the new one (test 14).
- **Pack URL checked.** The shipped exe's PackSpec.BASE_URL is `https://github.com/ccxmxrgo/Undertow-autocharter/releases/download/autocharter-pack-v1/`; all 4 parts and SHA256SUMS.txt are live and match the pinned sizes and hashes.
- **Follow-ups closed by the review fixes (04-REVIEW-FIX.md):** F-1 by WR-01 (MARGIN_CAP_S is now 0.5 s; the harness case at RTT p90 300 ms has +0.279 s slack), F-3 by WR-07 (`NetSession.host_choosing()`), F-5 by IN-03 (`net_smoke.ps1 -Lossy`). Tests 5 and 9(3) still say whether real links look right. F-2 and F-4 stay open and are covered by tests 3 and 7.
- **Verifier gate runs:** TIMING GATE OK; full suite 2154 cases with 1 failure (test_bot_frequency, D-UAT-01, test 12); NET SMOKE OK (full + drop, start spread 1.5 ms, landed_late_max 0.0 ms, digests identical).
