# Phase 3: Offline Versus - Context

**Gathered:** 2026-10-15 (orchestrator; the user is asleep and asked for autonomous progress, "continue to polish the game and go to next phases"). No discuss session.
**Status:** Ready for UI spec / planning
**Sources:** `03-SPEC.md` (locked by the user 2026-10-08, 14 requirements) and `03-RESEARCH.md` "Recommended Decisions (orchestrator defaults)".

<domain>
## Phase Boundary

A complete, fun, fair versus match against bot rivals, fully offline: killstreak rewards (03-SPEC req 1-8), the five
multiplayer moments (req 9-13), slower hull repair (req 14), and the remaining TORP/PAY/MATCH requirements. No
networking (Phase 4). Rules live in a pure, frame-rate-independent object that Phase 4's host can reuse.

</domain>

<decisions>
## Implementation Decisions

### Locked (user)
- **03-SPEC.md requirements 1-14 are locked.** Where 03-SPEC quotes timing windows of ±35/±70 ms, use the real
  current windows from judge_config.gd (research: the spec text is stale).

### Orchestrator defaults (user may override any of these)
D-01..D-33 are adopted exactly as written in `03-RESEARCH.md` § "Recommended Decisions (orchestrator defaults)".
That section is canonical for the planner. In brief:
- D-01..D-03 targeting (H / pad Y cycles AUTO, rivals, ATTACKERS; AUTO = deepest rival, or second-deepest when you lead).
- D-04..D-08 flight, telegraph, shields, 1-bar immunity, capped ghost damage.
- D-09..D-17 payload details: Pressure Crack, Crossed Wires, Ghost Notes, Ink Cloud, Depth Charge, Sonar Jam, Return to Sender.
- D-18..D-21 bots: 1 human + 1-3 bots, Veteran/Regular/Rookie tiers.
- D-22..D-25 win rules, placement, wreck ghosts.
- D-26 panel layout; D-27 Solo Dive training payloads.
- D-28..D-33 cross-cutting architecture and HUD.

**D-29 (pin move) is deliberate and authorised by 03-SPEC requirement 14.** The perfect_regen default lives in
judge_config.gd (pinned fbcf994). Follow the 02.2-26 G1 procedure:
1. One commit that changes only that line.
2. One commit that updates tests/test_hull_score.gd.
3. One commit that moves `$judgeBase` in tools/check_timing_gate.ps1 to the hash of commit 1.

Then prove both directions: the gate prints OK, and a scratch edit makes it fail. conductor, clock_model, input_judge
and hull_score stay pinned at 72e21ce and are never edited (extend them in new classes instead).

### Open questions resolved by default
- Ballast Patch restores 25% hull.
- A reflected shot does not count as "landed" for the original shooter.
- A ghost hit does not reset the reward meter.
- Every player in a match uses the same difficulty; mixed difficulties are deferred to Phase 4.
- Medium players earning few rewards on Expert is accepted for now. The bot report records the numbers, and the
  ratio stays a tunable constant.

### Claude's Discretion
- Visual and audio treatment, within Palette and UiKit and the UI-SPEC.
- Bot names.
- Tuning constants (kept in a config resource).

</decisions>

<canonical_refs>
- .planning/phases/03-offline-versus/03-SPEC.md — locked requirements
- .planning/phases/03-offline-versus/03-RESEARCH.md — architecture, pin procedure, defaults, pitfalls, waves
- .planning/REQUIREMENTS.md — TORP-*, PAY-*, MATCH-*
- CLAUDE.md — timing gate, pins, Palette, UiKit.register_fx
</canonical_refs>

<deferred>
- Networking and lobbies (Phase 4).
- Rival highways on screen.
- Mixed difficulties in one match.
</deferred>
