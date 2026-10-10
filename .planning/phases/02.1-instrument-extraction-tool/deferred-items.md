# Phase 02.1 deferred items

- (found in 02.1-02) The repo has `core.autocrlf=true` and no `.gitattributes`. `render_chart` emits LF text, but a
  committed `notes.chart` may be checked out as CRLF on another Windows clone, which changes the file bytes and so the
  song hash (SONG-05). The plan that writes/commits bundled charts (05/06) should add `*.chart -text` / `*.ini -text`
  (or `eol=lf`) to `.gitattributes`, and write files with `newline=""`.
