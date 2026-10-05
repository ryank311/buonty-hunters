extends Node3D
## A thrown grenade (frag, smoke, or flashbang). It flies under gravity, bounces off
## the world, and goes off when its fuse runs out, wherever it has come to rest.

const Combat := preload("res://scripts/combat/combat.gd")
const BLAST_FX := preload("res://scripts/combat/blast_fx.gd")
const SMOKE := preload("res://scripts/combat/smoke_cloud.gd")
## The recovered Mk141 report, three sequencer choices.
const FLASH_REPORTS: Array[AudioStream] = [preload("res://audio/flashbang/mark141_flash_1.wav"), preload("res://audio/flashbang/mark141_flash_2.wav"), preload("res://audio/flashbang/mark141_flash_3.wav")]
const RADIUS := 0.07
const GRAVITY := 16.0
const BOUNCE := 0.38
const COLOURS := {"frag": Color("3f4a33"), "smoke": Color("8a8d86"), "flash": Color("c9cfd4")}
var profile: WeaponProfile
var thrower: Node
var velocity := Vector3.ZERO
var fuse: float = 3.5
var resting: bool = false
var bounces: int = 0
var ignited: bool = false
var smoke_cloud: Node3D

func launch(owner_actor: Node, item: WeaponProfile, origin: Vector3, initial_velocity: Vector3) -> void:
	thrower = owner_actor
	profile = item
	fuse = item.fuse_seconds
	velocity = initial_velocity
	global_position = origin
	if item.kind == "smoke":
		var canister := SMOKE.CANISTER.instantiate() as Node3D
		canister.rotation.z = PI * 0.5
		add_child(canister)
		return
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.2
	sphere.radial_segments = 8
	sphere.rings = 4
	body.mesh = sphere
	var paint := StandardMaterial3D.new()
	paint.albedo_color = COLOURS.get(item.kind, Color.DIM_GRAY)
	paint.roughness = 0.9
	body.material_override = paint
	add_child(body)

func _physics_process(delta: float) -> void:
	if ignited and not is_instance_valid(smoke_cloud):
		queue_free()
		return
	if not ignited:
		fuse -= delta
		if fuse <= 0.0:
			go_off()
			if profile.kind != "smoke":
				return
	if resting:
		return
	velocity.y -= GRAVITY * delta
	var motion := velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + motion + motion.normalized() * RADIUS, Combat.WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += motion
		return
	global_position = hit.position + hit.normal * RADIUS
	velocity = velocity.bounce(hit.normal) * BOUNCE
	bounces += 1
	# Once it is barely moving on something flat enough to hold it, let it lie.
	if velocity.length() < 1.2 and hit.normal.y > 0.6:
		velocity = Vector3.ZERO
		resting = true

func go_off() -> void:
	if ignited:
		return
	ignited = true
	var where := global_position
	var info := {"source": thrower, "weapon": profile.display_name}
	match profile.kind:
		"frag":
			Combat.blast(get_tree(), where, profile.effect_radius, profile.damage, info)
			_burst(Color("ffcf7a"), profile.effect_radius * 0.45, 0.4)
		"flash":
			Combat.flash(get_tree(), where, profile.effect_radius, profile.effect_seconds)
			_burst(Color.WHITE, 2.2, 0.25, 1.0, FLASH_REPORTS.pick_random())
		"smoke":
			smoke_cloud = SMOKE.new()
			Combat.spawn(get_parent(), smoke_cloud)
			smoke_cloud.global_position = where
			smoke_cloud.start(profile.effect_radius, profile.effect_seconds, self)
			return # A burning canister keeps falling/bouncing until it rests.
	queue_free()

func _burst(colour: Color, radius: float, seconds: float, pitch: float = 0.38, report: AudioStream = BLAST_FX.REPORT) -> void:
	var fx := BLAST_FX.new()
	Combat.spawn(get_parent(), fx)
	fx.global_position = global_position
	fx.start(colour, radius, seconds, pitch, report)
