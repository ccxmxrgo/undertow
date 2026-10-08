UNDERTOW - early playtest build (v0.2, 2026-10-08)
=================================================

You're a submarine sinking into a deep-sea trench. This build is still the
single-player core: it's for checking that timing and the new look feel
good. Torpedoes and online versus come later.

This update is based on your v0.1 feedback. Thank you!


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

Menu: "Start Dive" plays the test song. "Practice Dive (No-Fail)" plays it
without being able to sink. Settings lets you rebind keys, change scroll
speed and volume, and turn on No-Fail.

The music is still generated test audio, not real songs yet. Real songs
(Clone Hero charts) come in a later update.


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
- Your best score is saved for each song and shown on the menu and on the
  results screen. Practice, Autoplay and No-Fail dives never set a record.
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

Thanks for diving!
