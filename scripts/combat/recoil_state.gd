class_name RecoilState
extends RefCounted

const HORIZONTAL_PATTERN: Array[float] = [0.45, -0.3, 0.65, -0.5, 0.25, 0.6, -0.7, -0.2]
var offset := Vector2.ZERO # Pitch and yaw in radians; separate from the player's look input.
var bloom: float = 0.0 # Additional cone half-angle in degrees.
var visual_kick: float = 0.0
var since_shot: float = 10.0
var shot_index: int = 0

func reset() -> void:
	offset = Vector2.ZERO
	bloom = 0.0
	visual_kick = 0.0
	since_shot = 10.0
	shot_index = 0

func kick(profile: WeaponProfile, stability: float, running: float = 0.0) -> void:
	if since_shot > 0.35:
		shot_index = 0
	offset.x = minf(offset.x + deg_to_rad(profile.vertical_kick * stability * (1.0 + running * 0.25)), deg_to_rad(profile.max_climb))
	offset.y = clampf(offset.y + deg_to_rad(profile.horizontal_kick * HORIZONTAL_PATTERN[shot_index % HORIZONTAL_PATTERN.size()] * stability), -deg_to_rad(profile.max_climb / 3.0), deg_to_rad(profile.max_climb / 3.0))
	# Bloom is stored before stance scaling, so going prone also steadies an existing burst.
	bloom = minf(bloom + profile.spread_per_shot * (1.0 + running * 1.8), profile.max_bloom)
	visual_kick = minf(visual_kick + profile.weapon_kick, 2.5)
	since_shot = 0.0
	shot_index += 1

func tick(delta: float, profile: WeaponProfile) -> void:
	var before := since_shot
	since_shot += delta
	var recovery_delta := maxf(0.0, since_shot - maxf(before, profile.recovery_delay))
	offset = offset.move_toward(Vector2.ZERO, deg_to_rad(profile.recovery_speed) * recovery_delta)
	bloom = move_toward(bloom, 0.0, 4.0 * recovery_delta)
	visual_kick *= exp(-22.0 * delta)
