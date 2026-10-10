# UNDERTOW

## What This Is

UNDERTOW is a competitive online rhythm game made in Godot, inspired by Guitar Hero, for playing with friends. Each player commands a submarine sinking into a deep-sea trench. Their note highway is the sub's sonar screen. Playing well is also how you attack: perfect streaks charge torpedoes that land on rivals' sonar as disruptive notes. Up to four friends play the same song at once, each on their own PC, until only one hull is left intact.

**Tagline:** "Your streak is a torpedo."

## Core Value

Hitting notes must feel tight and fair on each player's own machine, while torpedoes reach rivals over the network fast enough that a friend's perfect streak is felt *inside the same song*. If torpedoes don't land mid-song, it's just four solo games running side by side. If timing feels mushy, it's not a rhythm game.

## Game Design

### Fantasy & Setting

- **The Hadal Trench.** Rival salvage crews race their subs into a trench where the water itself carries music. Each song is a dive. The deeper you get, the faster and denser the "currents" (notes) become.
- **The sonar screen is the highway.** The interface is a phosphor-green CRT sonar scope. Notes are sonar returns that slide down 4 frequency-band lanes toward the hull line (the strike line). The theme is built into how the game looks and plays, not painted over a normal fretboard.
- **Hull = health.** Misses crack the hull. Hull at zero means implosion, and you're out. Last sub intact wins. If the song ends with several subs still alive, the deepest one wins (depth = score).
- **Wreck ghosts.** Eliminated players keep playing as the wreck. Their hits charge weak "debris" attacks, so nobody sits out after losing.

### The Twist: Offensive Rhythm

