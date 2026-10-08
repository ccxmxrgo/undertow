# Research: How to Make UNDERTOW Better

**Researched:** 2026-10-08
**Status:** Proposals only. Nothing here is locked. Each idea needs the user's OK before it moves into a phase SPEC or REQUIREMENTS.md.
**Inputs:** PROJECT.md, REQUIREMENTS.md, research/FEATURES.md, 01.1 friend feedback, 01.2 playtest gaps (G-1 curved board, G-2 goggles), phases/03-offline-versus/03-SPEC.md, plus a web pass (sources at the end).

## TL;DR: the 8 strongest ideas

| # | Idea | Why (evidence) | Phase | Cost |
|---|------|----------------|-------|------|
| 1 | **Per-player difficulty in versus**, with depth scored as % of that chart's max | Mixed-skill friend groups. Handicaps balance outcomes without reducing enjoyment, most of all for weaker players [Abertay]. GH Face-Off and Clone Hero versus let players pick different difficulties [GH, CH wiki]. 03-SPEC already scales reward thresholds to each chart's note count, so rewards already work per difficulty. | 3 (match rules) + 4 (lobby) | Low–Med |
| 2 | **"Dogpile" defence**: when 2+ rivals target you, your reward meter fills faster | Tetris 99 boosts the attack of a player being targeted by several opponents, so being focused isn't pure punishment [tetris.wiki]. Turns the planned "Dogpiled" medal into a real mechanic. | 3 | Low |
| 3 | **Endgame escalation**: as subs implode, disruptor travel shortens and the bounty refund grows | Tetris 99 shortens the garbage delay as players are knocked out, so pressure rises at the end [tetris.wiki]. Stops the last two players from cruising to the song's end. | 3 | Low |
| 4 | **Spend a held reward to cancel an incoming disruptor** (offset) | Puyo offsetting and the Tetris Effect Zone give the player an active, timed defence [FEATURES.md, Tetris Effect guide]. FEATURES.md already flagged "let a full tube absorb an incoming payload" as undecided. Gives the one-slot hold a real decision: attack now or keep it as a shield. | 3 | Low–Med |
| 5 | **Attacker gets something for landing a hit**, beyond the bounty | Fortnite Festival Battle Stage, the closest shipped game to UNDERTOW, made sending an attack also help the sender's own score [Epic help]. Small depth bonus per landed disruptor. | 3 | Low |
| 6 | **Never shake or move the board during play**; put impact juice around it | Players report that a shaking highway makes fast sections unreadable [itch.io]. **This conflicts with the planned Phase 5 "screen shake on impact" (AV-03)** and with 01.2 G-1 readability. Shake the visor rim, room or HUD, never the lanes or hit line. | 5 (amend AV-03) | Low |
| 7 | **Hit-window visual + hitsounds option** | Clone Hero can draw the hit window around the strikeline [CH wiki]. Missing hitsounds make correct hits feel wrong [itch.io]. Helps the 01.1 "highlighted but not ready" complaint and the 01.2 "curved lines are harder to hit" gap. | 1.2 follow-up or 5 | Low |
| 8 | **Section practice with slow-down in Solo Dive** | Clone Hero practice mode picks sections and changes speed during play [CH wiki]. Friends learn the hard part of a song before a versus night. Charts already contain section names. | 2 or 3 (MATCH-06) | Med |

## 1. What the closest shipped game teaches us

**Fortnite Festival Battle Stage** (2024 – April 2026) was a 16-player rhythm battle royale with sabotage attacks, which is very close to UNDERTOW [Wikipedia, Epic help]:
- Attacks were fired from Overdrive. Holding more Overdrive made the attack last longer.
- Sending an attack also helped your own score.
- Everyone played the same song but chose their own part and difficulty.
- The lowest scorers were eliminated after each song, over up to 4 songs.
- **It was removed on 2026-04-16 for low engagement** ("failed to attract a sustainable player base") [PocketGamer.biz, Epic help]. No source blames the attack design. The likely lesson: strangers in matchmaking didn't stick around. UNDERTOW's friends-only scope avoids that problem, and it makes social features (killfeed, medals, rematch) count for more than balance perfection.

