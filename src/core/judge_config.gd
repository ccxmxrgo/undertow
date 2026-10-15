class_name JudgeConfig
extends Resource
## All judgment, hull, score and clock tunables (D-08). Seconds unless noted.
## Windows and tuning live here only; the judge contains no magic numbers.

@export var perfect_window: float = 0.050
@export var good_window: float = 0.100
@export var early_miss_window: float = 0.130
@export var release_forgive_window: float = 0.100
@export var sustain_tick_interval: float = 0.1
## Hull damage for a stray press (D-10): default 0, revisit in Phase 3.
@export var stray_hull_damage: float = 0.0

@export var hull_start: float = 100.0
@export var miss_damage: float = 8.0
@export var perfect_regen: float = 0.25

@export var score_perfect: int = 100
@export var score_good: int = 50
@export var score_sustain_tick: int = 10
@export var combo_per_multiplier_step: int = 10
@export var max_multiplier: int = 4
## Depth in meters = score / score_per_meter (D-14).
@export var score_per_meter: float = 100.0

## Clock discipline tuning (ClockModel): snap above this error, else slew.
@export var clock_snap_s: float = 0.050
## Time constant of the audio-target smoothing (seconds). Replaces the per-frame 0.15 fraction,
## which gave p99 3.84 ms of jitter at 240 Hz (playtest 01-07) and varied with frame rate.
## Chosen by tools/playtest/replay_clock.py --sweep on the 240 Hz capture (p99 < 1.7 ms at 0.15 s
## but 0.4 s was needed so the synthetic white-noise test (3.2 ms std at 30 fps) stays under 2 ms).
@export var clock_slew_tau_s: float = 0.4
