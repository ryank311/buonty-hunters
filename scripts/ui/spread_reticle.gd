class_name SpreadReticle
extends Control

const DIRECTIONS := [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]
const CIRCLE_FILL := Color(0.08,0.09,0.09,0.12)
const CIRCLE_RIM := Color(0.04,0.05,0.05,0.27)
var center_ring := Control.new()
var spread_marks: Array[Control] = []
var feedback := Control.new()
var circle_radius: float = 32.0
var displayed_spread: float = 0.0
var target_spread: float = 0.0
var mark_distance: float = 40.0
var ui_scale: float = 1.0
var mark_length: float = 22.0
var ink := Color(0.89,0.90,0.86,0.88)
var blocked: bool = false
var hit: bool = false

func _ready() -> void:
	name = "Reticle"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_ring.name = "CenterRing"
	center_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_ring)
	center_ring.draw.connect(_draw_center)
	for index: int in range(4):
		var mark := Control.new()
		mark.name = ["North","East","South","West"][index]
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(mark)
		spread_marks.append(mark)
		mark.draw.connect(func() -> void:
			mark.draw_line(Vector2.ZERO,DIRECTIONS[index] * mark_length * ui_scale,Color(0.04,0.06,0.04,0.65),4.0 * ui_scale,true)
			mark.draw_line(Vector2.ZERO,DIRECTIONS[index] * mark_length * ui_scale,ink,2.0 * ui_scale,true)
		)
	feedback.name = "HitAndObstruction"
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feedback)
	feedback.draw.connect(_draw_feedback)

func update_reticle(spread_degrees: float, vertical_fov: float, delta: float, obstructed: bool, hit_flash: bool, paused: bool, recoil_pixels: Vector2 = Vector2.ZERO) -> void:
	visible = not paused
	blocked = obstructed
	hit = hit_flash
	ink = Color("dca46c") if blocked else Color(0.89,0.90,0.86,0.88)
	ui_scale = clampf(size.y / 720.0,0.75,1.6)
	circle_radius = 32.0 * ui_scale
	target_spread = tan(deg_to_rad(spread_degrees)) * size.y * 0.5 / tan(deg_to_rad(vertical_fov * 0.5))
	# Fast outward response, slower settling. Neither the ring nor the aim point expands.
	var rate := 35.0 if target_spread > displayed_spread else 9.0
	displayed_spread = lerpf(displayed_spread,target_spread,1.0 - exp(-rate * delta))
	mark_distance = circle_radius + 8.0 * ui_scale + displayed_spread
	var center := size * 0.5 + recoil_pixels
	center_ring.position = center
	feedback.position = center
	for index: int in range(spread_marks.size()):
		spread_marks[index].position = center + DIRECTIONS[index] * mark_distance
		spread_marks[index].queue_redraw()
	center_ring.queue_redraw()
	feedback.queue_redraw()

func _draw_center() -> void:
	center_ring.draw_circle(Vector2.ZERO,circle_radius,CIRCLE_FILL)
	center_ring.draw_arc(Vector2.ZERO,circle_radius,0,TAU,64,CIRCLE_RIM,2.5 * ui_scale,true)
	center_ring.draw_circle(Vector2.ZERO,1.5 * ui_scale,Color(0.92,0.94,0.89,0.9))

func _draw_feedback() -> void:
	if hit:
		for direction: Vector2 in [Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
			feedback.draw_line(direction * 5 * ui_scale,direction * 10 * ui_scale,ink,2.0 * ui_scale,true)
	if blocked:
		feedback.draw_line(Vector2(-7,34) * ui_scale,Vector2(7,34) * ui_scale,ink,3.0 * ui_scale,true)
