extends Control
## Red marks on a ring around the reticle toward enemy gunfire the player can hear: a
## shot within its gun's original Sound_Radius (resources/recovered/muzzle_flashes.json),
## so suppressed guns, whose radius is a few metres, are rarely heard. Each shooter has
## one mark that follows it, holds while it keeps firing and then fades.

const SOURCE := Vector2(640, 448)
## Ring radius and mark width in source pixels; the mark's arc in radians each side.
const RADIUS := 46.0
const WIDTH := 5.0
const SPREAD := 0.28
const HOLD := 0.6
const FADE := 1.0
const COLOR := Color(0.92, 0.12, 0.08)
const ALPHA := 0.8
var player: Node3D
## Shooter instance id -> {origin, age}.
var marks: Dictionary = {}

func _ready() -> void:
	name = "GunfireIndicator"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(Gunfire.LISTENERS)

func heard_gunfire(origin: Vector3, _model: String, shooter: Node, team: int, radius: float) -> void:
	if player == null or shooter == player or team == 0:
		return
	if player.global_position.distance_to(origin) > radius:
		return
	marks[shooter.get_instance_id()] = {"origin": origin, "age": 0.0}

func update_marks(delta: float) -> void:
	for key: int in marks.keys():
		marks[key].age += delta
		if marks[key].age > HOLD + FADE:
			marks.erase(key)
	queue_redraw()

## Clockwise angle of a world point from straight ahead in the view (0 ahead, PI/2 right).
func bearing(point: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 0.0
	var local := camera.global_basis.inverse() * (point - camera.global_position)
	return atan2(local.x, -local.z)

func _draw() -> void:
	var scale := size / SOURCE
	var center := size * 0.5
	for mark: Dictionary in marks.values():
		var fade := 1.0 - clampf((mark.age - HOLD) / FADE, 0.0, 1.0)
		# Godot's arcs start on +X and turn clockwise on screen; ahead is up.
		var angle := bearing(mark.origin) - PI * 0.5
		draw_arc(center, RADIUS * scale.y, angle - SPREAD, angle + SPREAD, 16, Color(COLOR, ALPHA * fade), WIDTH * scale.y, true)
