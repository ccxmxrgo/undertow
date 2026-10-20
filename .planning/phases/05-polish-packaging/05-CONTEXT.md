# Phase 5: Polish & Packaging - Context

**Gathered:** 2026-10-20 (orchestrator). The user asked for autonomous progress, so there was no discuss session.
**Status:** Ready for planning
**Source:** `05-RESEARCH.md` audit and "Recommended Decisions (orchestrator defaults)".

<domain>
## Phase Boundary

The research audit decides what this phase covers. It closes only the gaps:
- **AV-03:** downbeat pings, hull creaks, and an underwater low-pass muffle that grows as the hull drops.
- **AV-04:** the missing torpedo impact, launch and elimination feedback.
- **AV-05:** low effects measured on a weak GPU, a slow-frame hint, and the versus p95.
- **DIST-01:** exe icon, boot splash and version info, plus a v0.8.0 local friend zip.

AV-01 and AV-02 are already done (D-01) and are closed without new work.

</domain>

<decisions>
## Implementation Decisions

### Orchestrator defaults (user may override)
D-01..D-13 are adopted as written in `05-RESEARCH.md` § "Recommended Decisions". That section is canonical for the planner.

| Decision | Summary |
|---|---|
| D-01 | AV-01 and AV-02 are closed as done; keep the cyan palette. |
| D-02 | A bar-start ping at about −20 dB with a Settings toggle. |
| D-03 | A runtime low-pass filter on the Music bus, only while gameplay runs. |
| D-04 | Procedural creaks, plus a "Hull sounds" toggle. |
| D-05 | Torpedo feedback driven by events, with no protocol change. |
| D-06 | A slow-frame detector, plus a hint on the Results screen. |
| D-07 | Re-baseline on the current GPU, and measure on the integrated GPU (never report an unmeasured result as a pass). |
| D-08 | Fix the versus HUD redraw if the versus p95 is still over 4.35 ms. |
| D-09 | Add an icon, a dark splash and version info. No code signing; build locally only. |
| D-10 | v0.8.0. |
| D-11 | Timing gate in every plan; the pinned files and `default_bus_layout.tres` are untouched. |
| D-12 | All new sounds are procedural. |
| D-13 | Reuse the 02.2 and Phase 3 UI specs. |

### Hard rules
- **Pinned files:** conductor, clock_model, input_judge and hull_score stay pinned at 72e21ce, and judge_config at 2c2e54c. `tools/check_timing_gate.ps1` must print TIMING GATE OK at the end of every plan.
- **Bus layout:** `default_bus_layout.tres` is never committed. Bus effects are added and removed at runtime.
- **Friend zip:** it must keep bundling everything (user decision 2026-10-20):
  - the Autocharter pack in "Autocharter Pack", verified against PackSpec;
  - the download URL `github.com/ccxmxrgo/Undertow-autocharter`.

  The friends bundle also adds the user's "Extra Songs" from `build/dist/friends/UNDERTOW-v0.7.0/Extra Songs`. The bundle goes on the user's Desktop.
- **Behaviour:** offline and online behaviour is otherwise unchanged. The Phase 3 and 4 determinism suites and `tools/net_smoke.ps1` stay green.
- **Known red:** `test_bot_frequency` (D-UAT-01) stays red and its test is not loosened.

### Claude's Discretion
- Sound design parameters.
- Shake and flash amounts, within the effect contract (Low effects and Reduce motion).
- Icon art (original, procedural or drawn in code).

</decisions>

<canonical_refs>
- .planning/phases/05-polish-packaging/05-RESEARCH.md
- .planning/phases/02.2-visual-design-overhaul/02.2-UI-SPEC.md, .planning/phases/03-offline-versus/03-UI-SPEC.md
- CLAUDE.md
</canonical_refs>

<deferred>
- Code signing.
- Store or Steam distribution.
- A full-screen CRT post-process.
</deferred>
