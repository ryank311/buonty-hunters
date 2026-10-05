class_name RecoveredMap
extends Node3D
## A recovered disc map installed whole: native geometry, collision and sky from
## art/models/recovered_map_<id>.glb; original lighting, fog and spawns from
## resources/recovered/levels/<id>.json (both written by tools/recovery/prepare_level.py).

const LEVELS := "res://resources/recovered/levels/"
const SKY_SHADER := preload("res://shaders/recovered_sky.gdshader")
# PS2 colour registers treat 128 as full intensity.
const COLOUR_SCALE := 255.0 / 128.0
# Sine of the elevation where the sky is clear of fog (about 9 degrees).
const HORIZON_FADE := 0.16

var map_id: String = ""
var data: Dictionary = {}
var kill_height: float = -8.0
var sky: Node3D
var sky_eye := Vector3.ZERO
var restore: Dictionary = {}
var fill_light: DirectionalLight3D

## Installed multiplayer maps, sorted by name. Campaign maps stay offline.
static func catalogue() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for file: String in DirAccess.get_files_at(LEVELS):
		if not file.ends_with(".json"):
			continue
		var entry: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVELS + file))
		if entry is Dictionary and entry.get("mode") == "Multiplayer" and ResourceLoader.exists(entry.model):
			result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return result

func _init(id: String = "") -> void:
	map_id = id
	# No stand-in soldiers: the default roster is placed for the Old Quarter.
	set_meta(&"inspection_only", true)

func _ready() -> void:
	name = "RecoveredMap"
	data = JSON.parse_string(FileAccess.get_file_as_string(LEVELS + map_id.to_lower() + ".json"))
	kill_height = data.kill_height
	set_meta("kill_height", kill_height)
	var model := (load(data.model) as PackedScene).instantiate() as Node3D
	model.name = "Map"
	add_child(model)
	_prepare_surfaces(model)
	preload("res://scripts/levels/recovered_actions.gd").new().install(self, model, map_id)
	for shape: CollisionShape3D in model.find_children("*", "CollisionShape3D", true, false):
		if shape.shape is ConcavePolygonShape3D:
			# The original probes accept both polygon orientations (see PILOT.md).
			shape.shape = shape.shape.duplicate()
			shape.shape.backface_collision = true
	sky = model.get_node_or_null("Sky")
	if sky != null:
		_prepare_sky()
	_add_spawns()
	_apply_ambience()

func _exit_tree() -> void:
	var session := get_parent()
	if session == null:
		return
	if restore.has("environment"):
		session.get_node("Environment").environment = restore.environment
	var sun := session.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null and restore.has("sun"):
		sun.transform = restore.sun.transform
		sun.light_color = restore.sun.color
		sun.light_energy = restore.sun.energy

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if sky != null and camera != null:
		var eye := camera.global_position
		if not sky.get_meta("follow_height", true):
			eye.y = global_position.y
		sky.global_position = eye - sky_eye
		var distance := camera.far * 0.9
		for mesh: MeshInstance3D in sky.find_children("*", "MeshInstance3D", true, false):
			for surface: int in range(mesh.get_surface_override_material_count()):
				var material := mesh.get_surface_override_material(surface) as ShaderMaterial
				if material != null:
					material.set_shader_parameter("sky_distance", distance)

func _prepare_surfaces(model: Node) -> void:
	var materials: Dictionary = data.materials
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface: int in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if original == null:
				continue
			var info: Dictionary = materials.get(original.resource_name, {})
			if info.get("sky", false):
				continue
			var material := original.duplicate() as BaseMaterial3D
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.roughness = 1.0
			material.metallic_specular = 0.0
			match info.get("mode", "OPAQUE"):
				"ALPHACLIP":
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					material.alpha_scissor_threshold = 0.5
				"ADDITIVE":
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
					material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					material.no_depth_test = false
					material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
					mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_:
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if info.get("translucent", false) else BaseMaterial3D.TRANSPARENCY_DISABLED
			mesh.set_surface_override_material(surface, material)

