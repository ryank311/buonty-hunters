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
@export var dive_lift: float = 4.0
@export var dive_recovery_seconds: float = 0.45
## The original reached nine tenths of its run in 0.18 s, which this acceleration gives.
@export var acceleration: float = 32.0
@export var braking: float = 35.0
@export_range(0.0, 2.0) var body_weight: float = 1.0
@export var gravity: float = 18.0
@export var jump_height: float = 0.65
## Sideways and backward speed as a share of forward speed, in each stance. The original
## ran 6.5 m/s sideways and 3.7 back, crouch-walked 1.5 and 1.35, and crawled 0.55 and 1.1.
@export var strafe_multiplier: float = 1.0
@export var backward_multiplier: float = 0.57
@export var crouch_strafe_multiplier: float = 1.0
@export var crouch_backward_multiplier: float = 0.91
@export var prone_strafe_multiplier: float = 0.5
@export var prone_backward_multiplier: float = 1.0
