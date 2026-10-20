---
phase: 04-online-play
plan: 09
subsystem: versus-net
tags: [harness, integration, determinism, latency, disconnect, telegraph]
requires: [HostInputQueue, RemoteReferee, NetHostChannel, NetClientChannel, MemTransport, NetCodec, MatchHarness._AutoActor]
provides: [NetMatchHarness]
affects: [04-13, 04-16, 04-17]
tech-stack:
  added: []
  patterns: [virtual-time whole online match, codec on every hop, global actor order shared with MatchHarness]
key-files:
  created:
    - src/versus/net_match_harness.gd
    - tests/test_net_match_harness.gd
  modified: []
decisions:
  - "finish() first lets in-flight inputs land, then pumps exactly to end_t + D and calls sim.finish(end_t), so MATCH_END is the last event and host-log times never decrease (the plan's pump(end_t + D + 1.0) would put beat events after the end_t MATCH_END)"
  - "Case 5 (D-09 no pop-in) asserts on a link inside the D-09 budget (D 0.143 from the D-05 formula, L 0.07 +- 0.02, link-derived margin, 4 seeds), not on the D 0.2 / L 0.15 cap link: there the 0.3 s margin cap cannot cover D + L + F and pop-in is measured (see Findings)"
  - "A dropped client's machine stops playing and flushing at drop_at_s; the host drops the seat when MemTransport peer_left fires (link latency later)"
  - "The match seed also seeds the MemTransport hub (jitter/loss RNG); all game traffic is reliable, so the 2% loss profile only affects unreliable packets (none in the match)"
metrics:
  duration: "~35 min"
  completed: 2026-10-20
  tasks: 2
  files: 2
---

# Phase 4 Plan 09: Headless online match harness Summary

NetMatchHarness runs a whole online match in virtual song time. The host side is MatchSim, HostInputQueue, NetHostChannel and SubRig(0). The clients (1-3) are each SubRig(k) on a RemoteReferee and a NetClientChannel. They share a MemTransport hub with latency, jitter, loss and drops. Every message goes through NetCodec.encode/decode, every seat is a MatchHarness._AutoActor autoplay human, and scripted fires run every 8 beats. Seven integration tests prove NET-04 rule exactness, exact fan-out, the late clamp, the TORP-04 online telegraph, D-09 no pop-in inside its budget, NET-05 disconnect and DUEL_LIVE.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | ca26bda | feat(04-09): NetMatchHarness headless online match over MemTransport |
| 2 | e82b728 | test(04-09): NET-04/NET-05 online match integration tests |

## Tests

test_net_match_harness.gd is 7/7 in about 11 s.

1. **Determinism across links.** 3 clients, D 0.10, 2-beat flight, margin_rtt_p90_s pinned at 0.1. Each match seed (7 and 2) runs 4 link profiles: latency 0, 0.05, 0.04 ± 0.03 jitter, and 0.04 ± 0.03 with 2% loss. The host log is `==` identical across all four, late_inputs is 0 in every run, and each log has 650-770 events with launches from every seat.
   - Negative control (probe, not committed): latency 0.15 > D gives 1074 late inputs and a different host log, so the comparison really can fail.
2. **Fan-out.** Every client log `==` the host log in every profile. Under the loss profile each client has rejected_events 0, an empty out-of-order buffer, and received count equal to the broadcast count.
3. **Late inputs.** Latency 0.15 with D 0.06 gives late_inputs = 1074 (> 0). Event t in the host log never decreases, and MATCH_END is last.
4. **Telegraph.** Flight 2, D 0.2, L 0.15 on hand_chart (100 → 140 BPM): every row has receipt ≤ arrive_t − 1 beat. Flight 1 on the same link fails the bound on 6 of 6 rows.
5. **Overlay (D-09).** Link-derived margin, D 0.143, L 0.07 ± 0.02, seeds 1/2/3/7: 12 overlay rows, all with active_start − approach_local ≥ receipt_t. Minimum slack is 0.058 s.
6. **Disconnect.** Seat 2 dropped at 20 s with L 0.03. The log has IMPLODED{2} then PLAYER_LEFT{2, "disconnected"}, both at t = 19.925 (released_t when peer_left fired). MATCH_END has 4 standings rows. Clients 1 and 3 equal the host log, and client 2 holds a 206/581 prefix.
7. **DUEL_LIVE.** click_chart 120 BPM with a solo at [20, 29.5] and 2 clients. Every DUEL_LIVE lies strictly between DUEL_START and DUEL_RESULT, with at most one per beat. Mid-duel at 25 s, each client's RemoteReferee.duel_live(seat) equals the last received pct and duel_active() is 0. After the result both are cleared.