func _prepare_sky() -> void:
	sky.reparent(self, false)
	sky.transform = Transform3D.IDENTITY
	var low := Vector3.INF
	var high := -Vector3.INF
	for mesh: MeshInstance3D in sky.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box := mesh.transform * mesh.get_aabb()
		low = low.min(box.position)
		high = high.max(box.end)
		for surface: int in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = SKY_SHADER
			if original != null:
				material.set_shader_parameter("albedo_texture", original.albedo_texture)
				material.set_shader_parameter("use_alpha", original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			var fog: Dictionary = data.ambience.fog
			material.set_shader_parameter("fog_color", Color(fog.color[0], fog.color[1], fog.color[2]))
			# Fogged maps hide the dome's lower band in the fog, as the original's
			# 82 m fog wall hid the horizon.
			material.set_shader_parameter("horizon_fade", HORIZON_FADE if fog.enabled else 0.0)
			mesh.set_surface_override_material(surface, material)
	if data.sky.source == "level":
		# A dome built into the level keeps its authored height above the ground;
		# it only follows the camera horizontally.
		sky_eye = Vector3.ZERO
		sky.set_meta("follow_height", false)
	else:
		# A separate sky model has no world height: put the eye on its axis just
		# above the rim, so the rim meets the horizon.
		sky_eye = Vector3(0, low.y + (high.y - low.y) * 0.25, 0)

func _add_spawns() -> void:
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	add_child(spawns)
	var locations := Node3D.new()
	locations.name = "Locations"
	add_child(locations)
	for entry: Dictionary in data.spawns:
		var position := Vector3(entry.position[0], entry.position[1] + 0.05, entry.position[2])
		var marker := Marker3D.new()
		marker.name = entry.name.validate_node_name()
		spawns.add_child(marker)
		# The preparation picks the most open direction at eye height.
		var facing := Vector3(entry.facing[0], 0, entry.facing[1]) if entry.has("facing") else Vector3(-position.x, 0, -position.z)
		marker.transform = Transform3D(Basis.looking_at(facing if facing.length() > 0.1 else Vector3.FORWARD, Vector3.UP), position)
		var location := Marker3D.new()
		location.name = marker.name
		location.position = position
		location.set_meta("title", entry.name.to_upper())
		location.set_meta("radius", 25.0)
		locations.add_child(location)

func _apply_ambience() -> void:
	var session := get_parent()
	var ambience: Dictionary = data.ambience
	var fog: Dictionary = ambience.fog
	var fog_colour := Color(fog.color[0], fog.color[1], fog.color[2])
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = fog_colour
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = _colour(ambience.ambient)
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = fog.enabled
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = fog_colour
	environment.fog_light_energy = 1.0
	environment.fog_density = 1.0
	environment.fog_sky_affect = 0.0
	environment.fog_depth_begin = fog.begin
	environment.fog_depth_end = fog.end
	environment.fog_depth_curve = 1.0
	var world := session.get_node_or_null("Environment") as WorldEnvironment
	if world != null:
		restore.environment = world.environment
		world.environment = environment
	var lights: Array = ambience.lights
	var sun := session.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null and not lights.is_empty():
		restore.sun = {"transform": sun.transform, "color": sun.light_color, "energy": sun.light_energy}
		_aim(sun, lights[0])
	if lights.size() > 1:
		fill_light = DirectionalLight3D.new()
		fill_light.name = "FillLight"
		add_child(fill_light)
		_aim(fill_light, lights[1])

func _aim(light: DirectionalLight3D, entry: Dictionary) -> void:
	var direction := Vector3(entry.direction[0], entry.direction[1], entry.direction[2]).normalized()
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD
	light.global_basis = Basis.looking_at(direction, up)
	var colour := _colour(entry.color)
	var energy := maxf(colour.r, maxf(colour.g, colour.b))
	light.light_color = colour / energy if energy > 0.0 else Color.BLACK
	light.light_energy = energy

func _colour(values: Array) -> Color:
	return Color(values[0] * COLOUR_SCALE, values[1] * COLOUR_SCALE, values[2] * COLOUR_SCALE)
