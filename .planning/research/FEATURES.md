# Feature Landscape

**Domain:** Competitive online rhythm game (Guitar Hero / Clone Hero lineage) with Tetris 99 / Puyo-style attack mechanics, friends-only 2-4 players
**Project:** UNDERTOW
**Researched:** 2026-10-07
**Confidence:** MEDIUM overall. Based on established knowledge of Guitar Hero, Clone Hero, YARG, osu!mania, Rock Band, GH3 Battle Mode, Tetris 99 and Puyo Puyo. No live web verification was done in this pass. Specific numbers (timing windows, attack counts) are flagged LOW where they come from memory and should be checked during implementation.

## Table Stakes

Missing any of these makes the game feel broken or unfair.

### Rhythm core

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Audio-clock-driven note scrolling and judgment | Mushy timing kills a rhythm game. Frame-time drift is the classic failure. | Med | Use the audio playback position (with output latency compensation), not delta accumulation. Core Value item. |
| Timing windows with tiers (Perfect / Good / Miss) | Players need graded feedback. Streaks that charge torpedoes need a defined "good hit". | Low | Clone Hero uses a single ~±70ms-ish window for notes. osu!mania uses 5-6 tiers. Recommend 3 tiers: Perfect ~±30-35ms, Good ~±50-70ms, Miss beyond. LOW confidence on exact numbers. Make them constants for tuning. |
| Per-player audio/visual latency calibration | Different PCs, DACs, displays. Fairness depends on it. | Med | Tap-along calibration screen plus manual offset slider, saved per player. Separate audio and visual offsets (Clone Hero and YARG both offer this). |
| Hit feedback (visual flash, sound, judgment text) | Without it notes feel like they vanish. | Low | Per-lane hit flash, hit sound option, early/late indicator. Early/late indicator doubles as calibration aid. |
| Miss feedback and hull damage | Defines the health loop. | Low | Distinguish a missed note from an overstrum/ghost tap if you allow extra input (see Anti-features). |
| Combo/streak counter and score multiplier | Genre signature. Streak also feeds torpedo charge. | Low | Decide early whether score multiplier and torpedo streak are the same counter. Recommend separate: streak of Perfects charges tube, combo drives score. |
| Sustain notes (hold) | Chart import of GH charts is full of them. Missing sustains breaks imported charts. | Med | Head hit plus hold to tail. Define release leniency. Sustain breaks should be forgiving (Clone Hero style). |
| Chords / simultaneous notes | Same reason: imported charts use them. | Med | On 4 lanes with keyboard, chords of 2 are fine. Imported 5-fret charts need a lane-mapping/reduction step (see Dependencies). |
| HOPO / tap equivalents | Imported GH charts rely on HOPOs. | High | Decision needed: keyboard players have no strum. Recommend NOT modeling strum/HOPO; treat every note as a keypress and convert HOPO/tap to normal notes at import. Removes the need for a strum key. |
| Song select screen (list, search/sort, difficulty, preview audio) | Players pick songs from imported library. | Med | Sort by title/artist, show duration and chart difficulty, preview clip. Needs library scan and cache. |
| Chart import (.chart / .mid + audio, song.ini metadata) | Core content strategy. | High | Parse tempo map, time signatures, sync tracks, sustains, star power (ignore), multiple stems. Mapping 5 frets to 4 lanes is the hard part. Single biggest content risk. |
| Pause / resume / restart / quit (solo) | Expected in solo/practice. | Low | Online: no pause. See Anti-features. |
| Results screen | Closes the loop. In PROJECT.md. | Low | Placement, depth (score), accuracy, max streak, torpedoes fired/landed/reflected, hull remaining. |
| Rebindable keys and gamepad support | Keyboards differ (layouts, ghosting). In PROJECT.md. | Med | Test key rollover/ghosting on 4 lane keys + Fire. Allow separate bindings per player profile. Gamepad needs deadzone and button remap. |
| Settings: scroll speed, volume mix (music/SFX), video options, note/highway opacity | Standard in every rhythm game. | Low | Scroll speed is critical for readability. Pressure Crack payload must be relative to the player's own speed. |
| Fixed-length, countdown start, synced song start | Everyone must start together. | Med | Clock sync plus scheduled start time. |
| Lobby: create / join by code, ready-up, song hash check | Friends-only online loop. | Med | Show who is missing the song, host picks song and difficulty. |
| Disconnect handling | Home networks drop. | Med | Treat dropped player as eliminated (wreck) or removed; game must not hang. |
| Elimination and winner determination | Defines match end. | Low | Last hull wins; deepest wins if song ends. Tie-break rule needed. |

