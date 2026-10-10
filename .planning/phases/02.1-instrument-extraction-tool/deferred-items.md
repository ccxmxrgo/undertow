# Phase 02.1 deferred items

- (found in 02.1-02) The repo has `core.autocrlf=true` and no `.gitattributes`. `render_chart` emits LF text, but a
  committed `notes.chart` may be checked out as CRLF on another Windows clone, which changes the file bytes and so the
  song hash (SONG-05). The plan that writes/commits bundled charts (05/06) should add `*.chart -text` / `*.ini -text`
  (or `eol=lf`) to `.gitattributes`, and write files with `newline=""`.

- (from the 02.1 end-of-phase UAT, 2026-10-10) Difficulty tuning: the user found the bundled charts "a bit harder"
  ("we can tune that later"). In a later phase, tune autochart density / difficulty, for example lower the
  target n/s per difficulty (current Expert targets 2.8-3.5) or tighten the Expert / Hard 1 s caps, then re-gate.
- (from the 02.1 end-of-phase UAT, 2026-10-10) The user's full song list (Clone Hero-style songs to add later):
  https://docs.google.com/spreadsheets/d/13B823ukxdVMocowo1s5XnT3tzciOfruhUVePENKc01o/edit?gid=1870223413
