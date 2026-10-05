class_name SoldierSkin
extends Node3D
## The recovered character is the gameplay model, with its original 26-part rig.
## Native motion drives the skin. The proxy supplies controller bookkeeping.

const Library = preload("res://scripts/levels/recovery_library.gd")
const MODEL := "res://art/models/recovered_char_seal_a_cqb.glb"
const RIFLE := "res://art/models/recovered_m4.glb"
# Undo the inspection export's centering, retaining its canonical -Z facing.
const RIFLE_ORIGIN := Vector3(0, -0.12186501, -0.096025765)
const RIFLE_MUZZLE := RIFLE_ORIGIN + Vector3(0, 0.216, -0.443055)
const CARRIERS := {"rthigh": "RThigh", "rcalf": "RShin", "rfoot": "RShin", "rtoe": "RShin", "lthigh": "LThigh", "lcalf": "LShin", "lfoot": "LShin", "ltoe": "LShin", "rbicep": "RUpperArm", "rforearm": "RForearm", "rhand": "RForearm", "lbicep": "LUpperArm", "lforearm": "LForearm", "lhand": "LForearm", "neck": "Head", "head": "Head"}
var model: Node3D
var model_path: String = MODEL
var skeleton: Skeleton3D
var motion: Node
var driver: RefCounted
var bone: Dictionary = {}
var carried: Array = []

static func wear(proxy: SoldierProxy) -> SoldierSkin:
	var skin := SoldierSkin.new()
	skin.name = "Skin"
	proxy.add_child(skin)
	skin.set_model_path(MODEL)
	for part: MeshInstance3D in proxy.parts.values():
		part.hide()
	for old: Node in proxy.rifle_mesh.get_children():
		old.free()
	var rifle := load(RIFLE).instantiate() as Node3D
	rifle.position = RIFLE_ORIGIN
	prepare_materials(rifle)
	proxy.rifle_mesh.add_child(rifle)
	return skin

func set_model_path(path: String) -> void:
	if model != null:
		model.free()
	model_path = path
	model = load(path).instantiate()
	prepare_materials(model)
	add_child(model)
	motion = Library.attach(model)
	skeleton = motion.skeleton
	bone.clear()
	for index: int in range(skeleton.get_bone_count()):
		bone[skeleton.get_bone_name(index)] = index
	driver = preload("res://scripts/actors/recovered_locomotion.gd").new()
	motion.play("seal_stand")
	motion.seek(0)
	set_process(false)

static func prepare_materials(root: Node) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		# Keep per-character paint on an owned mesh. Surface overrides on shared
		# imported meshes leave stale material queries when a sibling is freed
		# (reproducible with two CQB instances in Godot's headless renderer).
		var local_mesh := mesh.mesh.duplicate() as ArrayMesh
		for surface: int in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_active_material(surface) as BaseMaterial3D
			if original == null:
				continue
			var material := original.duplicate() as BaseMaterial3D
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			local_mesh.surface_set_material(surface, material)
		mesh.mesh = local_mesh
		for surface: int in range(local_mesh.get_surface_count()):
			mesh.set_surface_override_material(surface, null)

func pose(proxy: SoldierProxy, stance: int, speed: float, movement: Vector2, grounded: bool, pitch: float, delta: float) -> void:
	driver.drive(self, proxy, stance, speed, movement, grounded, pitch, delta)

func place_weapon(proxy: SoldierProxy, clip: String, seconds: float) -> void:
	var attachment: Transform3D = motion.attachment(clip, seconds, "pistol" if proxy.weapon_slot == 1 else "rifle")
	var canonical := attachment * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
	var local := proxy.weapon_pivot.transform.affine_inverse() * canonical
	if proxy.weapon_slot == 0:
		proxy.rifle_mesh.transform = local
		proxy.muzzle.transform = local * Transform3D(Basis.IDENTITY, RIFLE_MUZZLE)
	else:
		proxy.pistol_mesh.transform = local
		proxy.muzzle.transform = local * Transform3D(Basis.IDENTITY, Vector3(0, 0.015, -0.26))
	var weapon: Node = proxy.get_parent().get_node_or_null("Weapon")
	if weapon != null and weapon.held_item.visible:
		var hand: Transform3D = motion.native_worlds[motion.rig.names.find("rhand")]
		weapon.held_item.transform = proxy.weapon_pivot.transform.affine_inverse() * hand

func tint(colour: Color, amount: float) -> void:
	# Keep recovered face textures intact; a modest gear tint identifies teams.
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null or "face" in material.resource_name.to_lower() or "head" in material.resource_name.to_lower():
				continue
			material.albedo_color = material.albedo_color.lerp(colour, amount * 0.35)

## Seed ragdoll joints from the actual original rig, not the old model's lengths.
func capture_proxy(proxy: SoldierProxy) -> void:
	var pose: Array = motion.native_worlds
	for pair: Array in [["L", "l"], ["R", "r"]]:
		var side: String = pair[0]
		var prefix: String = pair[1]
		var arm: Array[Vector3] = []
		var leg: Array[Vector3] = []
		for part: String in ["bicep", "forearm", "hand"]:
			arm.append(pose[motion.rig.names.find(prefix + part)].origin)
		for part: String in ["thigh", "calf", "foot"]:
			leg.append(pose[motion.rig.names.find(prefix + part)].origin)
		proxy.arm_joints[side] = arm
		proxy.leg_joints[side] = leg
		proxy._bone(side + "UpperArm", arm[0], arm[1], 1.0)
		proxy._bone(side + "Forearm", arm[1], arm[2], 1.0)
		proxy._bone(side + "Thigh", leg[0], leg[1], 1.0)
		proxy._bone(side + "Shin", leg[1], leg[2], 1.0)
	for pair: Array in [["Pelvis", "hips"], ["Torso", "spinehi"], ["Head", "head"], ["Neck", "neck"]]:
		proxy.parts[pair[0]].transform = pose[motion.rig.names.find(pair[1])]

static func limp(from: SoldierSkin, ragdoll: Node3D, bodies: Dictionary) -> SoldierSkin:
	var skin := SoldierSkin.new()
	skin.name = "Skin"
	ragdoll.add_child(skin)
	skin.set_model_path(from.model_path)
	skin.global_transform = from.global_transform
	for index: int in range(skin.skeleton.get_bone_count()):
		skin.skeleton.set_bone_pose(index, from.skeleton.get_bone_pose(index))
	for index: int in range(skin.skeleton.get_bone_count()):
		var name := skin.skeleton.get_bone_name(index)
		var body: RigidBody3D = bodies[CARRIERS.get(name, "Torso")]
		skin.carried.append([index, body, body.global_transform.affine_inverse() * skin.skeleton.global_transform * skin.skeleton.get_bone_global_pose(index)])
	skin.set_process(true)
	return skin

func _process(_delta: float) -> void:
	var inverse := skeleton.global_transform.affine_inverse()
	var moving := false
	for entry: Array in carried:
		var body: RigidBody3D = entry[1]
		if not is_instance_valid(body):
			set_process(false)
			return
		moving = moving or not body.freeze
		skeleton.set_bone_global_pose(entry[0], inverse * body.global_transform * entry[2])
	set_process(moving)
