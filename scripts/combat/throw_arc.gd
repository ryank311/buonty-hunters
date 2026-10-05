extends MeshInstance3D
## The arc drawn while a grenade throw is held: where the grenade will fly if let go
## now, up to the first thing it hits, with a ring where it comes down.
##
## predict() steps the same flight as throwable.gd (gravity, then a swept ray against
## the world each tick), so the line is the throw the player is about to make.

const Combat := preload("res://scripts/combat/combat.gd")
const THROWABLE := preload("res://scripts/combat/throwable.gd")
const MAX_SECONDS := 4.0
## Screen-steady thickness: metres of width per metre from the camera.
const WIDTH_PER_METRE := 0.0025
var lines := ImmediateMesh.new()
var ring := MeshInstance3D.new()
var paint := StandardMaterial3D.new()
var shown_frame: int = -10

func _ready() -> void:
	top_level = true
	mesh = lines
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.vertex_color_use_as_albedo = true
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = paint
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.42
	torus.rings = 16
	torus.ring_segments = 4
	ring.mesh = torus
	var ring_paint := paint.duplicate() as StandardMaterial3D
	ring_paint.vertex_color_use_as_albedo = false
	ring_paint.albedo_color = Color(1.0, 0.93, 0.6, 0.7)
	ring.material_override = ring_paint
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true
	add_child(ring)
	visible = false
	ring.visible = false

## The flight of a grenade thrown from `origin` at `velocity`, up to its first contact:
## {"points", "landing", "normal", "hit"}.
static func predict(world: World3D, origin: Vector3, velocity: Vector3) -> Dictionary:
	var step := 1.0 / Engine.physics_ticks_per_second
	var points := PackedVector3Array([origin])
	var position := origin
	var flight := velocity
	var space := world.direct_space_state
	for tick: int in range(ceili(MAX_SECONDS / step)):
		flight.y -= THROWABLE.GRAVITY * step
		var motion := flight * step
		var query := PhysicsRayQueryParameters3D.create(position, position + motion + motion.normalized() * THROWABLE.RADIUS, Combat.WORLD_MASK)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			points.append(hit.position)
			return {"points": points, "landing": hit.position, "normal": hit.normal, "hit": true}
		position += motion
		points.append(position)
	return {"points": points, "landing": position, "normal": Vector3.UP, "hit": false}

## Draws `flight` (from predict()) as a thin ribbon turned toward `eye`.
func show_flight(flight: Dictionary, eye: Vector3) -> void:
	shown_frame = Engine.get_physics_frames()
	var points: PackedVector3Array = flight.points
	lines.clear_surfaces()
	if points.size() < 2:
		visible = false
		ring.visible = false
		return
	lines.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var travelled := 0.0
	for index: int in range(points.size()):
		var point := points[index]
		var along := (points[mini(index + 1, points.size() - 1)] - points[maxi(index - 1, 0)]).normalized()
		var side := along.cross(point.direction_to(eye)).normalized()
		var width := clampf(point.distance_to(eye) * WIDTH_PER_METRE, 0.008, 0.05)
		if index > 0:
			travelled += point.distance_to(points[index - 1])
		# Fades in clear of the hand, so the line does not cover the soldier.
		var colour := Color(1.0, 0.93, 0.6, 0.85 * smoothstep(0.3, 1.4, travelled))
		lines.surface_set_color(colour)
		lines.surface_add_vertex(point - side * width)
		lines.surface_set_color(colour)
		lines.surface_add_vertex(point + side * width)
	lines.surface_end()
	visible = true
	ring.visible = flight.hit
	if flight.hit:
		var normal: Vector3 = flight.normal
		var across := normal.cross(Vector3.FORWARD if absf(normal.z) < 0.9 else Vector3.RIGHT).normalized()
		# Grows with distance so a far landing spot stays readable.
		var size := clampf(eye.distance_to(flight.landing) * 0.06, 1.0, 2.5)
		ring.global_transform = Transform3D(Basis(across, normal, across.cross(normal)).scaled(Vector3.ONE * size), flight.landing + normal * 0.02)

func hide_flight() -> void:
	visible = false
	ring.visible = false

func _process(_delta: float) -> void:
	# Whatever stops updating the arc (death, a menu, a weapon change) also clears it.
	if visible and Engine.get_physics_frames() - shown_frame > 2:
		hide_flight()
