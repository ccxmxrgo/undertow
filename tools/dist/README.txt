UNDERTOW - early playtest build (v0.7.0, 2026-10-20)
====================================================

You're a submarine sinking into a deep-sea trench. This build adds online
play with friends: up to 4 subs, each on their own PC, in the same song,
firing torpedoes at each other. Versus Bots and solo play are still here.
To play online, read ONLINE_SETUP.md (next to this file) first.

v0.5 gives every screen a new look: a deep-sea submarine cockpit looking
through a neon sonar into the abyss. v0.5.1 makes the hit windows wider
(easier to get PERFECT and GOOD), adds a calmer background and makes the
controller work in every menu (see WHAT'S NEW IN v0.5.1).
v0.5.2 adds Guitar Hero / Clone Hero songs that come with a notes.mid chart
(see WHAT'S NEW IN v0.5.2).
v0.5.3 makes the note highway easier to read (see WHAT'S NEW IN v0.5.3).
v0.5.4 adds Chart a Song: turn an audio file you own into a playable chart
(see WHAT'S NEW IN v0.5.4).
v0.6.0 adds Versus Bots: race up to 3 bot subs down the trench, with killstreak
torpedoes (see WHAT'S NEW IN v0.6.0).
v0.7.0 adds Play Online: 2 to 4 friends on their own PCs, over Tailscale or
LAN (see the v0.7.0 notes below and ONLINE_SETUP.md).
This build is for friends only: please don't share it further.

Want to help test? Open TESTER-CHECKLIST.txt (next to this file). It is a
short list of things to try, with boxes to tick, and says how to report a bug.


HOW TO RUN
----------
1. Unzip the whole folder somewhere (e.g. your Desktop).
2. Double-click UNDERTOW.exe. The game opens fullscreen. The whole game is
   in that one file.
3. Windows may say "Windows protected your PC" because the game isn't
   signed. Click "More info", then "Run anyway".
4. On first launch the CALIBRATE SONAR wizard opens. Please do it! It
   measures your speaker and screen delay so hits line up. Use WIRED
   headphones or speakers if you can, because Bluetooth adds a lot of delay.


CONTROLS
--------
  Lanes ............ 1  2  3  4     (number keys on the top row;
                                     gamepad: LB  LT  RT  RB)
  Skip intro ....... Space          (gamepad: A)
  Pause ............ Esc            (gamepad: Start)
  Fullscreen ....... F11            (switches fullscreen / window)
  Debug overlay .... F3             (shows timing numbers)
  Autoplay ......... F4             (watch the bot play the song perfectly)
  Fire reward ...... Space          (gamepad: A; versus and Solo Dive)
  Switch target .... H              (gamepad: Y; versus)
  Fire and Switch target can be rebound in Settings > Controls.

Menus with a gamepad (every screen: menu, song select, results, pause,
Settings, calibration, dialogs):
  Move ............. D-pad or left stick
  Confirm .......... A
  Back ............. B
  Pause ............ Start
  In SELECT SONG also: LB / RB jump a page, Left / Right change the
  difficulty, Y = sort, X = rescan library.
  Settings > Controls has a GAMEPAD column: rebind the lanes to any
  controller button or trigger there.

Space skips the intro straight to a short 3-2-1 count-in. Retry and the F4
autoplay restart play a quick version of the intro, so getting back in is
fast. Esc pauses at any time.

The game opens fullscreen. F11 switches to a window and back.
Settings > Display also has a Fullscreen switch and a Low effects switch.
Low effects simplifies the abyss (fewer rings and particles, no glitch);
notes and lanes stay fully bright.

Played v0.1? Your keys move to 1 2 3 4 automatically, unless you had
changed them yourself. Settings > Reset Controls always gives you 1 2 3 4.

Menu: "Start Dive" opens SELECT SONG, where you pick a song and a
difficulty. "Solo Dive (No-Fail)" does the same, but you can't sink, and can
add training torpedoes. "Versus Bots" sets up a match against bot subs. "Play Online" hosts or
joins a match with friends (see ONLINE_SETUP.md).
Settings lets you rebind keys, change scroll speed and volume, turn on
No-Fail and add Clone Hero song folders (see SONGS below).

SELECT SONG controls:
  Song ............. Up / Down      (1 / 2 also work while the search is
                                     empty; 3 / 4 jump a page)
  Difficulty ....... Left / Right
  Dive ............. Enter
  Search ........... just type (title or artist); Esc clears it
  Sort ............. F2
  Rescan Library ... F5
  Open Songs Folder  F6
  Back ............. Esc
Highlight a song for half a second to hear a preview.


WHAT'S NEW IN v0.7.0
--------------------
- Read ONLINE_SETUP.md (next to this file) first. It explains how to connect
  through home routers. Tailscale (free) is the recommended way; same Wi-Fi
  / LAN, ZeroTier and router port forwarding also work.
- Everyone needs v0.7.0. Play Online shows your VERSION at the bottom; a
  friend on another build gets DIFFERENT VERSIONS.
- Main menu > Play Online: set your name (friends see it), then Host Match,
  or type the host's address and Join Match. The host screen lists this
  PC's addresses; give friends the one marked TAILSCALE. Default port 47474.
- Up to 4 subs on separate PCs play the same song in sync (a shared DIVE IN
  3 / 2 / 1 countdown). Torpedoes fly between friends mid-song, with the
  same rewards and warnings as Versus Bots. Online, a torpedo flies 2 beats
  so the warning still comes in time over the internet (the host can pick
  1 BEAT LAN for same-room play).
- Lobby: everyone shows NAME, PING, SONG and READY. The host picks the
  song, difficulty and torpedo flight; friends press Ready Up; the host
  presses Start Match. A friend without the song shows MISSING (copy the
  song folder to them, or pick another song).
- Leaving mid-match (Esc > Leave Match) turns your sub into a wreck and
  the others play on. If the host leaves, the match ends for everyone
  (HOST LEFT).
- After the song every PC shows the same results. The host picks Back to
  Lobby for another round.
- The first time you host, Windows Firewall asks: click Allow (Private
  networks).
- Settings > ONLINE: Player name and Online port.


WHAT'S NEW IN v0.6.0
--------------------
- Main menu > Versus Bots: you against 1 to 3 bot subs (Rookie, Regular or
  Veteran) on the same song. Last hull standing wins; if several survive,
  the deepest dive wins. Versus matches do not set records.
- Unbroken Perfects fill your torpedo tube. A full tube loads a random
  reward: 6 disruptors (Crossed Wires, Ghost Notes, Ink Cloud, Pressure
  Crack, Sonar Jam, Depth Charge) and 3 buffs (Decoy Flare, Ballast Patch,
  Overclock). Space fires it; H switches target (AUTO, each rival,
  ATTACKERS).
- A torpedo aimed at you is announced a beat before it lands (red INCOMING
  box, red screen edges, a ping). Hit the red-ringed notes Perfect to send
  it back.
- Two torpedoes fired at each other on the same beat collide. The leader
  carries a bounty. Guitar solos become Solo Duels. A killfeed (top right)
  shows what happened, and the results show medals.
- If your hull breaks in versus you keep playing as a wreck and can charge
  small debris attacks.
- Practice Dive is now Solo Dive. In Song Select press F3 (or the gamepad
  triggers) to pick training torpedoes that a drone fires at you.
- Hull repair is slower: each Perfect now repairs a quarter of what it used
  to, so a Miss takes about 32 Perfects to undo.
- Strong players earn about 3 rewards a song on Expert; if you rarely earn
  one, tell us (it is tunable).


WHAT'S NEW IN v0.5.4
--------------------
- Main menu > Chart a Song turns an MP3, OGG, WAV or FLAC file you own
  into a song you can play, with Easy to Expert charts. It splits the
  music into instruments and charts one of them (or Instrument Lanes:
  each lane is one instrument).
- The first time, the game offers a one-time download, the Autocharter
  pack: about 400 MB, about 1 GB on disk (have about 2 GB free while it
  installs), stored in %LOCALAPPDATA%\UNDERTOW\ac. Installing after the
  download takes about 1.5 minutes. You can remove it again on the Chart
  a Song screen.
- If the screen says the pack is not available yet, it has not been
  published yet: try again later. Everything else works without it.
- Charting a 4-minute song takes about 1 to 3 minutes on a typical gaming
  PC (on the developer's PC a 2-minute song took about 36 seconds, so a
  4-minute song about 1 minute); the first run after the download is
  slower. Your music never leaves your PC.
- Charted songs appear in Song Select like any other song (charter:
  UNDERTOW autochart). Use "Chart Another Instrument" to try a different
  instrument quickly (a few seconds, the split is reused).
- Antivirus programs may scan the pack during the first setup, which can
  make it slower.
- If charting fails, press "Show Details" and send us the log.txt it
  shows with your bug report.
- If it says to install the Microsoft Visual C++ Redistributable, install
  "Microsoft Visual C++ Redistributable (x64)" from microsoft.com (search
  for "vc_redist.x64.exe") and try again.


WHAT'S NEW IN v0.5.3
--------------------
- The download is now just one game file, UNDERTOW.exe (plus this README
  and the checklist).
- The far end of the highway is now much wider, so the four lanes stay
  apart all the way down and notes no longer pile up into one blob.
- Notes fade in at the far end instead of popping in as tiny specks, and
  far notes are already a readable size.
- Notes move at a steadier speed: they no longer race at the end (the
  speed change across the board is about 2.9 times instead of about 7.8
  times).
- Lines, glows and sweeps fade out toward the far end, so the far end is
  calmer.
- Timing is unchanged: a note is still exactly on the hit line when you
  should hit it, and the same number of beats is on screen at 1x.
- At 1x the notes now look slower near the hit line. If you liked it
  faster, raise Settings > Gameplay > Scroll speed.
- Everything from v0.5.2 still applies: songs with a notes.mid chart work
  the same way (see below).


WHAT'S NEW IN v0.5.2
--------------------
- Songs with a notes.mid chart now work (for example Guitar Hero 3 rips
  and most Clone Hero packs). Drop the folder into Songs and press Rescan
  Library (F5). All four difficulties, section names and solos work. The
  lead guitar part is used. If a song has none, the next guitar or bass
  part is used. With none at all it shows "No guitar part in .mid".
- Songs that showed "MIDI charts not supported yet" are read again
  automatically on the first scan (that scan can take a bit longer).
- If a folder has both notes.chart and notes.mid, notes.chart is used.
  Did you convert a song with Moonscraper earlier? You can delete that
  notes.chart to go back to the original notes.mid (optional).
- Sync: .mid songs are timed exactly like .chart songs (tested to within
  1 ms). If EVERY song feels a little early or late, re-run Settings >
  Calibration > Re-run Calibration (wired headphones help). If only one
  song is off, tell us the song and whether notes come early or late. Its
  song.ini "delay" (in ms, higher = notes later) can fix it.
- Still not supported: .opus audio (shows "Opus audio not supported") and
  drum-only or vocal-only charts.


WHAT'S NEW IN v0.5.1
--------------------
- Wider hit windows: PERFECT is now +-50 ms (was 35), GOOD is +-100 ms
  (was 70), and a press up to 130 ms early counts as a miss (was 100).
  Notes are drawn exactly on the hit line at the on-time moment (the
  triangle note sat 2 pixels too high, that is fixed).
- A new "Calm" background, on by default: still trench walls and a soft
  glow on the beat. Settings > Display > Background switches between Calm
  and Living (the v0.5 moving, pulsing trench). Please tell us which one
  you prefer.
- The controller now works in every menu: D-pad or left stick to move,
  A to confirm, B to go back, Start to pause (see CONTROLS). You can also
  rebind the lanes to controller buttons in Settings > Controls.

Running the game from the source code (not this zip)? After pulling new
code, run "godot --headless --path . --import" once (or open the project
in the Godot editor) before starting the game, otherwise new screens can
fail to open.


WHAT'S NEW IN v0.5
------------------
- A new look everywhere, one "abyssal cockpit" style on every screen.
- Title screen: an animated abyss (rocks, light shafts, drifting snow,
  a submarine with its searchlight) behind the UNDERTOW logo, with menu
  music, icons and a one-line description for each item, and a LAST DIVE
  card with your last song and best depth.
- Menu music: a bundled song plays quietly on the menus. Turn it off in
  Settings > Audio > Menu music. Menus also make soft blips when you move,
  confirm or go back (Settings > Audio > SFX sets their volume).
- Song select: album art (album.png / album.jpg in the song folder, or a
  generated cover), difficulty tiles with note count and a 1-5 intensity
  meter, and a visualizer that moves with the preview.
- The board: filled lanes, beat and bar lines, solid gem notes, pads that
  light up when you press, and hit explosions (big on PERFECT, small on GOOD,
  a red fizzle on MISS). The trench glows more as your multiplier grows, and
  the life on the walls pulses on the beat.
- A cockpit HUD: a multiplier ring around your streak, a depth gauge (with
  your best depth marked), a hull arc, a song progress bar with section
  names, and a live accuracy %.
- Results: a grade (S A B C D), accuracy, depth, max combo, PERFECT / GOOD /
  MISS bars and an early/late timing histogram, so you can see if you rush
  or drag. Buttons: Retry Dive, Song Select, Back to Menu.
- Pause, IMPLOSION, Settings, calibration and the intro are restyled, and
  screens change with a short sonar wipe.
- For weaker PCs: Settings > Display > Low effects (fewer particles, no glow,
  a simpler background; notes stay fully bright).
  Settings > Gameplay > Reduce motion stops the shake, parallax and other
  big movement.
- Accuracy now counts PERFECT as 100%, GOOD as 50% and MISS as 0%.

The questions we really need answered (see TESTER-CHECKLIST.txt):
  "Does it look like a finished game now? Is anything hard to read during
  play? Anything that feels too busy?"


WHAT'S NEW IN v0.4
------------------
- Three new bundled songs: "Sea Shanty 2", "HRT" and "INVISIBLE".
- The two original songs ("Synth Wave April 3, 2022" and "Space Synth
  Wave") are re-charted.
- All five charts are now made from the audio: every note sits on a sound
  you can hear (one instrument, usually the lead synth), and the lanes
  follow the tune: when the melody goes up, the notes move right; when it
  goes down, they move left. Easy, Medium and Hard are simpler versions of
  Expert, the way Clone Hero charts do it.
- Because the two original songs have new charts, their best scores start
  again from zero.
- Song previews in SELECT SONG now start in the middle of the song, not in
  the intro or the last seconds.

Bundled songs:
  1. Sea Shanty 2 - Ian Taylor / Jagex (Old School RuneScape)
  2. HRT - artist unknown
  3. INVISIBLE - Duran Duran
  4. Synth Wave April 3, 2022 - Pro Sensory
  5. Space Synth Wave - Pro Sensory

The one question we really need answered (see FEEDBACK below):
  "Is there a sound under every note? Does going right feel like going up?"
  Play each song on Expert and on Easy, and tell us the song, difficulty
  and time (e.g. "INVISIBLE, Easy, 1:20") of anything that feels off.


WHAT'S NEW IN v0.3
------------------
- Real songs! Two bundled tracks with Easy, Medium, Hard and Expert charts:
  "Synth Wave April 3, 2022" and "Space Synth Wave" (both have a solo).
- SELECT SONG screen: a list of every song with length, difficulties and
  your best depth, a detail panel, a short audio preview, search and sort.
- Play your own Clone Hero songs: drop them into the Songs folder (see
  SONGS below). Zips work too.
- Your best is saved per song AND per difficulty.
- The main menu has a new "Open Songs Folder" item.
- The old test song is still there as "Calibration Track" (marked TEST).


SONGS
-----
Where is the Songs folder?
  %APPDATA%\Godot\app_userdata\UNDERTOW\songs
  (for example C:\Users\<you>\AppData\Roaming\Godot\app_userdata\UNDERTOW\songs)
  You don't have to find it yourself: "Open Songs Folder" in the main menu
  or in SELECT SONG opens it, even before you have any songs. The path is
  also shown at the bottom right of SELECT SONG.

How to add songs:
  1. Get a Clone Hero song you own. A song is a folder with a notes.chart
     or notes.mid file, usually a song.ini, and the audio (song.ogg,
     song.mp3 or song.wav; split stems like guitar.ogg + drums.ogg also
     work).
  2. Drop the whole folder into the Songs folder. A .zip of the folder
     works too: just drop the .zip in, no need to unpack it.
  3. In SELECT SONG press "Rescan Library" (F5). The song shows up.
  Already have a Clone Hero songs folder? Settings > Library > Add Folder
  reads it where it is. Your files are never copied or changed.

An audio file without a chart (for example a bare .mp3) is listed as
"NEEDS A CHART". To play it, chart it first with Main menu > Chart a Song
(see WHAT'S NEW IN v0.5.4).

How 5-fret charts become 4 lanes (the same for every song):
  Green  = lane 1
  Red    = lane 2
  Yellow = lane 3
  Blue   = lane 4
  Orange = lane 4 too, merged with Blue (the longest sustain is kept)
  Open notes = lanes 2 and 3 together
  HOPO and tap markers are ignored (every note is a normal hit).
  All four difficulties are playable. Only lead guitar charts are used.

Not supported (shown greyed out with the reason, so you know why):
  - Opus audio ("Opus audio not supported"). Convert it to OGG Vorbis,
    MP3 or WAV.
  - .mid charts without a guitar part ("No guitar part in .mid").
  - Damaged .mid files ("Unreadable .mid"): download the song again.

Only add songs you own. This friends-only build bundles a few songs the
developer owns (see MUSIC CREDITS); please don't share it further.


MUSIC CREDITS
-------------
"Synth Wave April 3, 2022" and "Space Synth Wave" by Pro Sensory
(Alex McCulloch), released as CC0 (public domain), via OpenGameArt.org.
Thank you!
"Sea Shanty 2" from the Old School RuneScape soundtrack, by Ian Taylor /
Jagex. "INVISIBLE" by Duran Duran. "HRT", artist unknown. These three are
NOT free music: they are in this build for friends only, so please don't
share the build or the songs.
All charts were generated from the audio by UNDERTOW autochart.


WHAT'S NEW IN v0.2
------------------
- A whole new look. Every dive starts by putting the headset on: your
  room, the lenses close in around you, a CRT blink, LINK ESTABLISHED, and
  you drop into a neon abyss. Takes about 4 seconds; press Space to skip it.
- The board is now a trench: four glowing cables run straight from a far
  horizon down to a flat hit line at the bottom. Notes travel down the
  cables and all four lanes are hit on the same line.
- Clean screen edges and a minimal HUD: your streak sits left of the board,
  depth on the right, and a hull arc under the board turns red with
  HULL CRITICAL when you're about to sink.
- The abyss reacts to you: the crowd glows brighter on long streaks, dims
  when you miss, and the trench walls breathe on the beat.
- Keys are now 1 2 3 4, so you can play with one hand.
- Each lane has its own color and shape: cyan diamond, amber circle,
  magenta triangle, lime square.
- Notes only light up when you can actually hit them. Dim = too early,
  bright = hit it now.
- A big streak counter, with popups at 10, 25, 50 and 100 in a row.
- Your best score is saved and shown on the results screen. Practice,
  Autoplay and No-Fail dives never set a record.
- "Solo Dive (No-Fail)" in the main menu (called Practice Dive before v0.6.0).


FEEDBACK WE NEED (reply in Discord or on WhatsApp)
--------------------------------------------------
1. Did it launch? Any errors or crashes? (If it crashed, send us the file
   godot.log from %APPDATA%\Godot\app_userdata\UNDERTOW\logs. Paste that
   path into the Explorer address bar to open the folder.)
2. What audio offset did calibration give you? (shown as "+NN MS")
3. Do hits feel ON the beat, early or late? Does anything feel laggy?
4. Do PERFECT / GOOD / MISS feel fair? Too strict or too easy?
5. Can you tell the 4 note shapes apart quickly?
6. Keyboard or gamepad? Do keys 1 2 3 4 feel OK? Did every press register?
7. What headphones/speakers did you use (wired / Bluetooth / USB)?
8. Anything confusing, ugly or annoying?
9. Do notes look ready at the right moment (do they light up when you can
   hit them)?
10. Did the intro feel cool or too long? Did you use Space to skip it?
11. Can you read the notes at your scroll speed? Which speed did you use?
12. Does the new look feel like UNDERTOW and not like a guitar game?
13. Did the frame rate stay smooth?
14. For each bundled song, on Expert and on Easy: is there a sound under
    every note? Does going right feel like going up in the music? Tell us
    the song, difficulty and time of anything that feels off.
15. Did your own Clone Hero songs import? Name any song that didn't, and
    what SELECT SONG said about it.
16. Was it clear where the Songs folder is and how to add songs?

Thanks for diving!
