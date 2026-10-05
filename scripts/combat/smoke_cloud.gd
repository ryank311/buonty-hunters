extends Node3D
## A smoke grenade's cloud: overlapping grey puffs that swell, hang, and thin out.
## The puffs are plain unshaded spheres drawn from both sides, so the cloud hides what
## is behind it on every renderer and still looks like smoke from inside.

const PUFFS := 14
const GROW_SECONDS := 2.5
const FADE_SECONDS := 4.0
var radius: float = 4.5
var seconds: float = 18.0
var age: float = 0.0
var material := StandardMaterial3D.new()
var puffs: Array[MeshInstance3D] = []

func start(cloud_radius: float, duration: float) -> void:
	radius = cloud_radius
	seconds = duration
	add_to_group(&"smoke_clouds")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.74, 0.75, 0.72, 0.94)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for index: int in range(PUFFS):
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius * rng.randf_range(0.42, 0.62)
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		puff.mesh = sphere
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := TAU * index / PUFFS
		var spread := radius * rng.randf_range(0.15, 0.6)
		puff.position = Vector3(cos(angle) * spread, sphere.radius * rng.randf_range(0.5, 1.1), sin(angle) * spread)
		add_child(puff)
		puffs.append(puff)
	_process(0.0)

## How much of the cloud is there right now, from 0 (gone) to 1 (full).
func density() -> float:
	return smoothstep(0.0, GROW_SECONDS, age) * (1.0 - smoothstep(seconds - FADE_SECONDS, seconds, age))

func _process(delta: float) -> void:
	age += delta
	var grown := smoothstep(0.0, GROW_SECONDS, age)
	for puff: MeshInstance3D in puffs:
		puff.scale = Vector3.ONE * lerpf(0.15, 1.0, grown)
	material.albedo_color.a = 0.94 * (1.0 - smoothstep(seconds - FADE_SECONDS, seconds, age))
	if age >= seconds:
		queue_free()
