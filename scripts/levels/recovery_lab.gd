extends Node3D
## An inspection area for the first recovered assets. Animation is independent of
## the prototype player; the map uses recovered collision plus visible crop fences.

const CLIPS: Array[String] = ["seal_stand", "seal_walk", "seal_run", "seal_crouch"]
const Library = preload("res://scripts/levels/recovery_library.gd")
const Guns = preload("res://scripts/combat/recovered_weapons.gd")
@onready var character: Node3D = $Character
@onready var weapon: Node3D = $Weapon
@onready var retargeted: Node3D = $Retargeted
var animation: Node
var target_animation: Node
var original_library: AnimationLibrary
var data: Dictionary
var character_index: int = 0
var browser: CanvasLayer
var animation_names: Array[String] = []
var clip_index: int = 1
var playback_paused: bool = false
var collision_visible: bool = false
var collision_overlay: MeshInstance3D
var caption: Label3D
var weapon_caption: Label3D
var weapon_index := 0
var guns: Array = []

func _ready() -> void:
	_prepare_materials(self)
	for node: Node in $Map.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape.shape is ConcavePolygonShape3D:
			shape.shape = shape.shape.duplicate()
			# The original probes test both sides. Blender removes duplicate
			# opposite faces, so configure Godot's shape explicitly.
			shape.shape.backface_collision = true
	data = Library.catalogue()
	original_library = load(Library.ORIGINAL)
	animation = Library.attach(character, original_library)
	target_animation = Library.attach(retargeted, original_library)
	animation_names.assign(CLIPS)
	for clip: String in animation.get_animation_list():
		if not animation_names.has(clip):
			animation_names.append(clip)
	for index: int in range(data.characters.size()):
		if data.characters[index].name == "seal_A_scuba":
			character_index = index
	# Both players advance from the same inspection clock.
	caption = _label("", character.position + Vector3(0, 2.37, 0), 24)
	_label("PLAYER • ORIGINAL RIG", retargeted.position + Vector3(0, 2.15, 0), 24)
	weapon_caption = _label("M4 CARBINE", weapon.position + Vector3(0, 0.8, 0), 24)
	_label("CROSSROADS • RECOVERED PLAZA", Vector3(0, 3.1, 0), 28)
	_box("WeaponStand", Vector3(1.5, 0.9, 0.65), weapon.position - Vector3(0, 0.45, 0), Color("535c58"))
	_box("CharacterStand", Vector3(1.5, 0.08, 1.5), character.position - Vector3(0, 0.04, 0), Color("535c58"))
	_box("RetargetStand", Vector3(1.5, 0.08, 1.5), retargeted.position - Vector3(0, 0.04, 0), Color("535c58"))
	for side: int in [-1, 1]:
		_box("CropFenceX%d" % side, Vector3(0.2, 12, 60), Vector3(29.8 * side, 3, 0), Color(0.8, 0.65, 0.25, 0.14))
		_box("CropFenceZ%d" % side, Vector3(60, 12, 0.2), Vector3(0, 3, 29.8 * side), Color(0.8, 0.65, 0.25, 0.14))
		_label("INSPECTION BOUNDARY", Vector3(28.8 * side, 2, 0), 24)
		_label("INSPECTION BOUNDARY", Vector3(0, 2, 28.8 * side), 24)
	set_clip(clip_index)
	guns = Guns.catalogue()
	for index: int in range(guns.size()):
		if guns[index].id == "m4acarbine":
			set_gun(index)
			break
	browser = preload("res://scripts/ui/recovery_browser.gd").new()
	browser.lab = self
	add_child(browser)
	update_player_preview()

func set_gun(index: int) -> void:
	weapon_index = posmod(index, guns.size())
	var entry: Dictionary = guns[weapon_index]
	var angle := weapon.rotation.y
	remove_child(weapon)
	weapon.queue_free()
	weapon = Node3D.new()
	weapon.name = "Weapon"
	weapon.position = Vector3(5, 0.94, 8)
	weapon.rotation.y = angle
	add_child(weapon)
	var model := load(entry.path).instantiate() as Node3D
	var low := Guns.vector(entry.bounds_min)
	var high := Guns.vector(entry.bounds_max)
	model.position = -Vector3((low.x + high.x) * 0.5, low.y, (low.z + high.z) * 0.5)
	weapon.add_child(model)
	_prepare_materials(model)
	weapon_caption.text = entry.name.to_upper()

func equip_gun(record_id: int = -1) -> void:
	var profile := Guns.profile_for(guns[weapon_index].id, record_id)
	if profile == null:
		return
	var combat: PracticeWeapon = get_parent().player.weapon
	var slot := 1 if profile.hold == "pistol" else 0
	combat.receive(slot, profile, profile.magazine_size, profile.starting_reserve)
	combat.equip(slot)

