class_name RecoveredMuzzleFlash
extends Node3D
## The original game's muzzle flashes. Each weapon's FireAnimName chooses a flash type
## (resources/recovered/muzzle_flashes.json, from tools/recovery/prepare_muzzle_flashes.py):
## one of three recovered flame models, rolled about the barrel to one of the type's
## angles, grown from a tenth to one of its three sizes, with a short warm muzzle light.
## Suppressed weapons have no flash. The weapon's tick advances it, so it keeps the
## weapon's clock (and pauses with it); hiding the node from outside stops the flash.

const DATA := "res://resources/recovered/muzzle_flashes.json"
const MODEL := "res://art/models/recovered_muzzle_flash.glb"
## Muzzle light brightness at the decoded strength of 1.0.
const LIGHT_ENERGY := 6.0
static var data: Dictionary = {}

var models: Dictionary = {}
var light := OmniLight3D.new()
var spec: Dictionary = {}
var shown: MeshInstance3D
var size := 1.0
var age := 0.0
var duration := 0.0

func _ready() -> void:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var scene := (load(MODEL) as PackedScene).instantiate()
	add_child(scene)
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = false
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface: int in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			# The PS2 drew the flame additively: its alpha shapes the glow.
			var glow := StandardMaterial3D.new()
			glow.albedo_texture = original.albedo_texture if original != null else null
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			glow.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			glow.cull_mode = BaseMaterial3D.CULL_DISABLED
			glow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
			mesh.set_surface_override_material(surface, glow)
		models[String(mesh.name)] = mesh
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	visible = false

## The flash type a weapon fires with (its recovered ModelName), or "" for none.
static func flash_for(model: String) -> String:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var entries: Array = data.weapons.get(model.to_lower(), [])
	return entries[0].flash if not entries.is_empty() and entries[0].flash != null else ""

func fire(model: String) -> void:
	var kind := flash_for(model)
	stop()
	if kind == "" or not models.has(data.flashes[kind].model):
		return
	spec = data.flashes[kind]
	shown = models[spec.model]
	size = float(spec.sizes.pick_random())
	shown.rotation = Vector3(0, 0, float(spec.rolls.pick_random()))
	shown.visible = true
	light.light_color = Color(spec.light.color[0], spec.light.color[1], spec.light.color[2])
	light.omni_range = spec.light.range_m[1]
	light.visible = true
	age = 0.0
	duration = maxf(float(spec.light.seconds), float(spec.grow_seconds))
	visible = true
	_show()

func stop() -> void:
	if shown != null:
		shown.visible = false
	light.visible = false
	visible = false

## Advances a flash in progress by the weapon's tick.
func advance(delta: float) -> void:
	if shown == null or not shown.visible:
		return
	if not visible:
		stop()
		return
	age += delta
	if age >= duration:
		stop()
		return
	_show()

func _show() -> void:
	var grow := clampf(age / maxf(float(spec.grow_seconds), 0.001), 0.0, 1.0)
	shown.scale = Vector3.ONE * lerpf(0.1, size, grow)
	light.light_energy = LIGHT_ENERGY * float(spec.light.strength) * (1.0 - age / duration)
