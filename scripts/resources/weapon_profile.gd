class_name WeaponProfile
extends Resource

@export var display_name: String = "FIELD RIFLE"
@export var automatic: bool = true
@export var magazine_size: int = 30
@export var starting_reserve: int = 90
@export var rounds_per_minute: float = 600.0
@export var reload_seconds: float = 2.4
@export var draw_seconds: float = 0.32
@export var range_metres: float = 150.0
@export var impact_diameter: float = 0.11
# Degrees. These are playtest values, not extracted SOCOM statistics.
@export var vertical_kick: float = 0.65
@export var horizontal_kick: float = 0.16
@export var recovery_delay: float = 0.14
@export var recovery_speed: float = 9.0
@export var max_climb: float = 8.0
@export var base_spread: float = 0.25
@export var walk_spread: float = 0.85
@export var run_spread: float = 5.5
@export var spread_per_shot: float = 0.35
@export var max_bloom: float = 3.5
@export var weapon_kick: float = 1.0

const TUNING_KEYS: Array[String] = ["vertical_kick", "horizontal_kick", "recovery_delay", "recovery_speed", "max_climb", "spread_per_shot", "weapon_kick", "walk_spread", "run_spread", "max_bloom"]
