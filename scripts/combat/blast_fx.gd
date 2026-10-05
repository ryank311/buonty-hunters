extends Node3D
## A short-lived burst of light and noise for explosions and flashes. It does no damage.

## The game has one shot recording; slowed right down it stands in for a blast.
const REPORT := preload("res://audio/rifle.wav")
var seconds: float = 0.35
var lifetime: float = 0.35
var age: float = 0.0
var reach: float = 1.0
var ball := MeshInstance3D.new()
var light := OmniLight3D.new()
var material := StandardMaterial3D.new()
var sound := AudioStreamPlayer3D.new()

## `pitch` sets the character of the noise: low for an explosion, higher for a flashbang.
func start(colour: Color, radius: float, duration: float, pitch: float = 0.38) -> void:
	reach = radius
	seconds = duration
	sound.stream = REPORT
	sound.pitch_scale = pitch
	sound.volume_db = -3.0
	sound.max_distance = 160.0
	add_child(sound)
	sound.play()
	# Outlive the light by as long as the noise takes to finish.
	lifetime = maxf(seconds, REPORT.get_length() / pitch + 0.1)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	ball.mesh = sphere
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	ball.material_override = material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	light.light_color = colour
	light.omni_range = radius * 4.0
	light.light_energy = 6.0
	add_child(light)
	_process(0.0)

func _process(delta: float) -> void:
	age += delta
	var progress := clampf(age / seconds, 0.0, 1.0)
	ball.scale = Vector3.ONE * lerpf(reach * 0.25, reach, sqrt(progress))
	material.albedo_color.a = 1.0 - progress
	light.light_energy = 6.0 * (1.0 - progress)
	if age >= lifetime:
		queue_free()
