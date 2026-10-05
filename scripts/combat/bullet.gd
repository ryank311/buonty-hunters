extends Node3D
## A bullet that takes time to arrive and drops under gravity (the sniper rifle).
## Every physics tick it sweeps a ray along the path it flew, so it cannot pass through
## cover between ticks, and hands whatever it strikes back to the weapon that fired it.

const Combat := preload("res://scripts/combat/combat.gd")
var weapon: Node
var profile: WeaponProfile
var velocity := Vector3.ZERO
var travelled: float = 0.0
var flight_seconds: float = 0.0
var exclude: Array[RID] = []

func launch(owner_weapon: Node, shot_profile: WeaponProfile, origin: Vector3, direction: Vector3, ignore: Array[RID]) -> void:
	weapon = owner_weapon
	profile = shot_profile
	exclude = ignore
	global_position = origin
	velocity = direction.normalized() * profile.muzzle_velocity
	var tracer := MeshInstance3D.new()
	var streak := BoxMesh.new()
	streak.size = Vector3(0.025, 0.025, 1.8)
	tracer.mesh = streak
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("ffe9a8")
	tracer.material_override = glow
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.position.z = 0.9
	add_child(tracer)
	_face_travel()

func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta + Vector3.DOWN * 0.5 * profile.bullet_gravity * delta * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, Combat.SHOT_MASK, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	flight_seconds += delta
	if not hit.is_empty():
		travelled += from.distance_to(hit.position)
		if is_instance_valid(weapon):
			weapon.bullet_arrived(hit, profile, travelled, flight_seconds)
		queue_free()
		return
	travelled += from.distance_to(to)
	global_position = to
	velocity.y -= profile.bullet_gravity * delta
	_face_travel()
	if travelled >= profile.range_metres:
		queue_free()

func _face_travel() -> void:
	if velocity.length_squared() > 0.01 and absf(velocity.normalized().dot(Vector3.UP)) < 0.999:
		look_at(global_position + velocity, Vector3.UP)