Ideas to borrow:
- **Attack strength scales with what you invest.** Possible variant: firing a reward while your streak is still going (above 2× threshold) adds +1 bar of duration. Optional; keep it simple at first.
- **A multi-song set.** A "Setlist" match: 3 songs, with hull carried over between songs (or partly repaired), and the deepest total wins. It gives a friend night structure without new systems.

## 2. Comebacks and anti-snowball (Tetris 99, Tetris Effect, Puyo)

Tetris 99 [tetris.wiki, Siliconera]:
- Incoming garbage waits in a visible queue and can be cancelled by your own clears.
- **The delay shrinks as players are knocked out**, so the end gets tense (idea 3).
- **Being targeted by several players boosts your attack** (idea 2).
- Hard caps on queued and sent garbage stop any single blow from deciding a match. UNDERTOW already has this through one active disruptor plus the immunity window (TORP-05).

Tetris Effect Zone [Tetris Effect guide, GamesBeat]:
- One meter, two uses: an emergency escape when you're in trouble, or a huge attack when you're safe. **That timing choice is the fun.** Idea 4 gives UNDERTOW the same choice: spend the held reward to cancel an incoming disruptor during its 1-beat warning, or keep it to attack.

Mixed-skill fairness [Abertay, GH]:
- Handicaps balance outcomes and don't reduce fun, most of all for weaker players.
- Guitar Hero's Face-Off let a player on a lower difficulty win, because their notes were worth more.
- **For UNDERTOW:** let each player pick their own difficulty. Score depth as % of that chart's max possible score, so Easy and Expert players compete fairly. Hull damage per Miss stays the same. This pulls MODE-03 (handicap, currently v2) forward in a cheap form.

## 3. Readability and game feel

Readability is a fairness issue for UNDERTOW (Core Value), and the 01.2 playtest just failed on it (G-1).
- **Stable board.** Shaking the highway makes dense sections hard to read [itch.io]. Amend AV-03: impact shake goes on the visor rim, trench walls and HUD, never on lanes, notes or the hit line. Also add it to the low-effects toggle (AV-05).
- **Feedback on the note itself, not only text.** Players asked for visual feedback on the notes, not just judgment text [itch.io]. Perfect/Good bursts on the receptor, with early/late shown as a small tick left or right of the receptor (doubles as calibration help, as FEATURES.md notes).
- **Hitsounds option** [itch.io]. A soft per-lane click on hit, off by default, volume in settings. Helps on Bluetooth or high-latency audio, where the song alone feels mushy.
- **Hit-window overlay** (off by default), like Clone Hero's visual hit window [CH wiki]. Draws the ±70 ms band on each lane. Useful right now for tuning the 01.2 flat hit line.
- **Teach cues inside the game.** Unexplained cues break flow even when timing is perfect [Pixel Poppers]. Each disruptor's first appearance in a session should show a one-line caption with its icon ("CROSSED WIRES: follow the colours"). Solo Dive training (MATCH-06) can show all 9.
- **Map hit detection to exactly what the player sees** [akitsune.dev]. 01.2 G-1 acceptance 3 (note centre on the hit point at judge time) already covers this. Keep it as a permanent regression test.

## 4. More multiplayer modes (later)

Both use the existing systems and need no new netcode beyond Phase 4:
- **Sonar Duel (2 players):** Guitar Hero Face-Off and Rock Band Tug of War split a song into alternating sections. Each player plays only their turn, and the crowd meter swings with performance [GH, Rock Band]. In UNDERTOW, a "pressure gauge" swings between the two subs. A lopsided gauge cracks the losing hull.
- **Setlist** (section 1): 3 songs in a row, hull carried over.
- These sit next to Wolfpack 2v2 (MODE-01) and should be considered for v2, not v1.

## 5. Friend-night flow (no strong sources, design judgement)

No solid research was found on rematch flow [search came back empty], so these are judgement calls:
- **One-button rematch** on the results screen. Everyone presses Ready on the results screen and the same song restarts, so no trip back through the lobby.
- **Song vote in the lobby.** Each player suggests one song from the shared library (hash match, NET-02), and the game picks among them at random. Stops the host from always choosing.
- **Session scoreboard.** Wins and medals added up across the evening, cleared when the lobby closes (no accounts, in line with the anti-features list).