func update_player_preview() -> void:
	var skin: SoldierSkin = get_parent().player.soldier.soldier_skin
	var scene := load(skin.model_path) as PackedScene
	var replacement := scene.instantiate() as Node3D
	replacement.transform = retargeted.transform
	remove_child(retargeted)
	retargeted.queue_free()
	retargeted = replacement
	add_child(retargeted)
	_prepare_materials(retargeted)
	target_animation = Library.attach(retargeted, original_library)
	target_animation.play(animation_names[clip_index])
	target_animation.seek(animation.current_animation_position, true)

func _process(delta: float) -> void:
	if not playback_paused and animation != null:
		seek_animation(fmod(animation.current_animation_position + delta, animation.current_animation_length))

func set_character(index: int) -> void:
	character_index = posmod(index, data.characters.size())
	var scene := load(data.characters[character_index].path) as PackedScene
	var replacement := scene.instantiate() as Node3D
	replacement.transform = character.transform
	remove_child(character)
	character.queue_free()
	character = replacement
	add_child(character)
	_prepare_materials(character)
	animation = Library.attach(character, original_library)
	set_clip(clip_index)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("recovery_clip"):
		set_clip(clip_index + 1)
	elif event.is_action_pressed("recovery_pause"):
		set_playback_paused(not playback_paused)
	elif event.is_action_pressed("recovery_collision"):
		set_collision_visible(not collision_visible)
	elif event.is_action_pressed("recovery_step"):
		step_animation()
	else:
		return
	get_viewport().set_input_as_handled()

func set_clip(index: int) -> void:
	if animation == null or animation_names.is_empty():
		caption.text = "Animation import incomplete"
		return
	clip_index = posmod(index, animation_names.size())
	animation.play(animation_names[clip_index])
	target_animation.play(animation_names[clip_index])
	seek_animation(0.0)
	animation.speed_scale = 0.0 if playback_paused else 1.0
	_update_caption()

func seek_animation(seconds: float) -> void:
	animation.seek(seconds, true)
	target_animation.seek(seconds, true)

func set_playback_paused(value: bool) -> void:
	playback_paused = value
	if animation != null:
		animation.speed_scale = 0.0 if value else 1.0
	_update_caption()

func step_animation() -> void:
	if animation == null or animation_names.is_empty():
		return
	set_playback_paused(true)
	seek_animation(fmod(animation.current_animation_position + 1.0 / 30.0, animation.current_animation_length))
	_update_caption()

func _update_caption() -> void:
	caption.text = "%s\n%s%s" % [data.characters[character_index].name, animation_names[clip_index], " / PAUSED" if playback_paused else ""]
	if browser != null and browser.opened:
		caption.text = "RECOVERED"

func set_collision_visible(value: bool) -> void:
	if collision_overlay == null:
		var lines := ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.25, 1.0, 0.65, 0.65)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
		for node: Node in $Map.find_children("*", "CollisionShape3D", true, false):
			var shape := node as CollisionShape3D
			if not shape.shape is ConcavePolygonShape3D:
				continue
			var faces: PackedVector3Array = shape.shape.get_faces()
			for i: int in range(0, faces.size(), 3):
				for edge: int in range(3):
					lines.surface_add_vertex(to_local(shape.to_global(faces[i + edge])))
					lines.surface_add_vertex(to_local(shape.to_global(faces[i + (edge + 1) % 3])))
		lines.surface_end()
		collision_overlay = MeshInstance3D.new()
		collision_overlay.name = "RecoveredCollisionOverlay"
		collision_overlay.mesh = lines
		collision_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(collision_overlay)
	collision_visible = value
	collision_overlay.visible = value

func _prepare_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var local_mesh := mesh.mesh.duplicate() as ArrayMesh
		for surface: int in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as StandardMaterial3D
			# Foliage/fences use binary coverage; full GS material semantics are not
			# reconstructed yet. This prevents translucent sorting through buildings.
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.5
			local_mesh.surface_set_material(surface, material)
		mesh.mesh = local_mesh
		for surface: int in range(local_mesh.get_surface_count()):
			mesh.set_surface_override_material(surface, null)
	for child: Node in node.get_children():
		_prepare_materials(child)

func _label(text: String, at: Vector3, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.005
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("e1dfcb")
	label.outline_size = 5
	add_child(label)
	return label

func _box(title: String, size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = title
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var visible_box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	visible_box.mesh = mesh
	body.add_child(visible_box)
	add_child(body)
