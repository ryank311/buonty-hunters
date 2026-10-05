extends Node3D
## A directional mine. The soldier who places it cannot set it off: once armed, it goes
## off when a living soldier from another team walks into the arc in front of it. The
## blast is a cone and hurts whoever stands in it, friend or enemy.

const Combat := preload("res://scripts/combat/combat.gd")
const BLAST_FX := preload("res://scripts/combat/blast_fx.gd")
const TRIP_RANGE := 4.5
const TRIP_DOT := 0.5 # 60 degrees either side of straight ahead
const BLAST_DOT := 0.35
var profile: WeaponProfile
var placed_by: Node
var team: int = -1
var arming: float = 1.0
var detonated: bool = false

func place(owner_actor: Node, item: WeaponProfile, where: Transform3D) -> void:
	placed_by = owner_actor
	profile = item
	team = Combat.team_of(owner_actor)
	arming = item.fuse_seconds
	global_transform = where
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color("4d5a3a")
	olive.roughness = 0.9
	var pale := StandardMaterial3D.new()
	pale.albedo_color = Color("c9c39a")
	# A curved-looking face plate on two short legs, with a pale strip marking the front.
	for part: Array in [
		[Vector3(0.22, 0.12, 0.035), Vector3(0, 0.13, 0), olive],
		[Vector3(0.18, 0.02, 0.006), Vector3(0, 0.15, -0.02), pale],
		[Vector3(0.012, 0.09, 0.012), Vector3(-0.07, 0.04, 0), olive],
		[Vector3(0.012, 0.09, 0.012), Vector3(0.07, 0.04, 0), olive],
	]:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		piece.mesh = box
		piece.position = part[1]
		piece.material_override = part[2]
		add_child(piece)

func is_armed() -> bool:
	return arming <= 0.0 and not detonated

func _physics_process(delta: float) -> void:
	arming -= delta
	if arming > 0.0 or detonated:
		return
	var forward := -global_basis.z
	var world := get_world_3d()
	for actor: Node in get_tree().get_nodes_in_group(Combat.ACTOR_GROUP):
		if actor == placed_by or not actor is Node3D or not Combat.is_alive(actor) or Combat.team_of(actor) == team:
			continue
		var centre := Combat.centre_of(actor)
		var offset := centre - global_position
		if offset.length() <= TRIP_RANGE and forward.dot(offset.normalized()) >= TRIP_DOT and Combat.clear_line(world, global_position + Vector3.UP * 0.15, centre):
			detonate()
			return

func detonate() -> void:
	if detonated:
		return
	detonated = true
	var info := {"source": placed_by, "weapon": profile.display_name}
	Combat.blast(get_tree(), global_position + Vector3.UP * 0.15, profile.effect_radius, profile.damage, info, -global_basis.z, BLAST_DOT)
	var fx := BLAST_FX.new()
	Combat.spawn(get_parent(), fx)
	fx.global_position = global_position
	fx.start(Color("ffcf7a"), 3.0, 0.4)
	queue_free()