## Conflicts and risks found

1. **AV-03 screen shake vs readability.** Phase 5 plans "screen shake on impact". Research and 01.2 G-1 both say the board must stay still. Recommendation: amend AV-03 before Phase 5 is planned.
2. **"Random power-up pickups" is still listed as Out of Scope in REQUIREMENTS.md and as an anti-feature in FEATURES.md**, but 03-SPEC made rewards random (user decision, 2026-10-08). The next GSD transition should move that row, or discuss-phase may flag a contradiction.
3. **Fortnite Battle Stage was shut down.** Not a reason to change course: it failed to keep strangers in matchmaking, and UNDERTOW is for one friend group. It does mean social features (killfeed, medals, rematch, session scoreboard) deserve priority over extra content.

## Suggested next step

Ask the user which ideas to adopt. Adopted ideas go into:
- `phases/03-offline-versus/03-SPEC.md` (ideas 1–5)
- `REQUIREMENTS.md` (amend AV-03 for idea 6; ideas 7–8 as new requirements)
- Sections 4–5 as v2 candidates.

## Sources

- Fortnite Festival (Wikipedia): https://en.wikipedia.org/wiki/Fortnite_Festival
- What is Fortnite Festival Battle Stage? (Epic help): https://www.epicgames.com/help/en-US/fortnite-festival-c-202300000001635/c-Trending_0/what-is-fortnite-festival-battle-stage-a202300000010265
- Why are Rocket Racing, Ballistic, and Festival Battle Stage being removed? (Epic help): https://www.epicgames.com/help/fortnite-ballistic-c-202300000001637/gameplay-c-202300000001726/why-are-rocket-racing-ballistic-and-festival-battle-stage-being-removed-from-fortnite-a202300000083621
- Epic to retire three Fortnite modes (PocketGamer.biz): https://pocketgamer.biz/epic-games-to-retire-three-fortnite-modes-after-failing-to-attract-and-retain-players/
- Tetris 99 (tetris.wiki): https://tetris.wiki/Tetris_99
- Choose your targets in Tetris 99 (Siliconera): https://www.siliconera.com/always-remember-to-choose-your-targets-in-tetris-99/
- Tetris Effect Zone guide: https://gamertagmythras.com/blog/tetris/tetris-effect-zone-guide
- Tetris Effect: Connected multiplayer (GamesBeat): https://gamesbeat.com/tetris-effect-connected-offers-up-impressive-multiplayer-variety/
- Towards handicapping for online competitive games (Abertay): https://rke.abertay.ac.uk/en/publications/towards-handicapping-for-online-competitive-video-games-a-taxonom/
- Local multiplayer design and skill (PocketGamer.biz): https://www.pocketgamer.biz/rethinking-design-monetisation-and-skill-for-successful-local-multiplayer-gaming
- Clone Hero manual, How to play: https://wiki.clonehero.net/books/clone-hero-manual/page/how-to-play/revisions/919
- Clone Hero dictionary (note speed, hit window): https://wiki.clonehero.net/books/general-info/page/dictionary
- Guitar Hero III (Giant Bomb): https://www.giantbomb.com/games/3030-4031/
- Guitar Hero II (Giant Bomb): https://www.giantbomb.com/games/3030-14916/
- Rock Band (Giant Bomb): https://giantbomb.com/wiki/Games/Rock_Band
- Rhythm and Readability (Pixel Poppers): https://pixelpoppers.com/2019/06/rhythm-and-readability/
- How to design a rhythm game (Bugnet): https://bugnet.io/blog/how-to-design-a-rhythm-game
- Player feedback on highway shake and hitsounds (itch.io): https://itch.io/post/12506161 , https://itch.io/post/13875842 , https://itch.io/post/9208674
- Hit mapping to the visible play area (akitsune.dev): https://akitsune.dev/projects/wand
- Seven Years in Alpha: Thumper postmortem (GDC Vault): https://gdcvault.com/play/1024291/Seven-Years-in-Alpha-Thumper
