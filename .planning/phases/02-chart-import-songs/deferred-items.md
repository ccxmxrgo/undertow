# Deferred items (phase 02)

## Found during 02-06

- **tests/test_pause_overlay.gd `test_pause_freezes_song_time_without_scene_tree_pause` fails in the full suite, passes alone.**
  Song time is still -0.005 s after the 1.5 s wait when the whole suite runs (passes 3/3 when run on its own).
  Reproduced on an untouched HEAD (015371e) checkout in a temp worktree: same failure, 472 cases there, so it is
  not caused by 02-06. Also pre-existing on that checkout: the gdUnit process segfaults while disposing at exit
  (after the summary is printed). Out of scope for 02-06 (timing-core-adjacent test; fix belongs to a timing plan).