- **Torpedo charge:** consecutive good hits fill a torpedo tube meter. A full tube = one torpedo.
- **Fire:** a dedicated button launches it at a target. Targeting can cycle between rivals or default to the current leader. Launch and arrival snap to the next beat, so attacks feel musical.
- **Torpedo payloads** (land on the target's highway for a few bars):
  - **Ghost Notes:** fake returns mixed in with real ones. Hitting one costs hull. They look slightly different from real notes so a sharp eye can tell them apart.
  - **Lane Flip:** the lane order is mirrored.
  - **Ink Cloud / Sonar Fog:** the lower part of the highway goes dark, so notes appear late.
  - **Pressure Crack:** sudden scroll-speed spike.
  - **Depth Charge:** a dense burst of extra notes, built from the song's own rhythm.
- **Return to Sender:** some torpedoes arrive as marked "warhead" notes. Hitting all of them perfectly reflects the torpedo back at the person who fired it.
- **Counterplay, not punishment:** every payload can be read and survived by a skilled player. It should never be a random loss.

### Modes (v1 focus: Free-for-all)

- **Dive (FFA):** 2-4 players, last hull standing.
- **Solo Dive / Practice:** play songs alone with optional training payloads. Also used to test chart import and calibration.
- (Later) **Wolfpack 2v2:** shared crew hull, torpedoes pooled per team.

### Music & Charts

- **No song library to author by hand.** Players bring their own music:
  - Import existing community charts in the Clone Hero / Guitar Hero fan formats (`.chart` / `.mid` + audio). A large existing ecosystem the friend group may already have.
  - A small set of bundled royalty-free / original tracks with handmade charts so the game works out of the box.
- Every player in a match needs the same song locally. The lobby checks this with a song hash and shows who is missing it.
- (Later) Auto-charting from any audio file using onset/beat detection.

### Look & Sound

- **Core fantasy (user, 2026-10-08):** *put on the goggles and you're a rockstar in another world* (like Ready Player One). The goggles jack you into a virtual world, and "diving" means diving into it: a neon abyss arena where you perform. Torpedoes, hull and depth are that world's rules. Each dive opens with the goggles sliding on and a CRT-style blink as the world turns on.
- **Braindance means the FEEL** (the immersive, sensory "you're inside it" quality), not a cluttered UI. Keep the screen edges clean and put the style on the board itself (curved neon lines on a 3D road into a glowing horizon). It must NOT feel like Guitar Hero.
- **Art direction (user, 2026-10-07/08):** cyberpunk, "like you're inside the goggles", **inspired by the Braindance aesthetic from Cyberpunk 2077**: a recording-overlay frame with a red-accented, glitchy lens, a timeline scrubber (real song progress), layer tags and chromatic split. Inspiration only, with no CDPR assets or names. The sonar highway is seen through a diver's visor HUD, with neon lane colors (cyan, amber, magenta, lime) over sonar-green chrome.

- **Visual:** CRT phosphor sonar UI (scanlines, bloom, sweep-arm afterglow), black water background with bioluminescent creatures pulsing on the beat, small "periscope" panels showing rivals' highways and hull states.
- **Audio:** sonar pings on downbeats, hull creaks that get worse as hull drops, torpedo launches quantized to the beat, muffled underwater filter on the song as damage grows.
- **Juice:** screen shake on impact, the rival panel flashes when you are targeted, an implosion animation when a player is eliminated.

### Controls

- 4 lanes + Fire + Target-cycle. Keyboard default (e.g., D F J K, Space, Tab), plus gamepad. Rebindable.
- Per-player audio/visual latency calibration (essential for fairness across different PCs).

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Player can play a song on a 4-lane sonar highway with accurate, calibrated hit timing
- [ ] Hull/health system with misses causing damage and elimination at zero
- [ ] Streaks charge torpedoes; player can fire them at a chosen rival
- [ ] Five torpedo payloads (Ghost Notes, Lane Flip, Ink Cloud, Pressure Crack, Depth Charge) affect the target's highway
- [ ] Return-to-Sender reflection mechanic
- [ ] 2-4 friends can join an online lobby from their own PCs and start the same song in sync
- [ ] Torpedo/hull/score events replicate between players mid-song with beat-quantized arrival
- [ ] Players can import Clone Hero-style charts (`.chart` / `.mid` + audio)
- [ ] Bundled starter songs so the game works with no imports
- [ ] Instrument extraction tool (research first): separate a song the player owns into stems, then chart one instrument, or give each lane its own instrument ("instrument lanes")
- [ ] Per-player latency calibration and rebindable keyboard/gamepad controls
- [ ] Sonar CRT visual identity and underwater audio feedback
- [ ] Wreck-ghost play for eliminated players
- [ ] Results screen (winner, depth, torpedoes landed/reflected)

### Out of Scope

- Plastic guitar controllers / real instruments: keyboard + gamepad only for v1. Instrument support adds hardware-specific input work. Revisit if the group owns them.
- Public matchmaking, ranked play, accounts: this is for one friend group. Invite/join-by-code is enough.
- Shipping copyrighted songs in public builds: players import their own. Bundled tracks in public builds must be royalty-free or original. Override (2026-10-08/09, user): the friends-only build bundles the user's own songs (HRT, Sea Shanty 2, Duran Duran INVISIBLE); licences are not a concern for this private build (02.1-NOTES.md, Phase 2.1 D-13).
- Mobile/console builds: target the desktop PCs the friends use.
- Song/chart editor: importing existing charts covers content. An editor is a later milestone at most.
- Story/campaign mode: the game is about friends playing against each other.

## Context

- Built for a specific friend group playing from separate PCs over the internet, not couch co-op. This was an explicit choice (online netcode) made during setup.
- Online play is the main technical risk. Rhythm judgment must stay **local** (each client judges its own hits against its own audio clock). Only game events (torpedoes, hull damage, eliminations, scores) go over the network, stamped with song time. Song start must be synchronized via clock sync plus a scheduled start time.
- Friends' PCs will be behind home routers. NAT traversal / relay (e.g., Steam networking via GodotSteam, a relay, or a VPN like Tailscale/ZeroTier) needs a decision during research.
- Godot is not currently installed on the developer's PATH. Setup must cover installing Godot 4.x.
- Concept chosen from four pitched options (MIMIC, ECHO, UNDERTOW, ONE ORGAN). The others are kept as possible future modes.

## Constraints

- **Engine**: Godot 4.x (stable), GDScript preferred. This was the user's request.
- **Platform**: Windows desktop first. The developer is on Windows 11, and friends are presumed to be on PCs.
- **Networking**: 2-4 players online, peer-hosted (one friend hosts). No paid dedicated servers expected.
- **Timing**: hit judgment accurate to the ~±50ms window range, with audio clock as the source of truth (not frame time).
- **Content/legal**: public builds: no copyrighted music bundled; content comes from imports. Override (2026-10-08/09, user): the friends-only build bundles the user's own songs (HRT, Sea Shanty 2, Duran Duran INVISIBLE); licences are not a concern for this private build (02.1-NOTES.md, Phase 2.1 D-13).
- **Team**: solo/hobby developer with AI assistance. Scope must stay small enough to actually play with friends soon.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| UNDERTOW concept (offensive rhythm / torpedo versus) | Picked by user from 4 non-cliché pitches. Rhythm skill becomes aggression between friends. | — Pending |
| Online netcode (not couch) | User plays with friends on separate PCs | — Pending |
| Local hit judgment, networked events only | Network latency must never affect timing fairness | — Pending |
| Clone Hero chart import instead of authoring charts | Huge existing chart ecosystem, avoids content bottleneck and copyright issues | — Pending |
| Keyboard/gamepad only | Simplest input path, everyone already owns one | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-07 after initialization*
