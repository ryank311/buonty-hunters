extends MeshInstance3D
## A tracer streak from the original EFFE models (a 3 m line along the shot, 30 source
## units) drawn with EFFE_TXR tracer.tif: its top row is the red streak, its bottom row
## the green, each brightest at the head. Ours and our team's rounds burn green, the
## enemy's red, as the original's tracer_ally / tracer_enemy pair. The head flies from
## the muzzle to the hit; the streak shortens into the hit and is gone.

const TEXTURE := preload("res://art/effects/recovered_tracer.png")
const LENGTH := 3.0
const WIDTH := 0.07
## The texture's colours are muted; drawn additively they are brightened to read in daylight.
const GLOW := 2.2
## Visual travel speed in m/s, tuned for a quicker streak at these map distances.
## The source effects' 800-1200 pair may encode speed (80-120 m/s), but its meaning
## is unconfirmed; this is a feel setting rather than a recovered ballistic value.
const SPEED := 140.0
static var shared_mesh: ArrayMesh
static var materials: Dictionary = {}

var from := Vector3.ZERO
var to := Vector3.ZERO
var ally := true
var travelled := 0.0

func _ready() -> void:
	if shared_mesh == null:
		shared_mesh = _streak()
	mesh = shared_mesh
	material_override = _material(ally)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_place()

func _process(delta: float) -> void:
	travelled += delta * SPEED
	if travelled - LENGTH >= from.distance_to(to):
		queue_free()
		return
	_place()

func _place() -> void:
	var total := from.distance_to(to)
	var direction := (to - from).normalized() if total > 0.001 else Vector3.FORWARD
	var head := from + direction * minf(travelled, total)
	var tail := from + direction * clampf(travelled - LENGTH, 0.0, total)
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	# Local +Z runs from the head back along the streak to its tail.
	global_transform = Transform3D(Basis.looking_at(direction, up), head)
	scale = Vector3(1.0, 1.0, maxf(head.distance_to(tail), 0.001))

## Two crossed strips from z 0 (head) to z 1 (tail), so the line has width from any side.
static func _streak() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP]:
		var side := axis * WIDTH * 0.5
		vertices.append_array([-side, side, side + Vector3.BACK, -side, side + Vector3.BACK, -side + Vector3.BACK])
		uvs.append_array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func _material(green: bool) -> StandardMaterial3D:
	if not materials.has(green):
		var glow := StandardMaterial3D.new()
		glow.albedo_texture = TEXTURE
		glow.albedo_color = Color(GLOW, GLOW, GLOW)
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		# The streak and its fade fill the left 18 of the texture's 32 columns.
		glow.uv1_scale = Vector3(0.56, 0.5, 1.0)
		glow.uv1_offset = Vector3(0.0, 0.5 if green else 0.0, 0.0)
		materials[green] = glow
	return materials[green]