### Versus / attack core (lessons from Tetris 99, Puyo Puyo, GH3 Battle)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Attack meter that visibly fills | Players must see attack progress. | Low | Torpedo tube. |
| Clear incoming-attack telegraph | Fairness: Puyo shows incoming garbage preview, Tetris 99 shows a warning meter. Surprise attacks feel cheap. | Med | Rival panel flashes, countdown to impact snapped to beat, show payload type icon. Arrival is beat-quantized so players get a readable 1-2 beat warning. |
| Attacks are survivable by skill | GH3 lesson, see below. | Med | Every payload needs a counterplay read. |
| Target selection (at least a default plus manual) | Tetris 99 core feature. | Med | See targeting section. |
| Live view of rivals' state | Hull and streak of rivals needed to choose targets. | Med | Periscope panels. Keep to compact data (hull, streak, tube level). |
| Spectate/ghost play after elimination | Avoids sitting out. In PROJECT.md. | Med | Wreck ghosts with weak debris attacks. |

## Differentiators

What sets UNDERTOW apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Streak-as-torpedo (skilled play = attack, no item pickups) | Unlike GH3 Battle (random power-ups from star phrases) the attack source is the same skill the player is demonstrating. Fully skill-driven, removes RNG complaints. | Med | The core hook. Tune charge rate vs. hull damage. |
| Beat-quantized launch and arrival | Attacks feel musical and become readable. Rare in Tetris-style attack games. | Med | Quantize to next beat of the chart tempo map. Needs the same tempo map on all clients. |
| Return to Sender (reflect via perfect warhead notes) | Active defense; gives the victim a skill-based comeback instead of passive suffering. | High | Warhead notes injected into target chart; success reported as event. Needs careful event ordering. |
| Five distinct payloads (Ghost, Lane Flip, Ink, Pressure, Depth Charge) | Variety of readable disruptions. | Med each | Ghost/Flip/Pressure are cheap. Ink is shader. Depth Charge needs chart-derived extra notes (Med-High). Ship in order of cost. |
| Wreck ghosts that keep attacking weakly | Nobody sits out, eliminated friends stay social. | Med | Cap debris strength so it cannot snowball. |
| Sonar CRT theme, depth as score | Coherent identity, theme is mechanic. | Med | Visual polish can come last. |
| Targeting modes (leader / cycle / attacker / random) | Tetris 99 depth. See below. | Low-Med | Ship a subset. |
| Local judgment, networked events (cheat-resistant by trust, lag-immune) | Timing fairness regardless of ping. | Med | Architectural differentiator; felt as "tight". |
| Training payloads in Solo Dive | Practice countering attacks alone. | Low | Reuses payload code. Strong dev/test tool too. |
| Bundled starter tracks | Works out of the box. | Med | Royalty-free/original, with handmade charts. |

### Lessons from Guitar Hero III Battle Mode (fairness)

