class_name WeaponProfile
extends Resource

@export var display_name: String = "M4A1"
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
@export var recovered_recoil_scale: float = 1.0
@export var recovered_spread_scale: float = 1.0
# Populated from the original reader at loadout creation, shared as read-only data.
var recovered_stats: Dictionary = {}
var fire_mode: int = 0
# Cone added while firing without focus aim; keeps scoped weapons honest from the hip.
@export var unaimed_spread: float = 0.0

@export_group("Damage")
# Torso damage per projectile; head and limb hits scale it (see combat.gd).
@export var damage: float = 34.0
# Full damage out to falloff_start metres, easing to minimum_damage (a fraction) at falloff_end.
@export var falloff_start: float = 60.0
@export var falloff_end: float = 150.0
@export_range(0.0, 1.0) var minimum_damage: float = 0.7
@export var pellets: int = 1
# Extra cone half-angle in degrees shared by every pellet of one shell.
@export var pellet_spread: float = 0.0

@export_group("Ballistics")
# Above zero the weapon fires a travelling bullet instead of an instant hitscan ray.
@export var muzzle_velocity: float = 0.0
@export var bullet_gravity: float = 9.8
# Vertical field of view at each scope zoom step; empty means no scope.
@export var scope_fovs: PackedFloat32Array = PackedFloat32Array()

@export_group("Carry")
@export_enum("firearm", "frag", "smoke", "flash", "claymore") var kind: String = "firearm"
@export_enum("long", "pistol") var hold: String = "long"
@export var recovered_model: String = ""
# Metres from the weapon pivot to the muzzle, and a stretch applied to the stand-in mesh.
@export var muzzle_length: float = 0.52
@export var visual_scale := Vector3.ONE
@export var sound_pitch: float = 1.0

@export_group("Equipment")
# Thrown and placed items: magazine_size is how many are carried.
# A grenade's launch speed at full strength, and from the briefest tap of the button.
@export var throw_speed: float = 15.0
@export var throw_speed_min: float = 9.0
@export var fuse_seconds: float = 3.5
@export var effect_radius: float = 8.0
@export var effect_seconds: float = 0.0

const TUNING_KEYS: Array[String] = ["vertical_kick", "horizontal_kick", "recovery_delay", "recovery_speed", "max_climb", "spread_per_shot", "weapon_kick", "walk_spread", "run_spread", "max_bloom", "recovered_recoil_scale", "recovered_spread_scale"]
