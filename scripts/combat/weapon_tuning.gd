extends RefCounted
## Per-gun overrides live in the user's settings, separate from recovered records.
## A record ID follows a gun across slots and geometry variants; equipment uses kind.
static var overrides: Dictionary = {}
const FIELDS := {
	"recovered_recoil_scale": ["Recoil strength (1 = original)", 0, 3, 0.05],
	"recovered_spread_scale": ["Spread strength (1 = original)", 0, 3, 0.05],
	"weapon_kick": ["Visible weapon kick", 0, 3, 0.1],
	"rounds_per_minute": ["Base firing rate (rpm)", 1, 3000, 1],
	"damage": ["Damage per projectile", 0, 5000, 1],
	"magazine_size": ["Magazine / carried capacity", 1, 999, 1],
	"starting_reserve": ["Starting reserve rounds", 0, 3000, 1],
	"reload_seconds": ["Reload time (s)", 0.05, 15, 0.05],
	"draw_seconds": ["Equip time (s)", 0, 5, 0.01],
	"range_metres": ["Maximum range (m)", 1, 3000, 1],
	"falloff_start": ["Full damage through (m)", 0, 3000, 1],
	"falloff_end": ["Minimum damage from (m)", 0, 3000, 1],
	"minimum_damage": ["Minimum damage fraction", 0, 1, 0.05],
	"pellets": ["Projectiles per round", 1, 64, 1],
	"impact_diameter": ["Impact mark diameter (m)", 0.01, 1, 0.01],
	"muzzle_velocity": ["Bullet speed (m/s; 0 = hitscan)", 0, 2000, 10],
	"bullet_gravity": ["Bullet gravity (m/s²)", 0, 100, 0.1],
	"sound_pitch": ["Weapon sound pitch", 0.1, 3, 0.05],
	"throw_speed": ["Full throw speed (m/s)", 1, 60, 0.5],
	"throw_speed_min": ["Minimum throw speed (m/s)", 1, 60, 0.5],
	"fuse_seconds": ["Fuse / arm time (s)", 0.05, 30, 0.05],
	"effect_radius": ["Effect radius (m)", 0.1, 100, 0.1],
	"effect_seconds": ["Effect duration (s)", 0, 120, 0.5],
	"vertical_kick": ["Vertical kick (°)", 0, 5, 0.05],
	"horizontal_kick": ["Horizontal kick (°)", 0, 5, 0.05],
	"recovery_delay": ["Recoil recovery delay (s)", 0, 2, 0.01],
	"recovery_speed": ["Recoil recovery speed (°/s)", 0.1, 50, 0.1],
	"max_climb": ["Maximum recoil climb (°)", 0, 30, 0.1],
	"base_spread": ["Base spread (°)", 0, 15, 0.05],
	"walk_spread": ["Walking spread (°)", 0, 15, 0.05],
	"run_spread": ["Running spread (°)", 0, 30, 0.05],
	"spread_per_shot": ["Spread added per shot (°)", 0, 5, 0.05],
	"max_bloom": ["Maximum spread bloom (°)", 0, 30, 0.05],
	"unaimed_spread": ["Hip-fire spread (°)", 0, 30, 0.05],
	"pellet_spread": ["Additional pellet spread (°)", 0, 30, 0.05],
}

static func key(profile: WeaponProfile) -> String:
	if not profile.recovered_stats.is_empty():
		return "gun_%d" % int(profile.recovered_stats.id)
	return "equipment_" + profile.kind if profile.kind != "firearm" else "legacy_" + profile.display_name

static func capture(profile: WeaponProfile) -> void:
	var values := {}
	for field: String in FIELDS:
		values[field] = profile.get(field)
	values.scope_fovs = profile.scope_fovs.duplicate()
	overrides[key(profile)] = values

static func apply(profile: WeaponProfile) -> void:
	var values: Variant = overrides.get(key(profile), {})
	if not values is Dictionary:
		return
	for field: String in FIELDS:
		if values.has(field) and (values[field] is float or values[field] is int) and is_finite(float(values[field])):
			var value := clampf(float(values[field]), FIELDS[field][1], FIELDS[field][2])
			profile.set(field, roundi(value) if profile.get(field) is int else value)
	var zooms: Variant = values.get("scope_fovs")
	if zooms is PackedFloat32Array and zooms.size() == profile.scope_fovs.size():
		var valid := true
		for zoom: float in zooms:
			valid = valid and is_finite(zoom) and zoom >= 1.0 and zoom <= 100.0
		if valid:
			profile.scope_fovs = zooms.duplicate()
