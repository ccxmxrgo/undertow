UNDERTOW - early playtest build (v0.4, 2026-10-10)
=================================================

You're a submarine sinking into a deep-sea trench. This build is still the
single-player core: it's for checking that timing, the look and now real
songs feel good. Torpedoes and online versus come later.

v0.4 brings five bundled songs, all charted from the music itself.
This build is for friends only: please don't share it further.


HOW TO RUN
----------
1. Unzip the whole folder somewhere (e.g. your Desktop). Keep the .exe and
   the .pck file together.
2. Double-click undertow-debug.exe. The game opens fullscreen.
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
difficulty. "Practice Dive (No-Fail)" does the same, but you can't sink.
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
     file, usually a song.ini, and the audio (song.ogg, song.mp3 or
     song.wav; split stems like guitar.ogg + drums.ogg also work).
  2. Drop the whole folder into the Songs folder. A .zip of the folder
     works too: just drop the .zip in, no need to unpack it.
  3. In SELECT SONG press "Rescan Library" (F5). The song shows up.
  Already have a Clone Hero songs folder? Settings > Library > Add Folder
  reads it where it is. Your files are never copied or changed.

An audio file without a chart (for example a bare .mp3) is listed as
"NEEDS A CHART". You can't play it yet; a tool that charts songs for you
comes in a later update.

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
  - .mid charts (only .chart files work for now).

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
- "Practice Dive (No-Fail)" in the main menu, right under Start Dive.


FEEDBACK WE NEED (reply in Discord or on WhatsApp)
--------------------------------------------------
1. Did it launch? Any errors or crashes? (If it crashed, run
   undertow-debug.console.exe instead and screenshot the text window.
   It shows the error messages.)
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
