class_name MovementProfile
extends Resource

## Top speeds are the original game's, from its motion table (motion.rdr) at 0.1 m to the
## source unit: 6.5 running, 1.48 crouched, 1.1 crawling. The recovered gait clips turn
## by distance covered, so the feet stay planted whatever is set here.
@export_range(2.0, 8.0) var run_speed: float = 6.5
## The original had no walk button; this is what half a push of its stick gave.
@export var walk_speed: float = 2.6
@export var crouch_speed: float = 1.48
@export var prone_speed: float = 1.1
@export var prone_turn_speed: float = 1.2
@export var dive_speed: float = 5.6
## Launch push over the speed carried into the dive.
@export var dive_boost: float = 1.3
## Keeps the dive's 0.44 s flight under the original gravity.
@export var dive_lift: float = 5.2
@export var dive_recovery_seconds: float = 0.45
## The original reached nine tenths of its run in 0.18 s, which this acceleration gives.
@export var acceleration: float = 32.0
@export var braking: float = 35.0
@export_range(0.0, 2.0) var body_weight: float = 1.0
## The original's dynamics.rdr: gravity 235 source units/s² (23.5 m/s²).
@export var gravity: float = 23.5
## Chosen for feel, not recovered: high enough to hop onto anything up to about 0.9 m
## that the 0.65 m step does not take; higher ledges are climbed.
@export var jump_height: float = 1.0
## dynamics.rdr step_height 6.5 units: ledges up to this are walked onto without a climb.
@export var step_height: float = 0.65
## dynamics.rdr max_slope: the steepest walkable ground.
@export var max_slope_degrees: float = 50.0
## dynamics.rdr climb heights (metres, matching the clips' root rise): a ledge up to low
## plays "Climb crate", up to medium "Climb medium", and up to high hangs and climbs up.
@export var low_climb_height: float = 1.3
@export var medium_climb_height: float = 2.15
@export var high_climb_height: float = 2.65
## dynamics.rdr min_stand_height: headroom needed on top of a ledge to climb onto it.
@export var climb_headroom: float = 1.0
## Climbing a ladder at a full stick. The original's "Climb ladder" rate works out at
## 7.59 source units a second.
@export var ladder_speed: float = 0.759
## Sideways and backward speed as a share of forward speed, in each stance. The original
## ran 6.5 m/s sideways and 3.7 back, crouch-walked 1.5 and 1.35, and crawled 0.55 and 1.1.
@export var strafe_multiplier: float = 1.0
@export var backward_multiplier: float = 0.57
@export var crouch_strafe_multiplier: float = 1.0
@export var crouch_backward_multiplier: float = 0.91
@export var prone_strafe_multiplier: float = 0.5
@export var prone_backward_multiplier: float = 1.0
