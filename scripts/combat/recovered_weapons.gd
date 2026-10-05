extends RefCounted
## Runtime gun catalogue: original scale, attachment origins and muzzle markers.
static var _entries: Array = []

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

static func profile_for(id: String) -> WeaponProfile:
	var entry := find(id)
	if entry.is_empty() or not entry.playable:
		return null
	# Existing prototype combat tuning, not a claim to recovered ballistic behavior.
	var profile := load("res://resources/weapons/%s.tres" % template(entry)).duplicate() as WeaponProfile
	profile.recovered_model = id
	profile.display_name = entry.name.to_upper()
	return profile
