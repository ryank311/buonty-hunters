extends Node3D
## A source-fed volume, rendered by ray integration on the Mobile renderer too.
## Recovery supplies the canister and puff detail; transport/lifetime are adapted.

const GROW_SECONDS := 2.5
const CANISTER := preload("res://art/models/recovered_smoke_grenade.glb")
const SHADER := preload("res://shaders/smoke_volume.gdshader")
const NOISE := preload("res://resources/smoke_noise.tres")
const PUFF := preload("res://art/effects/recovered/cloudpuff01.png")
## Native cap is 10 cm above the attachment origin, laid on its side at runtime.
const VENT := Vector3(-0.10, 0.0, 0.0)
var radius: float = 8.0
var seconds: float = 18.0
var age: float = 0.0
var emitter: Node3D
var material := ShaderMaterial.new()
var volume := MeshInstance3D.new()

func start(cloud_radius: float, duration: float, source_node: Node3D = null) -> void:
	radius = maxf(cloud_radius, 0.1)
	seconds = maxf(duration, 0.1)
	emitter = source_node
	add_to_group(&"smoke_clouds")
	if emitter == null:
		var canister := CANISTER.instantiate() as Node3D
		add_child(canister)
		canister.rotation.z = PI * 0.5
	var box := BoxMesh.new()
	# Wider screens spread along the ground instead of becoming twice as tall.
	var height := minf(radius, 4.5)
	box.size = Vector3(radius * 2.8, height * 2.0, radius * 2.8)
	volume.mesh = box
	volume.position.y = height * 0.9
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.shader = SHADER
	material.set_shader_parameter("billows", NOISE)
	material.set_shader_parameter("recovered_puff", PUFF)
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("lifetime", seconds)
	material.set_shader_parameter("bounds", box.size * 0.5)
	material.set_shader_parameter("source", VENT - volume.position)
	volume.material_override = material
	add_child(volume)
	_process(0.0)

## How much of the cloud is there right now, from 0 (gone) to 1 (full).
func density() -> float:
	return smoothstep(0.0, minf(GROW_SECONDS, seconds * 0.3), age) * (1.0 - smoothstep(seconds * 0.68, seconds, age))

func _process(delta: float) -> void:
	age += delta
	if is_instance_valid(emitter):
		global_position = emitter.global_position
	material.set_shader_parameter("age", age)
	volume.visible = age > 0.0 and age < seconds
	if age >= seconds:
		queue_free()
