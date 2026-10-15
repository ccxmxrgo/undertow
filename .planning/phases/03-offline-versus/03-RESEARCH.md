# Phase 3: Offline Versus - Research

**Researched:** 2026-10-15
**Domain:** Godot 4.7.2 GDScript gameplay systems: killstreak rewards, highway disruptors, bot rivals, match flow (offline, EventChannel seam for Phase 4)
**Confidence:** HIGH for codebase integration and the pin strategy (verified against the repo and a headless Godot check). MEDIUM for bot calibration (simulated in a model, not yet in-engine). Design defaults are proposals for the orchestrator (no discuss session was held).

<user_constraints>
## User Constraints (from 03-SPEC.md, locked 2026-10-08; no CONTEXT.md exists)

There is no `03-CONTEXT.md`. The user is asleep and asked for autonomous progress, so no discuss session was held. `03-SPEC.md` holds the locked decisions. The orchestrator defaults for everything else are in **Recommended Decisions** below.

### Locked Decisions (03-SPEC.md requirements 1-14, summarized; the spec text is authoritative)
1. **Scaled reward threshold:** meter +1 per Perfect; reward at `ceil(reward_threshold_ratio x chart_note_count)` with ratio `0.12`. Miss empties the meter. Good neither adds nor empties it (Overclock is the exception). A stray press does nothing. Using a reward does not empty it.
2. **One reward slot:** while a reward is held the meter stops at full. After use it refills from 0. A Miss while holding keeps the reward and resets the meter. Only a Solo Duel prize may wait in a 1-item queue.
3. **Shuffled bag:** a personal bag holds all 9 rewards once, in shuffled order, and reshuffles when empty. Seeded per match (Phase 4 reproducibility).
4. **Firing:** the HUD shows the held reward's name and icon. Fire sends a disruptor to the current target (TORP-03) or applies a buff to self. Launch and arrival snap to beats, with a telegraph of at least 1 beat. One active disruptor per player plus immunity. Disruptors are reflectable (PAY-06). Buffs cannot be targeted, reflected or absorbed.
5. **6 disruptors:** Crossed Wires (2 random lanes swap positions, receptors slide over 1 beat, input follows position, 4 bars), Ghost Notes (hollow fakes, hitting one costs hull, 4 bars), Ink Cloud (bottom 35% blacked out, 4 bars), Pressure Crack (scroll x1.5 eased over 1 beat, 4 bars), Sonar Jam (all notes neutral grey, no lane shape, 3 bars), Depth Charge (extra notes on the song's rhythm, capped by local density, 2 bars). All go through one payload interface. Autoplay finishes all-Perfect under each one (skipping ghosts).
6. **3 buffs:** Decoy Flare (absorbs the next incoming disruptor, including a reflected one; expires after 8 bars; no immunity spent), Ballast Patch (+25% max hull, capped, cannot revive), Overclock (4 bars: Good counts as Perfect for the meter and score; Misses still reset).
7. **Lane Flip (PAY-02) removed;** Crossed Wires replaces it. The pool has exactly 9 rewards.
8. **Frequency:** a "strong" bot earns 2-4 rewards per bundled song. If not, adjust `reward_threshold_ratio` and record the new value.
9. **Torpedo Collision:** `torpedo_travel_beats` = 1. The target is alerted at launch. Opposing disruptors in flight at the same time both explode, both rewards are used, one `collision` event is emitted. Buffs never collide. Decoy is not spent.
10. **Bounty:** the alive leader by depth holds it. Ties keep the holder. Landing a disruptor that takes effect on the holder refunds `bounty_refund_ratio` 0.25 x threshold to the shooter's meter, with overflow becoming an instant reward. No self-claim.
11. **Solo Duel:** solos with at least 16 notes (`solo_duel_min_notes`). Banner 1 bar ahead. Live Perfect % on panels. The best Perfect % at or above 85% (`solo_duel_min_accuracy`) wins the next bag item. Tie-break is the longest Perfect streak in the solo; a tie after that means no winner. The prize queues (max 1) if the slot is full. Wreck ghosts don't take part.
12. **Killfeed:** top-right, at most 4 lines, 4 s fade, lines for 7 event types, own lines highlighted. Reads only from the EventChannel.
13. **Medals:** up to 3 per player in table order: Untouchable, Uno Reverse, Bounty Hunter, Shredder, Head-On, Grudge, Dogpiled (rules in spec). Ties for "most" medals go to every tied player.
14. **Slower hull repair:** `perfect_regen` default 1.0 -> **0.25**. Miss 8 and start 100 are unchanged. Test: Miss -> 92, then Perfect -> 92.25. The existing 93 assertion becomes 92.25. 32 Perfects after a Miss -> 100.

Spec constraints: judgment stays local. Rewards are EventChannel game events (Loopback/Bot now, Net in Phase 4). All numbers are tunables in a config resource like `JudgeConfig`. Ghost and Sonar Jam must be readable with Low effects. Godot 4.7.2, GDScript, gdUnit4 (`tools/run_tests.ps1`). Collision, bounty and duel outcomes are decided from song-time-stamped events so the Phase 4 host can decide them once.

### Claude's Discretion (not pre-answered by the spec)
TORP-03, TORP-04, TORP-05, TORP-06, PAY-01 (beyond the spec's numbers), PAY-03, PAY-04, PAY-05, PAY-06, MATCH-01, MATCH-02, MATCH-03, MATCH-04, MATCH-06, plus the reward HUD, the bot skill model and the payload interface. Defaults are proposed in **Recommended Decisions**.

### Deferred Ideas (OUT OF SCOPE, from 03-SPEC Boundaries)
Comeback/deathstreak rewards. Position-dependent draw odds. Pre-match loadouts. Salvage phrases (star power). Finisher-tier rewards. Network sync of draws (Phase 4). Payback, Interceptor, Boarding Party, Sea Mine, Salvage Race, Thermal Vent, Mute/Wrong Station, Haunting/Ghost Fleet, Kill cam, Sonar Ping taunt. Wreck ghosts do not draw from the bag.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TORP-01 | Perfect streak fills an always-visible tube meter | `RewardMeter` (pure), spec reqs 1-2; HUD arc on the existing `TorpedoSocket` (UI-SPEC 4.14 reserved it) |
| TORP-02 | Fire a reward at a target, launch and arrival on beats | `BeatClock.beat_at`/`time_at_beat` give exact beat math; launch = next whole beat after the press, arrival = launch + `torpedo_travel_beats` (D-04) |
| TORP-03 | Cycle targets, default leader, Attackers toggle | `target_cycle` action already exists (H / pad Y). D-01..D-03 |
| TORP-04 | Telegraph at least 1 beat before landing | Alert at launch plus a 1-beat flight (spec req 9); warheads are marked at launch (D-05) |
| TORP-05 | One active payload per player, then immunity | `MatchSim` shield state: active, incoming or immune, with a 1-bar immunity (D-06, D-07) |
| TORP-06 | No mashing, no instant elimination | Per-payload hull-loss cap, spacing invariants, autoplay-under-payload tests (D-08) |
| PAY-01 | Pressure Crack | `Highway.scroll_mult` eased over 1 beat. Judgment is untouched because depth 0 is still the note time (D-09) |
| PAY-02 | (superseded by Crossed Wires, spec req 7) | `Highway.lane_pos` remap plus a physical-key-to-lane remap in `LaneInput` (D-10) |
| PAY-03 | Ghost Notes | `VersusJudge` overlay notes of kind GHOST, `NOTE_GHOST` hollow gem (UI-SPEC 4.15 reserved the type) (D-11, D-12) |
| PAY-04 | Ink Cloud | `InkCloudLayer` above `HighwayNotes`, receptors redrawn on top (D-13) |
| PAY-05 | Depth Charge | Seeded overlay notes on the 8th-note grid, spacing and density caps (D-14) |
| PAY-06 | Return to Sender | Warhead = first 4 base notes at or after arrival, all Perfect -> reflect (D-15..D-17) |
| MATCH-01 | Offline versus vs bots | `BotPlayer` = real `InputJudge` + `VersusHull` driven by a seeded Gaussian skill model (D-18..D-21) |
| MATCH-02 | Last intact hull wins, otherwise the deepest, with a tie-break | `MatchSim.standings()` (D-22, D-23) |
| MATCH-03 | Wreck ghosts with weak, capped debris | `PlayerState.mode = WRECK`, debris rules (D-24, D-25) |
| MATCH-04 | Periscope panels: hull, tube, incoming/active | `PeriscopePanel` x up to 3 in the left column (D-26) |
| MATCH-05 | Results: winner, depth, accuracy, landed/reflected (+ medals) | `VersusResultsScreen` + `MedalRules` (spec req 13) |
| MATCH-06 | Solo Dive with chosen training payloads | Practice Dive + `TrainingDrone` on `LoopbackChannel` (D-27) |
</phase_requirements>

## Summary

The codebase is ready for Phase 3 and needs **no edits to the four timing-core files pinned at 72e21ce**. The reason is a GDScript property I verified headlessly on the installed Godot 4.7.2. A subclass in a new file can override `InputJudge.press/tick/release` and `HullScore.on_judged` and call `super.<method>()`. The `judged.connect(on_judged)` that `HullScore.connect_judge` makes inside the pinned file then dispatches to the subclass override, and the subclass can call the parent's `_damage`, `_set_hull` and `_add_score`. `LaneInput.judge` and `Autoplay` are typed `InputJudge`, so a `VersusJudge extends InputJudge` drops in unchanged. Every payload, buff and bot then lives in new files. The base judge still judges every chart note byte-for-byte as before.

Requirement 14 (`perfect_regen` 0.25) is the one exception. The spec says the **default** changes and the existing test is updated, so `judge_config.gd` must change. That file is pinned separately at `fbcf994`, and project history already has the procedure for a user-approved change to it (02.2-26, gap G1). Plan it as an exact repeat: one commit that changes only that line, then one commit that re-baselines `$judgeBase` in `tools/check_timing_gate.ps1`. The judge windows stay at 50/100/130 ms. Note that the spec's Background still quotes the old 35/70 ms windows; they are stale.

The game rules (meter, bag, slot, firing, shields, collision, bounty, duel, medals) belong in a **pure, song-time-driven `MatchSim` referee**. Fed `GameEvent` dictionaries through an `EventChannel`, it runs headless in gdUnit4. In Phase 4 the host runs this same object. Bots are not scripted event emitters. Each bot plays the real chart through its own `VersusJudge`/`VersusHull`, with presses sampled from a seeded Gaussian timing model. Rewards, warheads, duels and bounty therefore come from exactly the same code as the human's. I simulated the spec's 0.12 ratio. A "strong" bot defined as sigma 33 ms with a 1.5% lapse (about 86% Perfect, 12% Good, 2% Miss) earns a mean of **3.0-3.8 rewards on the bundled Expert charts (396-569 notes)**, which satisfies requirement 8 without retuning the ratio.

**Primary recommendation:** Build `MatchSim` + `RewardMeter` + `RewardBag` + `EventChannel` as pure RefCounted classes first (Wave 0). Subclass the pinned judge and hull for the payload overlays. Move only the `judge_config.gd` pin, using the G1 procedure. Define the "strong" bot as sigma 33 ms with a 1.5% lapse.

## Architectural Responsibility Map

(Single-process desktop game. The "tiers" here are the game's own layers.)

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Note judgment (base chart) | Core: `InputJudge` (pinned, unchanged) | - | Timing core must not move |
| Overlay notes (ghost, depth charge), warhead tracking, Crossed Wires input | Core: `VersusJudge extends InputJudge` (new) | `LaneInput` (physical-to-lane remap) | Keeps pinned bytes intact. Remap at the input source so Autoplay/bots (which press by lane) stay correct |
| Hull/score side effects (ghost damage, Ballast, Overclock score) | Core: `VersusHull extends HullScore` (new) | - | Only the owner changes their own hull (ARCHITECTURE.md anti-pattern 3) |
| Reward meter, bag, slot, duel queue | Rules: `RewardMeter`, `RewardBag`, `PlayerState` (pure) | - | Unit-testable, deterministic |
| Firing, shields, immunity, collision, bounty, duel, elimination, standings | Rules: `MatchSim` referee (pure, song-time driven) | `EventChannel` | Phase 4 host runs the same referee |
| Event transport | Seam: `EventChannel` -> `LoopbackChannel` (Phase 3), `NetEventChannel` (Phase 4) | - | Spec constraint |
| Bot rivals | Sim: `BotPlayer` (pure-ish RefCounted) | `MatchSim` | Same rules as the human |
| Disruptor visuals (lane slide, scroll mult, ink, jam, ghost gems, warhead rings) | View: `Highway`, `HighwayNotes`, `NotePainter`, new `InkCloudLayer` | `UiKit.register_fx` for Low/Reduce | View reads modifier state; it never decides rules |
| HUD reward socket, telegraph, periscope panels, killfeed, banners | View: new `src/ui/versus/*` | `Palette`, `UiKit` | Palette-only colours, keep-out rule |
| Match setup, versus results, medals display | View screens | `MedalRules` (pure) | |

## Standard Stack

No new external packages. Everything uses Godot built-ins and the existing project code.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Godot (standard build) | 4.7.2-stable | Engine | Pinned by the project [VERIFIED: `GODOT_BIN` = `Godot_v4.7.2-stable_win64_console.exe`] |
| GDScript | built in | All code | Project constraint |
| `RandomNumberGenerator` | built in | Seeded bag shuffles, bot sampling, payload note generation | A per-object seed/state gives reproducible sequences. Set `seed`, then draw. Never use the global `randi()` [CITED: docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html; same-seed reproducibility VERIFIED headless in this session] |
| gdUnit4 | 6.2.1 (installed) | Tests | [VERIFIED: `addons/gdUnit4/plugin.cfg`] |

### Existing project code to reuse (do not rewrite)
| Code | Use in Phase 3 |
|------|----------------|
| `BeatClock.beat_at / time_at_beat / beats_between` | Beat-snapped launch/arrival, bar lengths for durations (time signatures), payload windows |
| `ChartData.solos` `{start, end, note_count}` | Solo Duel. Already parsed for `.chart` and `.mid` (Phase 2 / 02.2.1) [VERIFIED: chart_data.gd]. Every bundled Expert/Hard solo has 26-48 notes, so all five bundled songs can run a duel on Expert [VERIFIED: notes.chart scan] |
| `Autoplay` pattern (time-ordered press events) | `VersusAutoplay` and `BotPlayer` use the same "events at exact note times, never frame time" pattern (D-28 of Phase 1) |
| `BindingStore` actions `fire` (Space / pad A), `target_cycle` (H / pad Y) | Already in InputMap and the rebind UI [VERIFIED: binding_store.gd, project.godot] |
| `TorpedoSocket` (HUD left console, rect 272,928,80,80) | The home for the meter arc and held-reward icon (UI-SPEC 4.14) |
| `NotePainter.draw_note(type, ...)` | Reserved `NOTE_GHOST`, `NOTE_DISRUPTOR` types (UI-SPEC 4.15) |
| `UiKit.register_fx` + `apply_effect_settings()`/`effect_counts()` | Every new effect node (Low effects / Reduce motion contract) |
| `HitOffsetRecorder`, `RunStats` | Results accuracy per player |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Subclassing `InputJudge`/`HullScore` | Editing them | Violates the 72e21ce pin; re-baselining 4 timing files is far riskier |
| Subclass hull for Ballast/ghost | Calling `hull._damage()` from outside | Works in GDScript, but breaks the "only via apply_* methods" boundary and the underscore convention |
| Bots as real judges | Bots as scripted HULL_STATE/TORPEDO emitters (ARCHITECTURE.md option) | Scripted bots can't exercise warheads, duels, overclock or the meter rules; real-judge bots test everything for about 0.1 ms/frame |
| Separate versus scene | Mode flag in `Gameplay` + a `VersusController` child | A separate scene duplicates 440 lines of run wiring (intro, pause, conductor). Use the mode flag |

**Installation:** none.

## Package Legitimacy Audit

No external packages are installed in this phase. slopcheck is not applicable. **Packages removed:** none. **Flagged:** none.

## Architecture Patterns

### System Architecture Diagram

```
 keyboard/pad ──> LaneInput ──(physical key -> lane remap, Crossed Wires)──> VersusJudge.press(lane, t)
                     │                                                         │  overlay notes first (ghost/depth)
 fire / target ──> FireInput (ticks -> song_time) ──> EventChannel.send(FIRE)   │  else super.press -> InputJudge (pinned)
                                                        │                       v
 Conductor.song_time ───────────────┐                   │            judged / extra_judged / warhead signals
                                    v                   v                       │
                         VersusController._process(t):  MatchSim.update(t) <───┘ (via PlayerState hooks)
                           - human: judge.tick(t)         │  per beat boundary:
                           - bots:  BotPlayer.update(t)   │   1. resolve pending launches of this beat (collisions first,
                             (presses at exact note       │      then shield checks in player-index order)
                              times, seeded Gaussian)     │   2. arrivals: Decoy absorb? else install payload
                                                          │   3. payload ends -> immunity; warhead success -> reflect
                                                          │   4. bounty holder update, solo duel windows
                                                          v
                                               EventChannel.emit(GameEvent{type, song_time, from, to, ...})
                                                          │
            ┌──────────────────────┬──────────────────────┼──────────────────────┬─────────────────────┐
            v                      v                      v                      v                     v
   PayloadStack (per player)   HUD socket/telegraph   PeriscopePanels       Killfeed            MatchLog -> MedalRules
   -> Highway.scroll_mult,     (human)                (bots/rivals)        (top-right)          -> VersusResultsScreen
      lane_pos, jam, ink;
      VersusJudge overlay notes
```

### Recommended Project Structure
```
src/
├── versus/                     # NEW: pure rules + sim (RefCounted, no scene deps, headless-testable)
│   ├── versus_config.gd        # Resource: every Phase 3 tunable (ratio, durations, travel beats, refunds...)
│   ├── reward.gd               # enum + static table: id, name, kind (DISRUPTOR/BUFF), bars, icon key
│   ├── reward_meter.gd         # spec reqs 1, 2 (+ overclock, bounty refund, duel queue)
│   ├── reward_bag.gd           # spec req 3 (seeded Fisher-Yates)
│   ├── player_state.gd         # alive/wreck, slot, queue, shields, buffs, stats counters
│   ├── game_event.gd           # event type constants + constructor helpers (Dictionary payloads)
│   ├── event_channel.gd        # interface: send(e), signal received(e)
│   ├── loopback_channel.gd     # Phase 3 impl (optional injected latency for tests)
│   ├── match_sim.gd            # the referee: beat resolution, collision, bounty, duel, elimination, standings
│   ├── payload_notes.gd        # seeded ghost / depth-charge generators + warhead picker (pure)
│   ├── bot_profile.gd          # Resource: sigma, lapse, fire policy, payload penalties
│   ├── bot_player.gd           # one bot: VersusJudge + VersusHull + seeded presses
│   ├── medal_rules.gd          # pure: match log -> medals
│   └── training_drone.gd       # MATCH-06: fires chosen payloads at the player via LoopbackChannel
├── core/
│   ├── versus_judge.gd         # NEW: extends InputJudge (overlay notes, warheads)
│   └── versus_hull.gd          # NEW: extends HullScore (heal, ghost damage, overclock score)
└── ui/versus/                  # NEW: views (Palette-only; covered by test_color_literals scan of src/ui/**)
    ├── versus_controller.gd    # wires a match into Gameplay's _run_root
    ├── reward_socket.gd        # meter arc + held icon + queue pip on TorpedoSocket
    ├── incoming_alert.gd       # telegraph
    ├── periscope_panel.gd
    ├── killfeed.gd
    ├── duel_banner.gd
    ├── ink_cloud_layer.gd
    ├── match_setup_screen.gd
    └── versus_results_screen.gd
```

### Pattern 1: Extend pinned timing classes, never edit them
**What:** `VersusJudge extends InputJudge` and `VersusHull extends HullScore`, in new files.
**When:** Any payload, buff or bot behaviour that touches judging or hull.
**Example (verified pattern; signal-connected override dispatch confirmed on Godot 4.7.2 headless):**
```gdscript
# src/core/versus_hull.gd
class_name VersusHull
extends HullScore
## Phase 3 hull/score extensions. Never edit hull_score.gd (pinned 72e21ce).

var overclock_until: float = -INF   # song time; set by MatchSim
var now: float = 0.0                # song time of the judgment being processed

func on_judged(lane: int, idx: int, judgment: int, err: float) -> void:
	var m := multiplier()  # score uses the multiplier BEFORE the hit raises combo (HullScore contract)
	super.on_judged(lane, idx, judgment, err)
	if judgment == InputJudge.Judgment.GOOD and now < overclock_until:
		score += (_cfg.score_perfect - _cfg.score_good) * m  # top up to the Perfect value at the pre-hit multiplier
		score_changed.emit(score)

func heal(amount: float) -> void:          # Ballast Patch; caller checks not is_failed
	_set_hull(minf(hull + amount, _cfg.hull_start))

func take_damage(amount: float) -> void:   # Ghost Note hit
	_damage(amount)
```
Do not call `_add_score` for the bonus: it multiplies by `multiplier()` again, after the hit has already raised the combo. Unit-test it: a Good at x4 during Overclock scores 400.

```gdscript
# src/core/versus_judge.gd
class_name VersusJudge
extends InputJudge
signal extra_judged(kind: int, lane: int, judgment: int, error_s: float)  # DEPTH notes
signal ghost_hit(lane: int)
signal warhead_judged(torpedo_id: int, judgment: int)

func press(lane: int, t: float) -> void:
	if _press_overlay(lane, t):   # an overlay note in this lane is within its good window
		return
	super.press(lane, t)          # base chart judgment, byte-identical behaviour

func tick(t: float) -> void:
	super.tick(t)
	_expire_overlay(t)            # depth-charge notes past good_window -> MISS (extra_judged)
```
Warheads are base notes, so they need no overlay. `VersusJudge` listens to its own `judged` signal and checks note indices against the active warhead set.

### Pattern 2: Song-time referee with beat-boundary resolution
**What:** `MatchSim.update(t)` processes everything due up to song time `t` in a fixed order. A Fire press only creates a *pending launch* for `launch_beat = floor(beat_at(t_press) + EPS) + 1`, the next whole beat. At each beat boundary, all launches for that beat resolve together:
1. pair up opposite-direction launches whose flights overlap -> collision
2. remaining launches in player-index order: check the target's shields and same-beat races
3. commit -> `TORPEDO_LAUNCH` with `arrive_beat = launch_beat + torpedo_travel_beats`

**Why:** results never depend on frame rate or on whether the human or a bot was processed first in a frame. Phase 4 can replay the same events on the host.
**Collision rule:** A->B with flight `[La, La+travel)` and B->A with `[Lb, Lb+travel)` collide iff `Lb < La+travel and La < Lb+travel`. With travel = 1 that means `La == Lb`. A press during A's flight snaps to A's arrival beat, so there is no collision. This matches the spec acceptance exactly.

### Pattern 3: Payloads as data + modifier stack, never chart edits
Payloads are data records `{id, kind, from, to, launch_beat, arrive_t, end_t, seed, warheads}`. The target's `PayloadStack` exposes queries: `scroll_mult(t)`, `lane_pos(lane, t)`, `jammed(t)`, `ink_amount(t)`, plus overlay notes pushed into `VersusJudge`. `ChartData` is never mutated, and Highway reads modifier state each frame (ARCHITECTURE.md pattern) [CITED: .planning/research/ARCHITECTURE.md].

### Pattern 4: Bots play the real chart
`BotPlayer` holds `VersusJudge(chart, cfg)` + `VersusHull(cfg)` and a seeded RNG. For each note entering a 1 s lookahead, it samples once:
- lapse (no press), or
- press at `note.time + N(bias, sigma)`

using the profile in effect at that note's time (payload penalties applied). Presses go into a time-ordered queue, and `update(t)` presses everything due, like `Autoplay.update`. The base `InputJudge` judges them. Sampling at lookahead time in note order keeps it deterministic for a given event history.

### Anti-Patterns to Avoid
- **Editing `input_judge.gd`, `hull_score.gd`, `conductor.gd`, `clock_model.gd`:** the timing gate fails. Use subclasses.
- **Injecting overlay notes into `ChartData.notes`:** this breaks `Highway._state` indexing, the `InputJudge` queues built in `_init`, fingerprints and records.
- **Deciding collisions/races by processing order inside a frame:** this is non-deterministic and impossible for the Phase 4 host. Resolve per beat (Pattern 2).
- **Remapping Crossed Wires inside the judge:** Autoplay and bots press by lane, so a judge-level remap breaks them. Remap physical keys in `LaneInput`.
- **Using `Settings.no_fail` in versus:** a player could never be eliminated. Force `no_fail = false` for all versus players.
- **Global `randi()`/`randomize()`:** this breaks the seeded-bag reproducibility (spec req 3).
- **Colour literals in new UI:** `test_color_literals` scans `src/ui/**`. Add tokens to `palette.gd` and contrast rows to `test_contrast`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Beat/bar math across tempo and TS changes | Your own BPM accumulator | `BeatClock.beat_at/time_at_beat/beats_between` | Already handles tempo segments, odd TS, float snapping, tested |
| Judging overlay-vs-base presses | A second full judge | `VersusJudge` overlay queue + `super.press` | One code path for base notes keeps the timing gate meaningful |
| Seeded shuffle | Ad-hoc swaps with `randi()` | Fisher-Yates over `RandomNumberGenerator.randi_range` | Reproducible per seed [VERIFIED headless] |
| Effect settings plumbing | Per-node settings listeners | `UiKit.register_fx` | Project contract, enumerated by the Low/Reduce test |
| Accuracy/grade per player | New formulas | `RunStats.accuracy/grade` | Same numbers as solo results |
| Scene transitions | Custom fades | `ScreenTransition.change_scene` | Project standard |

**Key insight:** almost every hard part (timing, beats, judging, effects contract) already exists. Phase 3 risk is in rule interactions, not primitives, so put rules in one pure referee with exhaustive unit tests.

## Runtime State Inventory

Not a rename/refactor phase. One pinned-baseline change only:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `user://` ScoreStore records were earned with `perfect_regen` 1.0. Regen does not change score or depth, so records stay comparable | None |
| Live service config | None. Offline phase, verified: no network code exists | None |
| OS-registered state | None | None |
| Secrets/env vars | `GODOT_BIN` (User env), unchanged | None |
| Build artifacts | `tools/check_timing_gate.ps1` `$judgeBase = "fbcf994"` must move to the new commit (D-29) | Code edit in a separate commit |

## Hull pin: how to do requirement 14 without silently breaking the gate

**Facts (verified in the repo):**
- `perfect_regen` lives in `src/core/judge_config.gd` (pinned at `fbcf994`), not in `hull_score.gd`. `hull_score.gd` (pinned at `72e21ce`) only reads `_cfg.perfect_regen`, so **the 72e21ce group is untouched**.
- The only test that depends on regen is `tests/test_hull_score.gd:28` (`is_equal(93.0)`). `grep` finds no other `perfect_regen`/`hull_start`/`miss_damage` use outside the two core files. `test_autoplay` and `test_gameplay_smoke` assert hull 100 after all-Perfect runs, which is unaffected.
- The precedent is 02.2-26 (G1): commit `fbcf994` changed exactly the three window defaults in `judge_config.gd` only. Commit `c626ab9` then re-baselined the gate, with the header documenting the user approval and negative checks (whitespace edit -> FAILED).

**Recommended procedure (D-29):**
1. Commit A: `feat(03-xx): perfect_regen 1.0 -> 0.25 (03-SPEC req 14, user-approved 2026-10-08)`. It touches exactly one line of `judge_config.gd` (`git diff --stat` = 1 file, 1+/1-).
2. Commit B: update `tests/test_hull_score.gd` (93 -> 92.25, rename the test to `test_miss_costs_eight_perfect_restores_quarter`, add the 32-Perfects-back-to-100 test).
3. Commit C: `chore(03-xx): timing gate re-baselines judge_config.gd to <A>`. Set `$judgeBase` to A's short hash and add a header paragraph citing 03-SPEC req 14 and noting that the windows are unchanged.
4. Verify: the gate prints OK. Negative check: a scratch whitespace edit prints FAILED. Run `git diff fbcf994 <A> -- src/core/judge_config.gd` and confirm only `perfect_regen` changed.

The gate fails between A and C. That is expected; do not run phase verification in between.

**The alternative (not recommended):** leave the default and set `cfg.perfect_regen = 0.25` where `Gameplay.start()` builds `JudgeConfig`. That avoids moving the pin but contradicts the spec's acceptance criteria ("default becomes 0.25", "the existing hull test is updated"). It also leaves other `JudgeConfig.new()` call sites (e.g. `Bathymeter.estimate_max_depth`, `Highway.setup`) on the old value.

## Common Pitfalls

### Pitfall 1: Overlay notes popping in under the 1-beat flight
**What goes wrong:** with `torpedo_travel_beats = 1` (~0.5 s), a Ghost/Depth Charge payload that injects notes from the arrival time places them about 1 s into the 1.5 s approach (1x scroll). They appear mid-highway.
**How to avoid (D-14):** injected notes start at the first beat at or after `arrive_t + approach_s(target)`, so they enter at the far end. The payload's active window for TORP-05 is `[arrive_t, injection_end]`.
**Warning signs:** a visual test finds an overlay gem with depth < `Trench.D_FAR` on its first drawn frame.

### Pitfall 2: Ambiguous presses between base and overlay notes
**What goes wrong:** a press near both a Depth Charge note and a base note in the same lane is judged against the wrong one.
**How to avoid:** `PayloadNotes` never places an overlay note within `good_window + early_miss_window + 0.02` s (0.25 s) of any base note in that lane, inside a base sustain (head .. tail + release_forgive), or within the same spacing of another overlay note. Then the overlay window and the base window cannot overlap, and the router order doesn't matter. Unit-test this invariant on all 5 bundled charts x 4 difficulties.

### Pitfall 3: Crossed Wires and held sustains
**What goes wrong:** a key held across the remap releases a different lane than it pressed. The hold either never ends (or the wrong one ends early), or a stray is generated.
**How to avoid:** `LaneInput` records `pressed_lane[physical_key]` at press time and releases that lane, whatever the current map is. The remap switches only at the end of the 1-beat slide (D-10).

### Pitfall 4: Callable dispatch assumption
**Verified:** a parent's `signal.connect(on_judged)` calls the subclass override, and `super.on_judged()` and the parent's `_priv()` are callable from the subclass (headless Godot 4.7.2 run in this session: output `["child7","base7","priv7"]`). Keep a regression test so a future engine bump can't silently change it.

### Pitfall 5: Elimination vs regen
**What goes wrong:** `HullScore._damage` sets `is_failed` once, but later Perfects still regen hull above 0 because `on_judged` doesn't check `is_failed`. Ballast could also "revive".
**How to avoid:** the eliminated state lives in `PlayerState.alive` (set on `failed`). UI shows WRECK, not hull. `MatchSim` refuses Ballast and the bag for wrecks. Standings use `alive`/`eliminated_at`, never `hull > 0`.

### Pitfall 6: Frame-order nondeterminism
**What goes wrong:** the human and bots are processed sequentially in `_process`, so "same beat" decisions vary with frame timing.
**How to avoid:** Pattern 2 (beat-boundary resolution, index-ordered ties). Test: run the same scripted match at simulated 30, 144 and 1000 fps steps and get identical event logs.

### Pitfall 7: Killfeed glyphs
**What goes wrong:** the spec's examples use `⟶ ↩ 🛡 ✕ 💀`. Oxanium almost certainly lacks the emoji, which then render as tofu [ASSUMED; check with `Font.has_char()`].
**How to avoid:** draw these as `UiIcons` vector glyphs inline (HBox of Label + icon). Keep the text parts as in the spec. Add a test that the killfeed font `has_char` every text character used.

### Pitfall 8: Pressure Crack at high scroll settings
**What goes wrong:** the user's scroll speed can be up to 3.0, and x1.5 gives 4.5x (approach 0.33 s), which is borderline unreadable.
**How to avoid:** `effective = min(base x 1.5, max(base, pressure_crack_max_speed = 3.5))`, tunable. Flagged for playtest.

### Pitfall 9: Solo Duel resolution timing
**What goes wrong:** resolving at `solo.end` happens before the last notes are judged (late-Good window).
**How to avoid:** resolve at `solo.end + good_window + 1e-3`. Count only base-chart notes with `start <= time <= end`.

### Pitfall 10: Keyboard rollover on Fire during chords
Space plus 3 lane keys can ghost on cheap keyboards [CITED: .planning/research/PITFALLS.md]. Space and H defaults already exist, and rebind exists. Add a playtest checklist line; no code change.

### Pitfall 11: Reward frequency is very skill-sensitive
The simulation (below) shows the 0.12 ratio gives a "medium" player (sigma 42 ms, 3.5% lapse, ~74% Perfect) only **0.2-0.7 rewards per Expert song**, while strong/ace players get 3-6. Requirement 8 is still met (it targets the strong bot), but weaker friends may rarely fire on Expert. Surface this in UAT and keep the ratio tunable. The spec defers rubber-banding.

## Bot skill model (simulation evidence)

Model: per note, lapse with probability L (miss), else timing error ~ N(0, sigma). Perfect <= 50 ms, Good <= 100 ms (the current JudgeConfig). Meter per spec reqs 1-2. The bot fires about 4 notes after earning. 3,000 seeded trials per row, Node script in the scratchpad [VERIFIED: simulation run this session; model, not engine].

| Profile | sigma / lapse | Perfect / Good / Miss | Rewards/song @ 396 | @ 471 | @ 569 | @ 1000 |
|---------|---------------|-----------------------|-------------------|-------|-------|--------|
| ace | 22 ms / 0.4% | 97 / 2 / 0.4% | 6.4 | 6.3 | 6.2 | 5.8 |
| strong (recommended) | **33 ms / 1.5%** | 86 / 12 / 2% | **3.8** | **3.4** | **3.0** | 1.6 |
| (strong at 30/1.2%) | 30 ms / 1.2% | 89 / 9 / 1% | 4.6 | 4.3 | 3.9 | 2.6 |
| medium | 42 ms / 3.5% | 74 / 21 / 5% | 0.7 | 0.5 | 0.2 | 0.0 |
| weak | 55 ms / 7% | 59 / 27 / 13% | 0.0 | 0.0 | 0.0 | 0.0 |

Bundled note counts (ChartData counts each chord note): Expert 396 (HRT), 416 (April), 440 (Invisible), 471 (Shanty), 569 (Space). The maximum possible is `floor(1/0.12)` = 8 rewards. Real players' errors are streaky (correlated), so in-engine numbers will differ. Requirement 8's acceptance test is the in-engine harness run (Validation), not this table.

## Code Examples

### Seeded bag (spec req 3)
```gdscript
# src/versus/reward_bag.gd — Fisher-Yates with a private RNG (never the global one)
class_name RewardBag
extends RefCounted
var _rng := RandomNumberGenerator.new()
var _bag: Array[int] = []

func _init(seed_value: int) -> void:
	_rng.seed = seed_value

func draw() -> int:
	if _bag.is_empty():
		_bag = Reward.ALL.duplicate()
		for i in range(_bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp := _bag[i]; _bag[i] = _bag[j]; _bag[j] = tmp
	return _bag.pop_back()
```
Seed per player = `hash([match_seed, player_index])` (Phase 4 sends `match_seed` in the lobby start).

### Beat-snapped launch (TORP-02)
```gdscript
const EPS := 1e-6
static func launch_beat(t_press: float, tempo_map: Array) -> int:
	return int(floor(BeatClock.beat_at(t_press, tempo_map) + EPS)) + 1  # next whole beat, never "now"

static func beat_time(b: int, tempo_map: Array) -> float:
	return BeatClock.time_at_beat(float(b), tempo_map)
```
Durations in bars use `time_sigs`: `bar_beats = num * 4 / den` at the arrival time (BeatClock convention).

### Threshold (spec req 1)
```gdscript
static func threshold(note_count: int, ratio: float) -> int:
	return maxi(1, ceili(ratio * note_count - 1e-9))  # 1000 -> 120, 400 -> 48; guard float noise
```
Checked in float64 (same as GDScript `float`): `0.12 * 400` = 48 and `0.12 * 1000` = 120 exactly, so a plain `ceil` passes both acceptance values. The `- 1e-9` guard is defensive only, for ratios retuned later (e.g. 0.07 x 100 = 7.000000000000001). Bundled Expert thresholds: 396 -> 48, 416 -> 50, 440 -> 53, 471 -> 57, 569 -> 69.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| One tube = one torpedo, 5 payloads incl. Lane Flip | Killstreak meter, 9-item seeded bag, Crossed Wires | 03-SPEC 2026-10-08 | REQUIREMENTS PAY-02 text is stale (update at transition) |
| Judge windows 35/70 ms (03-SPEC Background) | 50/100/130 ms | 02.2-26 G1, 2026-10-11 | Bot sigma calibrated against 50/100 |
| `perfect_regen` 1.0 | 0.25 | 03-SPEC req 14 | Gate re-baseline (D-29) |
| ARCHITECTURE.md 2-beat flight | 1-beat flight, alert at launch | 03-SPEC req 9 | Overlay-note lead rule (Pitfall 1); Phase 4 latency budget ~0.4-0.5 s, still above typical RTT/2 |

## Recommended Decisions (orchestrator defaults)

These answer every Phase 3 requirement the spec left open. All numbers go in `VersusConfig` (a Resource like `JudgeConfig`) so playtests can tune them. The orchestrator can lock them as CONTEXT decisions.

**Targeting (TORP-03)**
- **D-01** Target modes cycle on `target_cycle` (H / pad Y) in this order: `AUTO` (leader) -> each living rival in seat order -> `ATTACKERS` -> back to `AUTO`. The mode is shown on the HUD under the socket and as a bracket on the targeted periscope panel.
- **D-02** `AUTO` targets the alive rival with the highest depth. If you are the leader, it targets the second-highest. Ties go to the lower seat index. A manually locked rival who dies falls back to `AUTO`.
- **D-03** `ATTACKERS` targets whoever most recently *launched* a disruptor at you (not only landed ones). With no attacker yet, it behaves as `AUTO`.

**Telegraph and flight (TORP-02/04)**
- **D-04** Fire press -> launch at the next whole beat (Pattern 2), arrival `torpedo_travel_beats` (1) later. The target is alerted at launch: sonar-ping SFX, red flash on the target's HUD edge (human) or panel (bot), and the incoming payload's icon with a 1-beat countdown ring.
- **D-05** Warhead notes are marked at launch, so the warning shows before arrival.

**One active payload + immunity (TORP-05)**
- **D-06** A player is *shielded* while a disruptor is in flight to them, active on them, or in immunity. Fire at a shielded target is refused at press time (HUD "SHIELDED", reward kept, short error blip). For same-beat races on one target, the lower seat index launches and the others get the reward back.
- **D-07** Immunity = 1 bar (`immunity_bars`) after a payload ends, including after reflection ends it early. Decoy absorption and collisions start no immunity (spec).

**Fairness (TORP-06)**
- **D-08** No payload needs mashing (all effects are timed windows). Ghost hits cost `ghost_hull_damage` 4 each, capped at `ghost_damage_cap` 12 per payload. Depth Charge misses cost the normal 8, but its note count is capped (D-14). Test: the worst case for each payload from full hull leaves hull > 0, and autoplay is all-Perfect under each payload.

**Payload specifics (PAY-01/03/04/05)**
- **D-09** Pressure Crack: `scroll_mult` 1.0 -> 1.5, easing in (smoothstep) over 1 beat at arrival and out over 1 beat at the end. The effective speed is capped by `pressure_crack_max_speed` 3.5 (Pitfall 8). Judgment is untouched.
- **D-10** Crossed Wires: two distinct lanes from the payload seed. Lane columns (strip, gems, receptor, labels) slide to swapped positions over 1 beat. **Input switches at the end of the slide** and switches back at the end of the return slide. Held keys release the lane they pressed (Pitfall 3).
- **D-11** Ghost Notes: hollow gem (`NOTE_GHOST`): lane shape outline only, 3 px dashed rim, no core fill, no halo, in all effect modes. One ghost per beat on average (`ghost_per_beat` 1.0) on the 8th-note grid, with spacing per Pitfall 2.
- **D-12** A ghost hit costs hull (D-08) and breaks combo and perfect streak (like a stray) but **does not touch the reward meter** (it is a press with no real note: spec "stray doesn't change it"). An ignored ghost does nothing.
- **D-13** Ink Cloud: an opaque `ABYSS_900` band over depth d in [-0.15, 0.35] of the board, i.e. the 35% of travel nearest the hit line. The hit line ticks and receptor outlines are redrawn above the ink at 60% so players can still see where to hit. Full effects: soft noise edge. Low effects: flat band.
- **D-14** Depth Charge: 8th-note grid in its window. The window starts at the first beat at or after `arrive_t + approach_s` and lasts 2 bars. It skips grid points that carry a base note in any lane, and respects spacing (Pitfall 2). Count cap = `min(floor(depth_charge_density x base_notes_in_window), grid_free_points)` with `depth_charge_density` 0.5, at least 2. Lanes are seeded. Overlay notes are real notes: Perfect/Good/Miss score, regen, damage and meter credit like base notes, but they don't change the threshold and don't count for Solo Duel %.
- **D-15** Sonar Jam: gems drawn as a plain circle in a new `Palette.JAM_GREY` (proposal: `TEXT_MID`-based so the existing contrast row applies). No lane shape, no lane colour, same position. Warhead rings stay visible.

**Return to Sender (PAY-06)**
- **D-16** Every disruptor (not debris) carries warheads: the first `warhead_count` 4 base notes with time at or after `arrive_t`, extended to whole chords. They show a `WARNING_RED` ring and chevron from launch. If fewer than 4 notes remain, there are no warheads (not reflectable).
- **D-17** If all warheads are Perfect (raw judgment; Overclock does not count), the payload ends on the target (1-beat ease out, immunity starts) and relaunches at the sender on the next beat with 1-beat flight. A reflected torpedo has no warheads (no ping-pong), can be absorbed by the sender's Decoy, and fizzles if the sender is shielded or dead (it still counts as reflected for stats and medals). Any warhead below Perfect ends the reflect chance.

**Bots (MATCH-01)**
- **D-18** Match = 1 human + 1-3 bots (default 3, a 4-sub match). Everyone plays the human's chosen song **and difficulty** (same ChartData). Match setup screen: bot count, bot skill (Rookie / Regular / Veteran = weak / medium / strong), seed hidden (random per match, shown in results for repro).
- **D-19** Bot timing: sigma/lapse per profile. Veteran = strong 33 ms / 1.5%, Regular = 42 ms / 3.5%, Rookie = 55 ms / 7%. No stray presses. Payload penalties while affected: Crossed Wires lapse +6%, Ink Cloud sigma x1.3, Pressure Crack sigma x1.2, Sonar Jam lapse +4%, Ghost Notes press each ghost with p 0.15 (Veteran) / 0.3 / 0.45, Depth Charge played with the normal profile.
- **D-20** Bot fire policy: fire a disruptor 1-8 beats after earning it (seeded), at `AUTO`, or `ATTACKERS` with p 0.3. Re-pick if shielded and retry each beat. Decoy and Overclock: use immediately. Ballast: use when hull <= 75, or after 16 bars if hull is still above 75.
- **D-21** Bot names from a fixed list (MAKO, ORCA, BARRACUDA, LAMPREY, NARWHAL, MORAY). The human is shown as "YOU" (a player name setting arrives in Phase 4).

**Win and standings (MATCH-02)**
- **D-22** When one sub is left alive, it is declared the winner on the spot ("LAST HULL STANDING" banner). The song still plays to the end, wrecks keep playing, and results come at the song end. If everyone left is eliminated in the same beat, the deepest wins.
- **D-23** Placement: survivors first, ordered by depth, then hull, then accuracy, then max streak. Exact equality = shared placement. Then eliminated players by later elimination time first, ties by depth. Versus ignores No-Fail (forced off). Pause is allowed offline (bots follow the song clock). Versus does not write ScoreStore records.

**Wreck ghosts (MATCH-03)**
- **D-24** On elimination: an IMPLOSION flash (not the solo FailScreen; the song continues). The held reward, queue and active buffs are lost, and in-flight torpedoes from the wreck still resolve. The player keeps playing as a WRECK with a debris meter. Same threshold, filled by Perfects, no bag.
- **D-25** Debris attacks: alternately "Silt" (Ink Cloud at d [-0.15, 0.20], 1 bar) and "Groan" (Pressure Crack x1.25, 1 bar). Cap `debris_max_per_wreck` 2 per song. Auto-target only: the leader. With 3+ alive, a debris attack never targets the lowest-depth living sub. Obeys shields/immunity. Decoy can absorb it. No warheads, no bounty, no collision, not counted for Untouchable, but listed in the killfeed as `WRECK ⟶ Silt ⟶ SAM`.

**Periscope panels (MATCH-04)**
- **D-26** Up to 3 panels in the left column, x 24..376, y 216..584 (about 112 px each). This area is outside the 7.1 keep-out and below the bezel. Each panel shows the callsign, a segmented hull bar (or WRECK), a tube meter arc with the held-reward icon, incoming/active payload icon with a beat countdown, a bounty marker, a target bracket, and Solo Duel live Perfect % during solos. A small scope blips on the rival's Perfects (decorative). No rival highway in Phase 3. The killfeed goes in the right column at x 1544..1896, y 216..400 (avoiding the right bezel curve). The keep-out test must cover both.

**Solo Dive (MATCH-06)**
- **D-27** The existing Practice Dive becomes Solo Dive training. A new "Training payloads" row in Song Select's detail panel offers Off (current Practice behaviour), All, or a single named payload. With payloads on, a `TrainingDrone` (a dummy rival on LoopbackChannel) fires the chosen payloads round-robin every `training_interval_bars` 8, with full telegraph and warheads. The player's own meter, bag and buffs work. Disruptors the player fires hit the drone (killfeed line only). No-Fail stays forced, and no records are written (unchanged).

**Cross-cutting**
- **D-28** Architecture: subclass the pinned judge and hull (Pattern 1). Use a pure `MatchSim` referee with beat-boundary resolution (Pattern 2). `VersusController` lives under `Gameplay._run_root` behind a mode flag (`Gameplay.pending_match`). The plain solo path keeps the base `InputJudge`/`HullScore` classes unchanged.
- **D-29** Requirement 14 ships via the G1 procedure (commits A/B/C above). This is the only pinned file touched in Phase 3. The 72e21ce group stays pinned and every plan runs the gate.
- **D-30** `chart_note_count` = `chart.notes.size()` of the base chart (each chord note counts, matching how each note is judged). Overlay notes never change the threshold.
- **D-31** Meter details: Depth Charge overlay Perfects add to the meter (D-14). Bounty refund overflow -> instant reward, and if the slot is full it goes to the queue only when it is the duel queue. Otherwise the overflow is dropped and the meter stays full (spec: "the extra is dropped").
- **D-32** Killfeed icons are `UiIcons` vector glyphs, not emoji (Pitfall 7). The own-line highlight is a `SONAR` left bar plus `TEXT_HI`; other lines use `TEXT_MID`.
- **D-33** Reward HUD: the meter is a 270-degree arc around `TorpedoSocket` (r 40, `SONAR`, full = `SONAR_PALE` pulse). The held reward icon sits in the socket with its name under it (Label 20). Disruptors use a `WARNING_RED` edge, buffs a `SONAR` edge. The duel-queue pip is a small `REWARD_GOLD` dot (left console only, outside the keep-out). Active buff state shows a chip with a bar countdown above the socket.

## Suggested plan breakdown (waves)

The `ui_phase` setting is true. Run `/gsd:ui-phase 3` before planning so a 03-UI-SPEC pins the exact layout of the socket arc, panels, killfeed, banners, gem types and results medals. If that is skipped, Wave 2 plans must carry the D-26/D-33 rects.

| Wave | Plan | Content | Requirements | Depends |
|------|------|---------|--------------|---------|
| 0 | 03-01 | Hull regen pin move (A/B/C commits, D-29), `VersusConfig`, `Reward` table, `RewardMeter`, `RewardBag`, threshold epsilon tests | spec 1, 2, 3, 7, 14; TORP-01 (logic) | - |
| 0 | 03-02 | `GameEvent`, `EventChannel`, `LoopbackChannel`, `PlayerState`, `MatchSim` (fire, beat snap, shields/immunity, collision, bounty, buffs state, elimination, standings), determinism test | spec 4, 6, 9, 10; TORP-02/03/05; MATCH-02 | 03-01 |
| 1 | 03-03 | `VersusJudge`, `VersusHull`, `PayloadNotes` (ghost, depth charge, warheads, spacing invariant over all bundled charts), `VersusAutoplay`, reflect logic in MatchSim | spec 5 (logic), 6; PAY-03/05/06; TORP-06 | 03-02 |
| 1 | 03-04 | `BotProfile`, `BotPlayer`, bot fire policy, headless `MatchHarness` (runs a full song in sim time), strong-bot frequency report on 5 songs, `SoloDuel` resolution, `MedalRules` | spec 8, 11, 13; MATCH-01 (logic) | 03-02 (03-03 for payload penalties) |
| 2 | 03-05 | Board visuals: `Highway` lane_pos remap + slide, `LaneInput` remap, scroll_mult ease, `InkCloudLayer`, Sonar Jam paint, `NOTE_GHOST`/warhead/overlay gems, Low/Reduce contract, extended visual-sync tests | PAY-01..05 visuals, spec 5 | 03-03 |
| 2 | 03-06 | Versus HUD: reward socket, telegraph, target mode, periscope panels, bounty marker, duel banner + live %, killfeed; keep-out, colour-literal and contrast tests | TORP-01/03/04, MATCH-04, spec 10-12 views | 03-02 |
| 3 | 03-07 | Integration: `VersusController`, match setup screen + main menu entry, wreck ghosts + debris, IMPLOSION-in-match, versus results screen with medals, Solo Dive training payloads | MATCH-01/03/05/06, spec 12-13 | 03-04, 03-05, 03-06 |
| 3 | 03-08 | Verification: full suite, timing gate, 5-song strong-bot run, autoplay under each payload on a bundled song, screenshots + visual review, friend zip v0.6, UAT sheet (human checkpoint, end of phase) | all | 03-07 |

8 plans (coarse granularity). 03-03/03-04 and 03-05/03-06 can run in parallel. Every plan runs `tools/check_timing_gate.ps1`, which must be OK after 03-01 commit C.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Oxanium lacks the emoji/arrow glyphs in the spec's killfeed examples | Pitfall 7 | Low: if present, the icons are still fine |
| A2 | Strong-bot frequency in-engine will be close to the iid simulation (3.0-3.8 on bundled Expert) | Bot skill model | Medium: if it is outside 2-4, tune sigma (the definition of "strong") before the ratio, and record it |
| A3 | All D-xx defaults (immunity 1 bar, ghost damage 4/cap 12, warhead count 4, debris rules, bot penalties, panel rects) | Recommended Decisions | Medium: design feel; all are tunables, so confirm in UAT |
| A4 | Players accept that "medium" skill rarely earns rewards on Expert with the locked 0.12 ratio | Pitfall 11 | Medium: fun risk; the ratio is tunable and rubber-banding is deferred by spec |
| A5 | Same-difficulty-for-all is acceptable offline (depth comparisons fair) | D-18 | Low: Phase 4 may revisit mixed difficulties |

## Open Questions (RESOLVED)

All four were resolved by 03-CONTEXT.md "Open questions resolved by default" (2026-10-15).

1. **Ballast Patch 25%** is still marked "unconfirmed" in the spec. Recommendation: ship 25 as a tunable and ask in UAT. **RESOLVED:** Ballast Patch restores 25% hull (VersusConfig.ballast_restore_ratio), confirmed in UAT.
2. **Does reflection count as "landed" for the shooter's stats?** Recommendation: no. Track it as `reflected_by_target`. Results show landed and reflected separately (MATCH-05). **RESOLVED:** a reflected shot does not count as landed for the original shooter.
3. **Mixed difficulties in versus:** deferred to Phase 4 (D-18 keeps them the same). **RESOLVED:** every player in a match uses the same difficulty; mixed difficulties are deferred to Phase 4.
4. **Should a Ghost hit reset the reward meter?** D-12 says no (consistent with the stray rule). The user may want teeth; tunable flag `ghost_resets_meter` = false. **RESOLVED:** a ghost hit does not reset the reward meter (ghost_resets_meter = false).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Godot console build | tests, gate, export | ✓ | 4.7.2-stable (`GODOT_BIN`) | - |
| gdUnit4 | tests | ✓ | 6.2.1 | - |
| PowerShell | `run_tests.ps1`, `check_timing_gate.ps1` | ✓ | Windows built in | - |
| git | gate (diff vs pin) | ✓ | - | - |
| Python | none needed (sim was done in Node) | ✗ (Store alias only) | - | Node 26 is available for any ad-hoc analysis |

**Missing dependencies with no fallback:** none.

## Validation Architecture

(`workflow.nyquist_validation` is false in config. The section is included because the orchestrator asked for it; it is concise.)

| Property | Value |
|----------|-------|
| Framework | gdUnit4 6.2.1 on Godot 4.7.2 headless |
| Quick run | `powershell -NoProfile -File tools/run_tests.ps1 -Path res://tests/test_<suite>.gd` |
| Full suite | `powershell -NoProfile -File tools/run_tests.ps1` |
| Gate | `powershell -NoProfile -File tools/check_timing_gate.ps1` -> `TIMING GATE OK` |

| Req | Behavior | Type | Test file (Wave 0 = new) |
|-----|----------|------|--------------------------|
| spec 1/2 | threshold 120/48, 119 vs 120, miss reset, hold stops meter, 50 extra Perfects no second reward | unit | `test_reward_meter.gd` ❌ |
| spec 3/7 | 9 unique, same seed same order, pool == 9 without Lane Flip | unit | `test_reward_bag.gd` ❌ |
| spec 14 | 100 -> 92 -> 92.25; 32 Perfects -> 100 | unit | `test_hull_score.gd` (edit) |
| spec 4/9, TORP-02/05 | launch on next beat, arrival +1 beat, shielded refusal, same-beat race, collision vs no collision | unit | `test_match_sim_fire.gd` ❌ |
| spec 10 | refund 30 of 120, Decoy gives 0, marker moves on the same update, ties keep holder | unit | `test_match_sim_bounty.gd` ❌ |
| spec 6 | Ballast 90->100, 50->75, no revive; Decoy one absorb or 8-bar expiry; Overclock Good +1 meter and Perfect score for 4 bars | unit | `test_buffs.gd` ❌ |
| spec 5, PAY-03/05, TORP-06 | overlay spacing invariant on 5 songs x 4 diffs; autoplay all-Perfect under each payload; ghost damage cap | unit/integration | `test_payload_notes.gd`, `test_versus_judge.gd` ❌ |
| PAY-06 | 4 Perfect warheads reflect, 3P+1G doesn't, reflected has no warheads, Decoy absorbs reflected | unit | `test_return_to_sender.gd` ❌ |
| spec 11 | 20-note solo 90 vs 86 -> A wins; all < 85 none; 10-note no duel; queued prize | unit | `test_solo_duel.gd` ❌ |
| spec 13 | scripted logs -> expected medals, first 3 in order, ties | unit | `test_medal_rules.gd` ❌ |
| spec 8, MATCH-01 | strong bots 2-4 rewards per bundled song (headless sim harness) | integration | `test_bot_frequency.gd` ❌ |
| determinism | same seed + inputs -> identical event log at 30/144/1000 fps stepping | integration | `test_match_determinism.gd` ❌ |
| MATCH-02/03 | standings and tie-breaks, wreck debris cap and target rule | unit | `test_match_standings.gd` ❌ |
| spec 12, MATCH-04 | killfeed one line per event, 5th pushes oldest, 4 s fade; panels inside allowed rects | scene | `test_killfeed.gd`, `test_layout_keepout.gd` (extend) |
| PAY visuals | gem on hit line at its time under Crossed Wires / Pressure Crack; Low effects readability | scene | `test_visual_sync.gd` (extend), `test_effect_settings.gd` (extend) |
| regression | Callable override dispatch on InputJudge/HullScore subclasses | unit | `test_versus_subclass.gd` ❌ |

Manual-only: feel of telegraph timing, readability under each payload at 1x/3x scroll, fun of bot skill tiers (UAT checkpoint in 03-08).

## Security Domain

Local, offline phase. No network, auth or crypto.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | - |
| V3 Session Management | no | - |
| V4 Access Control | no | - |
| V5 Input Validation | yes (light) | Clamp `VersusConfig` and match-setup values (bot count 1..3, ratios 0..1, bars >= 1). Treat `ChartData.solos` and section data from user-imported charts as untrusted: ignore solos with end <= start or outside the song, and cap overlay-note generation (bounded loops; `BeatClock.MAX_BEATS` precedent) |
| V6 Cryptography | no | Seeds are not security material |

| Threat | STRIDE | Mitigation |
|--------|--------|-----------|
| Hostile imported chart with absurd tempo or solo markers causing huge overlay generation | DoS | Bounded generators, minimum spacing, per-payload caps |
| Phase 4 forward risk: a peer lying about hull/rewards | Tampering | Out of scope now. Keeping rules in `MatchSim` makes host-side sanity checks possible later (ARCHITECTURE.md trust model) |

## Project Constraints (from CLAUDE.md and STATE)

- Godot 4.7.2 standard build, GDScript, gdUnit4 via `tools/run_tests.ps1`.
- Timing gate: `conductor.gd`, `clock_model.gd`, `input_judge.gd`, `hull_score.gd` byte-identical to `72e21ce`; `judge_config.gd` to `fbcf994` (moves once in this phase, D-29). Every plan runs the gate.
- Colours from `Palette` only (`test_color_literals` scans `src/ui/**`). New tokens get contrast rows.
- Every effect node registers through `UiKit.register_fx` and implements `apply_effect_settings()` / `effect_counts()` (Low effects and Reduce motion).
- Note-path keep-out (UI-SPEC 7.1) applies to every new HUD element.
- Judgment local; game events only through the EventChannel seam.
- GSD workflow: changes go through `/gsd:execute-phase` plans.

## Sources

### Primary (HIGH confidence)
- Repo code read this session: `src/core/{judge_config,hull_score,input_judge,conductor,beat_clock,chart_data,autoplay,trench}.gd`, `src/input/{lane_input,binding_store}.gd`, `src/ui/{gameplay,highway,hud,arena}.gd`, `src/ui/gauges/torpedo_socket.gd`, `tools/check_timing_gate.ps1`, `tests/test_hull_score.gd`
- `.planning/phases/03-offline-versus/03-SPEC.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, `.planning/PROJECT.md`, `.planning/STATE.md`, `02.2-26-SUMMARY.md` (G1 pin precedent), `02.2-UI-SPEC.md` (4.14, 4.15, 7.1-7.3)
- Headless Godot 4.7.2 check (this session): subclass override dispatch through a parent-connected signal, `super.method()`, parent underscore methods, seeded `RandomNumberGenerator`
- Godot docs, RandomNumberGenerator: https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md`, `FEATURES.md`, `PITFALLS.md`, `GAME-IMPROVEMENTS.md` (project research, 2026-10-07/08)
- Node simulation of the reward meter under Gaussian bot timing (this session; model, not engine)

### Tertiary (LOW confidence)
- None used for decisions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH (no new dependencies; versions verified locally)
- Architecture: HIGH (integration points verified in code; override dispatch verified in engine)
- Pin strategy: HIGH (gate script and precedent read)
- Bot calibration: MEDIUM (simulation only)
- Design defaults: MEDIUM (proposals; need UAT)

**Research date:** 2026-10-15
**Valid until:** 2026-11-15 (stable engine pin; re-check if Godot is bumped)