GH3 Battle Mode: players earn power-ups by hitting star-power phrases; power-ups are then used against the opponent. Recalled attacks include Difficulty Up, Lefty Flip, Double Notes, Broken String (mash to repair), Amp Overload, Whammy Pedal, Steal Amp, and Death Drain (a kill-shot at the end of the match that drains the opponent's life meter). LOW-MEDIUM confidence on the exact list; verify before citing in design docs.

Known fairness criticisms and implications for UNDERTOW:

| GH3 issue | Why it felt bad | UNDERTOW response |
|-----------|-----------------|-------------------|
| Random power-up from a fixed phrase, with no player choice | Luck decided matches | Attacks come from streaks, not RNG. Payload choice should be deterministic or visibly selectable, not random loot. |
| Instant, no-telegraph effects (Difficulty Up flipped the chart mid-phrase) | Unreadable, no reaction time | Beat-quantized arrival, warning cue, fixed duration of a few bars. |
| Mash-to-fix attacks (Broken String) and Death Drain | Rewarded button mashing, or ended a match from nothing (Death Drain kill at 0 life swings) | No mash-to-clear. No instant-kill. Hull damage from payloads only through missed/ghost notes. |
| Hard attacks stacking on a player already losing | Snowballing, a trailing player gets dogpiled | Cap concurrent payloads per target, add a short immunity window after being hit, cap total incoming. |
| Skill gap amplified by attacks (strong players unaffected, weak crushed) | Mismatch is unfun | Payload severity should scale gently, not with player skill. Keep Depth Charge density bounded. Consider optional handicap (hull or tube rate) for mixed-skill friend groups. |
| Chart-specific attack unreadability (Difficulty Up on a fast section) | Same attack was lethal on some songs, trivial on others | Compute payload strength relative to local chart density at arrival time and cap it. |

### Lessons from Tetris 99 targeting

Tetris 99 targeting modes: Random, Attackers (those targeting you), K.O.s (nearly eliminated players), Badges (players holding most badges). Players can also pick a specific opponent with stick/touch. Default is random in the older versions. MEDIUM confidence.

| Mode | Fit for 2-4 players | Recommendation |
|------|--------------------|----------------|
| Manual cycle (pick a specific rival) | Great: at 4 players it is a simple decision | Ship in v1. Tab cycles. |
| Leader / highest depth | Natural "anti-snowball" default | Ship in v1 as the default. |
| Attackers (whoever targets me) | Retaliation mechanic, simple to implement | Ship in v1 as a toggle, cheap and fun for grudges. |
| Lowest hull / "K.O." | Encourages finishing off, causes dogpiling | Optional, defer. |
| Random | Pointless with 3 opponents | Skip. |
| Badges | Needs an elimination-reward economy | Skip. |

Also relevant from Tetris 99 and Puyo: attacks should be offsettable (Puyo "offsetting" cancels incoming garbage with your own chain). UNDERTOW's Return to Sender is the analogue; consider also letting a full tube absorb or shorten an incoming payload (decide in design, not v1).

## Anti-Features

Deliberately NOT building for a friends-only 2-4 player game.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Public matchmaking, ranked/ELO, accounts, leaderboards | Out of scope; huge infra and anti-cheat burden | Join-by-code lobbies; session results only |
| Anti-cheat / server-authoritative judgment | Friends; cost is large | Trust clients, validate only for crashes/desync sanity |
| Dedicated servers | No budget | Peer-hosted with relay/VPN decision |
| Random power-up pickups (GH3 star-phrase loot) | RNG decides matches, contradicts "your streak is a torpedo" | Deterministic streak-charged torpedoes |
| Instant-kill or mash-to-clear attacks | Feels unfair and teaches button mashing | Skill-readable payloads only |
| Strum bar / strum key and HOPO/tap mechanics | Needs plastic guitar semantics; makes keyboard play awkward | Flatten HOPO/tap to normal notes at import |
| Plastic guitar / drum / mic instrument support | Hardware-specific work | Keyboard + gamepad only |
| Online pause | One player pausing stalls three others and is exploitable | Disconnect-safe no-pause; solo mode has pause |
| Song/chart editor | Scope; import covers content | Import only |
| In-game store, unlocks, cosmetics economy, campaign/story, careers | Scope; this is about friends | Unlock nothing, everything available |
| Syncing note judgment over the network / rollback netcode | Wrong problem for rhythm; adds lag to timing | Local judgment, networked events |
| Voice/text chat | Friends already use Discord | None |
| Bundled copyrighted songs | Legal | Imports plus royalty-free |
| Per-song online chart download/browser | Scope and legal | Player drops files in a folder |
| Star power / overdrive as separate system | Overlaps with torpedo tube and adds a second resource | Use only the torpedo meter |
| Many gameplay modes at launch (2v2 etc.) | Scope creep | Dive FFA first, Wolfpack later |
| Auto-charting (v1) | Quality risk, and imports cover content | Later milestone |

## Feature Dependencies

```
Audio clock + latency compensation -> Timing windows -> Hit feedback -> Combo/streak -> Torpedo tube
Chart parser (.chart/.mid) -> Lane mapping (5 fret -> 4 lane, HOPO flatten) -> Playable chart
Playable chart + audio clock -> Sustains/chords -> Song select -> Solo Dive/Practice
Calibration -> (required before) any competitive session is considered fair
Tempo map (shared) -> Beat-quantized launch/arrival -> Payload telegraph
Lobby + song hash check + clock sync + scheduled start -> Synchronized match
Event replication (song-time-stamped) -> Hull/elimination broadcast -> Rival panels -> Targeting
Torpedo tube -> Fire + Target select -> Payload spawn on target chart
Payloads (Ghost, Flip, Pressure first; Ink, Depth Charge later) -> Return to Sender (needs Ghost/warhead note type)
Elimination -> Wreck ghosts -> Results screen
Hull system -> Elimination -> Winner determination
Solo training payloads -> used to test payloads before netcode
Rebinding + gamepad -> Settings persistence (per-player profile)
```

Key ordering insight: payloads, targeting and tube can be built and tuned entirely in single-player (with a fake "rival" injecting events) before netcode exists. That de-risks the project.

## MVP Recommendation

Prioritize (in order):

1. Solo playable highway: audio-clock timing, 3 timing tiers, hit feedback, combo, hull, sustains/chords, calibration, rebinding, pause. (Table stakes core.)
2. Chart import with 5-to-4 lane mapping and a song select screen, plus 1-2 bundled tracks.
3. Torpedo tube, Fire, target cycle, and three cheap payloads (Ghost Notes, Lane Flip, Pressure Crack) tested in solo with training injections. Beat-quantized arrival and telegraph from the start.
4. Online lobby, song-hash check, synced start, event replication, elimination, results screen (Dive FFA).
5. One differentiator beyond core: Return to Sender and wreck ghosts, then Ink Cloud and Depth Charge.

Defer:
- Wolfpack 2v2: scope.
- Auto-charting: quality risk.
- Targeting modes beyond manual and leader (plus Attackers toggle): low value with 3 opponents.
- Handicap system: add only if friend skill gaps prove painful in playtests.
- Sonar CRT polish and full audio juice: after mechanics feel good, but keep a minimal readable look from the start because readability affects fairness.

## Open Questions for Later Phases

- Exact timing window values and streak definition (what counts as "good" for charging): LOW confidence, needs playtest tuning.
- 5-fret to 4-lane mapping approach (drop a fret vs. merge vs. use Expert-only charts): needs a dedicated research task.
- Tie-break and ghost-attack caps: design decision.
- Stacking and immunity rules for incoming payloads: design decision informed by GH3 lessons above.

## Sources

- Training knowledge of Guitar Hero III Battle Mode, Clone Hero, YARG, osu!mania, Rock Band, Tetris 99, Puyo Puyo (not re-verified online in this pass; MEDIUM/LOW as marked).
- .planning/PROJECT.md (project scope, constraints, out-of-scope items).
- Recommended verification before requirements lock: Clone Hero and YARG docs for chart format and timing windows, Tetris 99 targeting mode documentation, GH3 Battle Mode attack list on the Guitar Hero wiki.
