extends Node3D
## Original placed point lights plus documented fixture fallbacks. The Mobile
## renderer accepts eight omni lights per mesh; recovered surfaces span a map.
## Six reusable shadowed lights leave room for weapon/impact effects. Invisible
## distant emitters have no rendering cost and enter the pool as the eye moves.
const CATALOGUE := "res://resources/recovered/lighting.json"
const BUDGET := 6
const UPDATE_INTERVAL := 0.15
const FADE_TIME := 0.18
var sources: Array[Dictionary] = []
var slots: Array[Dictionary] = []
var desired: Array[int] = []
var elapsed := 0.0
var update_in := 0.0

func install(level: Node3D, map_id: String) -> void:
	name = "LocalLights"
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE))
	for entry: Dictionary in catalogue.maps.get(map_id, {}).get("lights", []):
		var source := entry.duplicate()
		source.point = Vector3(entry.position[0], entry.position[1], entry.position[2])
		sources.append(source)
	level.add_child(self)
	for index: int in range(mini(BUDGET, sources.size())):
		var light := OmniLight3D.new()
		light.name = "LocalLight%d" % index
		light.visible = false
		light.shadow_enabled = true
		light.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
		light.shadow_bias = 0.03
		light.shadow_normal_bias = 0.4
		light.light_specular = 0.0
		add_child(light)
		slots.append({"light": light, "source": -1, "fade": 0.0})
	set_process(not sources.is_empty())

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	elapsed += delta
	update_in -= delta
	if update_in <= 0.0:
		_select(to_local(camera.global_position))
		update_in = UPDATE_INTERVAL
	for slot: Dictionary in slots:
		var light: OmniLight3D = slot.light
		var keep := desired.has(slot.source)
		slot.fade = move_toward(slot.fade, 1.0 if keep else 0.0, delta / FADE_TIME)
		if not keep and slot.fade <= 0.0:
			slot.source = -1
			light.visible = false
			for index: int in desired:
				if not slots.any(func(other: Dictionary) -> bool: return other.source == index):
					_bind(slot, index)
					break
		if slot.source >= 0:
			var source: Dictionary = sources[slot.source]
			var flicker := 1.0
			if source.kind == "fire":
				# Stable, low-amplitude fire movement; no strobe or random reseeding.
				var phase := elapsed + float(slot.source) * 2.39
				flicker += 0.06 * sin(phase * 7.3) + 0.035 * sin(phase * 12.7)
			light.light_energy = float(source.get("energy", 1.0)) * slot.fade * flicker

func _select(eye: Vector3) -> void:
	var candidates: Array[Dictionary] = []
	for index: int in range(sources.size()):
		var source: Dictionary = sources[index]
		var distance := eye.distance_to(source.point)
		if distance > float(source.range) + 28.0:
			continue
		# Prefer nearby influence volumes. Hysteresis stops equal-distance lamps
		# swapping every frame as the player idles between them.
		var score := maxf(0.0, distance - float(source.range)) + distance * 0.25
		if desired.has(index):
			score -= 1.0
		candidates.append({"index": index, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
	desired.clear()
	for candidate: Dictionary in candidates.slice(0, BUDGET):
		desired.append(candidate.index)

func _bind(slot: Dictionary, index: int) -> void:
	var source: Dictionary = sources[index]
	var light: OmniLight3D = slot.light
	slot.source = index
	light.position = source.point
	light.light_color = Color(source.color[0], source.color[1], source.color[2])
	light.omni_range = source.range
	# CLight has an inner plateau and outer radius. Godot uses a smooth power
	# curve instead; a wider native plateau gives a gentler attenuation curve.
	light.omni_attenuation = clampf(1.0 - float(source.inner_range) / float(source.range), 0.3, 1.0)
	light.light_energy = 0.0
	light.set_meta("source_path", source.path)
	light.visible = true
