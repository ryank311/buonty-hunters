extends Node3D
## Native character.rdr gear, including the separate stowed-weapon offsets.
const DATA_PATH := "res://resources/recovered/outfits.json"
const Guns = preload("res://scripts/combat/recovered_weapons.gd")
static var data: Dictionary = {}
var skin: SoldierSkin
var overrides: Dictionary = {}
var show_stowed := true
var show_grenades := true
var pieces: Array[Dictionary] = []
var stowed: Dictionary = {}
var stowed_ids: Dictionary = {}
var grenades: Array[Dictionary] = []
var supply_signature := ""

static func catalogue() -> Dictionary:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return data

static func offset(spec: Dictionary) -> Transform3D:
	var angles := Vector3(float(spec.rotation[0]), float(spec.rotation[1]), float(spec.rotation[2])) * PI / 180.0
	# Recovered fixed-axis X, then Y, then Z (column-vector Rz * Ry * Rx).
	var rotation := Basis(Vector3.BACK, angles.z) * Basis(Vector3.UP, angles.y) * Basis(Vector3.RIGHT, angles.x)
	return Transform3D(rotation, Vector3(float(spec.translation[0]), float(spec.translation[1]), float(spec.translation[2])))

func rebuild() -> void:
	supply_signature = ""  # Refit belt attachments when the body's bind pose changes.
	for piece: Dictionary in pieces:
		piece.node.free()
	pieces.clear()
	var record: Dictionary = catalogue().characters.get(skin.model_path, {})
	var selected: Array = record.get("gear", []).duplicate()
	for slot: String in overrides:
		if overrides[slot] == "auto":
			continue
		selected = selected.filter(func(id: String) -> bool: return catalogue().gear.get(id, {}).get("group", "") != slot)
		if overrides[slot] != "none":
			selected.append(overrides[slot])
	for id: String in selected:
		if not catalogue().gear.has(id):
			continue
		var spec: Dictionary = catalogue().gear[id]
		if skin.motion.rig.names.find(spec.bone) < 0:
			continue
		var path: String = spec.models.get(record.get("context", ""), spec.path)
		var node := load(path).instantiate() as Node3D
		node.name = id
		SoldierSkin.prepare_materials(node)
		add_child(node)
		pieces.append({"node": node, "id": id, "bone": spec.bone, "offset": offset(spec)})
	update_pose()

func bone_world(name: String) -> Transform3D:
	var index: int = skin.motion.rig.names.find(name)
	if not skin.carried.is_empty():
		return skin.motion.to_skeleton.affine_inverse() * skin.skeleton.get_bone_global_pose(skin.motion.ids[index]) * skin.motion.corrections[index].affine_inverse()
	return skin.motion.native_worlds[index]

func update_pose() -> void:
	for piece: Dictionary in pieces:
		piece.node.transform = bone_world(piece.bone) * piece.offset
	for hold: String in stowed:
		var spec: Dictionary = catalogue().weapon_sockets["pistol" if hold == "pistol" else "rifle"]
		stowed[hold].transform = bone_world(spec.bone) * offset(spec) * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
	for grenade: Dictionary in grenades:
		grenade.node.transform = bone_world("hips") * grenade.offset

func update_equipment(proxy: SoldierProxy, weapon: PracticeWeapon) -> void:
	for hold: String in ["long", "pistol"]:
		var id: String = skin.weapon_ids[hold]
		if id != stowed_ids.get(hold, ""):
			if stowed.has(hold):
				stowed[hold].free()
			var entry: Dictionary = Guns.find(id)
			if entry.is_empty():
				continue
			var node := load(entry.path).instantiate() as Node3D
			SoldierSkin.prepare_materials(node)
			add_child(node)
			stowed[hold] = node
			stowed_ids[hold] = id
		if stowed.has(hold):
			var held: Node3D = proxy.pistol_mesh if hold == "pistol" else proxy.rifle_mesh
			stowed[hold].visible = show_stowed and not held.visible
	var supply: Array[String] = []
	if weapon != null and show_grenades:
		for slot: int in range(weapon.profiles.size()):
			var kind: String = weapon.profiles[slot].kind
			if not catalogue().grenades.has(kind):
				continue
			var count: int = weapon.ammo if slot == weapon.active_slot else weapon.magazines[slot]
			if slot == weapon.active_slot and weapon.held_item.visible:
				count -= 1
			for index: int in range(mini(count, 2)):
				if supply.size() < 4:
					supply.append(kind)
	var signature := str(supply)
	if signature != supply_signature:
		supply_signature = signature
		for grenade: Dictionary in grenades:
			grenade.node.free()
		grenades.clear()
		var bind: Transform3D = skin.motion.rig.worlds[skin.motion.rig.names.find("hips")]
		for index: int in range(supply.size()):
			var node := load(catalogue().grenades[supply[index]]).instantiate() as Node3D
			SoldierSkin.prepare_materials(node)
			add_child(node)
			# Belt positions are a fitting adaptation; the meshes and inventory are native.
			var position := bind.origin + Vector3((-1.0 if index % 2 == 0 else 1.0) * (0.17 + 0.06 * (index / 2)), -0.04, -0.16 + 0.13 * (index / 2))
			grenades.append({"node": node, "offset": bind.affine_inverse() * Transform3D(Basis.IDENTITY, position)})
	update_pose()

func choose(slot: String, id: String) -> void:
	overrides[slot] = id
	rebuild()

func reset() -> void:
	overrides.clear()
	show_stowed = true
	show_grenades = true
	rebuild()
