UNDERTOW - early playtest build (v0.2, 2026-10-08)
=================================================

You're a submarine sinking into a deep-sea trench, and your note highway is
the sonar screen. This build is still the single-player core: it's for
checking that timing and the look feel good. Torpedoes and online versus
come later.

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
  Pause ............ Esc            (gamepad: Start)
  Fullscreen ....... F11            (switches fullscreen / window)
  Debug overlay .... F3             (shows timing numbers)
  Autoplay ......... F4             (watch the bot play the song perfectly)

The game opens fullscreen. F11 switches to a window and back.
Settings > Display also has a Fullscreen switch and a Low effects switch
(Low effects turns off the goggle-visor look if it bothers you).

Played v0.1? Your keys move to 1 2 3 4 automatically, unless you had
changed them yourself. Settings > Reset Controls always gives you 1 2 3 4.

Menu: "Start Dive" plays the test song. "Practice Dive (No-Fail)" plays it
without being able to sink. Settings lets you rebind keys, change scroll
speed and volume, and turn on No-Fail.

The music is still generated test audio, not real songs yet. Real songs
(Clone Hero charts) come in a later update.


WHAT'S NEW IN v0.2
------------------
- Keys are now 1 2 3 4, so you can play with one hand.
- Each lane has its own color and shape: cyan diamond, amber circle,
  magenta triangle, lime square.
- Hit markers sit on the hull line, so you can see exactly where to hit.
- Notes only light up when you can actually hit them. Dim = too early,
  bright = hit it now.
- A cyberpunk visor frame around the screen (turn it off with Low effects).
- A big NOTE STREAK counter, with popups at 10, 25, 50 and 100 in a row.
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
5. Is the screen readable? Can you tell the 4 note shapes apart quickly?
6. Keyboard or gamepad? Do keys 1 2 3 4 feel OK? Did every press register?
7. What headphones/speakers did you use (wired / Bluetooth / USB)?
8. Anything confusing, ugly or annoying?
9. Is it easier to tell the notes apart now?
10. Do notes look ready at the right moment (do they light up when you can
    hit them)?
11. Does the fullscreen/visor look OK, or did Low effects help?

Thanks for diving!
