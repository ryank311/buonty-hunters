extends RefCounted
## Runtime gun catalogue: original scale, attachment origins and muzzle markers.
static var _entries: Array = []
static var _profiles: Dictionary = {}

static func profile_catalogue() -> Dictionary:
	if _profiles.is_empty():
		_profiles = JSON.parse_string(FileAccess.get_file_as_string("res://resources/recovered/weapon_profiles.json"))
		# JSON numbers are floats; Array.has/find use strict types in Godot.
		for record: Dictionary in _profiles.records.values():
			var modes: Array[int] = []
			for mode: float in record.modes:
				modes.append(int(mode))
			record.modes = modes
	return _profiles

static func records_for(id: String) -> Array:
	var data := profile_catalogue()
	var records: Array = []
	for key: String in data.models.get(id, []):
		records.append(data.records[key])
	return records

static func apply_stats(profile: WeaponProfile, record_id: int = -1) -> void:
	var records := records_for(profile.recovered_model)
	if profile.kind != "firearm" or records.is_empty():
		return
	var selected: Dictionary = records[0]
	if record_id >= 0:
		for record: Dictionary in records:
			if int(record.id) == record_id:
				selected = record
	profile.recovered_stats = selected
	profile.display_name = selected.name.to_upper()
	var modes: Array = selected.modes
	profile.fire_mode = 2 if profile.hold == "long" and modes.has(2) else int(modes.back())
	profile.automatic = modes.has(3)
	profile.rounds_per_minute = 60.0 / float(selected.fire_wait)
	# The recovered bank already encodes each gun's pitch.
	profile.sound_pitch = 1.0
	preload("res://scripts/combat/weapon_tuning.gd").apply(profile)

static func catalogue() -> Array:
	if _entries.is_empty():
		_entries = JSON.parse_string(FileAccess.get_file_as_string("res://resources/recovered/weapons.json")).weapons
	return _entries

static func find(id: String) -> Dictionary:
	for entry: Dictionary in catalogue():
		if entry.id == id:
			return entry
	return {}

static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

static func template(entry: Dictionary) -> String:
	if entry.hold == "pistol":
		return "heavy_pistol" if entry.source_name == "desert_eagle" else "auto_pistol" if entry.source_name == "glock18" else "pistol"
	return {"Shotguns": "shotgun", "Sniper rifles": "sniper", "Submachine guns": "smg"}.get(entry.category, "rifle")

static func profile_for(id: String, record_id: int = -1) -> WeaponProfile:
	var entry := find(id)
	if entry.is_empty() or not entry.playable:
		return null
	# Damage, ammunition and reload still use the prototype family; accuracy and
	# firing modes come from this gun's recovered record.
	var profile := load("res://resources/weapons/%s.tres" % template(entry)).duplicate() as WeaponProfile
	profile.recovered_model = id
	profile.display_name = entry.name.to_upper()
	apply_stats(profile, record_id)
	if record_id >= 0:
		profile.display_name = profile.recovered_stats.name.to_upper()
	return profile