Guards: test_match_determinism 4/4, test_match_sim_determinism 2/2 and test_versus_controller_determinism 5/5. TIMING GATE OK.

## Measured margins (seeds 1, 2, 3, 7; 3 clients; fire every 8 beats; hand_chart)

| Link profile | D | Margin | Min telegraph (beats, 2-beat flight) | Overlay rows | Min overlay slack |
|---|---|---|---|---|---|
| latency 0 | 0.10 | pinned rtt 0.1 → 0.183 s | 1.750 | 12 | +0.107 s |
| 0.04 ± 0.03 | 0.10 | pinned rtt 0.1 → 0.183 s | 1.600 | 12 | +0.052 s |
| 0.07 ± 0.02 (DERP class) | 0.143 | derived rtt 0.18 → 0.266 s | 1.442 | 12 | +0.058 s |
| 0.15 (cap) | 0.20 | derived rtt 0.30 → 0.383, capped 0.300 s | 1.167 (case 4, seed 7: 1.169) | 12 | **−0.050 s** |

At the cap link, flight 1 has a minimum warning of 0.169 beats, and 6/6 rows fail the 1-beat bound. This confirms D-08.

## Findings

**D-09 margin cap gap (outside this plan's files; not fixed).** HostInputQueue.MARGIN_CAP_S = 0.3, but at the D-05 cap (D 0.2) with L 0.15 the target receives LANDED at arrive_t + D + L + F ≈ +0.367 s. When payload_span's beat ceiling gives no extra room, overlay notes start their highway travel 50 ms before LANDED arrives. All three seeds that had overlay rows on that link showed exactly −0.050 s (seed 7 escaped only by luck).

The guarantee holds whenever D + L_p90 + 33 ms ≤ 0.3 s, which covers every link in the RESEARCH budget table up to the DERP relay class.

Options for the owner of host_input_queue.gd / D-09:
- raise the cap to cover D_max + L + F (about 0.4 s), or
- cap D + L for overlay purposes in the lobby high-latency warning.

## Deviations from Plan

**1. [Rule 1 - Bug] finish() order.** The plan's `pump(end_t + d_s + 1.0)` followed by `sim.finish(end_t)` would emit beat events after end_t and then MATCH_END at end_t, so log times would go backwards. finish() now lets in-flight inputs land (hub advance by 1 s), pumps to exactly end_t + D, and then finishes at end_t.

**2. [Rule 1 - Test correctness] Case 5 link.** The plan named the case-4 link (D 0.2, L 0.15). There the D-09 guarantee fails by design of the 0.3 s cap (see Findings). A single-seed test on that link passed only by luck, so case 5 now asserts on a D-05-consistent DERP-class link over 4 seeds, and the cap result is recorded above.

**3. [Rule 2] Leak.** The inner actors hold the harness, so finish() clears `_actors` to break the cycle (the run went from about 925 leaked ObjectDB instances to none).

**4. Case 1 runs 2 match seeds** (the hub RNG follows the match seed) for wider coverage. Runtime is still about 5 s.

## Housekeeping

`tests/zz_0409_probe.gd` (+ .uid) is my untracked scratch probe. `rm` was blocked by the sandbox, so I emptied it to a trivial no-op test. It is safe to delete and is not committed.

## Known Stubs
None.

## Threat Flags
None. T-04-27 is mitigated by case 1 (identical host logs across link profiles, with the negative control) and T-04-28 by case 6 (the match runs to MATCH_END after a drop).

## Self-Check: PASSED
src/versus/net_match_harness.gd and tests/test_net_match_harness.gd exist. Commits ca26bda and e82b728 are on origin/main.
