# Phase 4: Online Play - Context

**Gathered:** 2026-10-20 (orchestrator). The user asked for autonomous progress ("go to next phases"), so there was no discuss session.
**Status:** Ready for UI spec / planning
**Source:** `04-RESEARCH.md` § "Recommended Decisions (orchestrator defaults)".

<domain>
## Phase Boundary

2-4 friends on separate PCs play the same song at once, in a versus match where torpedoes reach each other mid-song.

- **Authority:** the host runs the only MatchSim, the same rules object as offline.
- **Clients:** they keep hit judgment, hull and the audio clock local. They send time-stamped inputs and apply the events the host sends back.
- **Connectivity:** a documented, no-cost path (Tailscale, ZeroTier, LAN or port forwarding). There are no servers, and Claude creates no accounts.

</domain>

<decisions>
## Implementation Decisions

### Orchestrator defaults (the user may override any of these)
D-01..D-24 are adopted exactly as written in `04-RESEARCH.md` § "Recommended Decisions". That section is canonical for the planner.

| Decisions | Topic | Summary |
|---|---|---|
| D-01, D-02 | Transport | ENet, behind a NetTransport seam. An in-memory transport with simulated latency, jitter and loss is used for tests. No `@rpc`. |
| D-03 to D-05 | Authority | Host-authoritative: Referee base, HostInputQueue with a fixed release delay D, RemoteReferee. |
| D-06, D-07 | Start | NTP-style clock offset, then a host-scheduled start through LOAD/LOADED/START. The intro is off online. |
| D-08 | Flight | 2-beat torpedo flight online, with a 1-beat LAN option in the lobby. |
| D-09 | Overlay notes | Ghost and Depth Charge notes get a network margin so they never pop in mid-highway. |
| D-10 | Prediction | No landing prediction in v1. Measure how late landings arrive first. |
| D-11 | Song match | Song key = song hash plus the time-signature/solo signature. Never send a file path. |
| D-12, D-13 | Lobby | NAME, PING, SONG and READY rows. New events FIRE_REFUSED and DUEL_LIVE. |
| D-14, D-15 | Connectivity | Tailscale first, with ZeroTier, LAN and port forwarding documented as fallbacks. UDP port 47474. |
| D-16 to D-19 | Leaving and ending | A player who drops out is eliminated and the match continues. If the host leaves, everyone sees a message and the match ends cleanly. Online has no pause or restart. RESULTS return everyone to the lobby. |
| D-20 to D-23 | Plumbing | `player_name` setting, version handshake, star topology, packet caps. |
| D-24 | Testing | Tests run in layers, from pure unit tests up to a 4-process smoke test and a human test over Tailscale. |

### Hard rules
- The timing core stays untouched:
  - conductor, clock_model, input_judge and hull_score stay pinned at 72e21ce.
  - judge_config stays pinned at 2c2e54c.
  - `tools/check_timing_gate.ps1` must print TIMING GATE OK at the end of every plan.
- Offline versus (Phase 3) must behave identically. The existing determinism and versus tests stay green.
- Every peer message is validated at one choke point, with size and count caps (ASVS L1). Peers never send code or file paths.
- Publishing anything, or creating accounts on any service, is a human action. Claude only writes the docs.

### Open items for UAT, not blockers
- Does a 2-beat flight feel fast enough?
- Is landing prediction needed?
- Tailscale is not installed on the dev PC. The user installs it for the real-internet test.

### Claude's Discretion
- Lobby layout, within the UI-SPEC.
- Network debug rows.
- Tuning of the network constants.

</decisions>

<canonical_refs>
- .planning/phases/04-online-play/04-RESEARCH.md — architecture, decisions, validation
- .planning/phases/03-offline-versus/ — MatchSim, events, VersusController, determinism
- .planning/REQUIREMENTS.md NET-01..07
- CLAUDE.md
</canonical_refs>

<deferred>
- Rollback or landing prediction (revisit after UAT).
- Steam relay or hosted servers.
- Spectators and joining mid-match.
</deferred>
