class_name MovementProfile
extends Resource

@export_range(2.0, 8.0) var run_speed: float = 4.5
@export var walk_speed: float = 1.6
@export var crouch_speed: float = 2.5
@export var prone_speed: float = 0.38
@export var prone_strafe_seconds: float = 1.15
@export var prone_turn_speed: float = 1.2
@export var dive_speed: float = 5.6
@export var dive_lift: float = 3.0
@export var dive_recovery_seconds: float = 0.45
@export var acceleration: float = 18.0
@export var braking: float = 24.0
@export_range(0.0, 2.0) var body_weight: float = 1.0
@export var gravity: float = 18.0
@export var jump_height: float = 0.65
@export var strafe_multiplier: float = 0.95
@export var backward_multiplier: float = 0.8
