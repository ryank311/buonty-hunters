class_name TacticalMap
extends Control

var session: Node3D
var mapped_level: Node3D
var footprints: Array[PackedVector2Array] = []
var range_metres: float = 38.0
var circle: PackedVector2Array = []

func initialize(owner_session: Node3D) -> void:
	session = owner_session
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild_circle)
	_rebuild_circle()

func _rebuild_circle() -> void:
	circle.clear()
	var radius := size.x * 0.5 - 3
	for index: int in range(64):
		circle.append(size * 0.5 + Vector2.from_angle(TAU * index / 64.0) * radius)
	queue_redraw()

func refresh() -> void:
	if not is_instance_valid(mapped_level) or session.level != mapped_level:
		mapped_level = session.level
		footprints.clear()
		_collect_geometry(mapped_level)
	queue_redraw()

func _collect_geometry(node: Node) -> void:
	# Navigation footprints come from the authored collision geometry, not a second map layout.
	if node is CollisionShape3D and node.get_parent() is StaticBody3D and node.get_parent().collision_layer & 1:
		var vertices: Array[Vector3] = []
		if node.shape is BoxShape3D:
			var half: Vector3 = node.shape.size * 0.5
			if (node.global_transform * Vector3(0,half.y,0)).y > 0.15:
				for x: float in [-half.x, half.x]:
					for z: float in [-half.z, half.z]:
						vertices.append(node.global_transform * Vector3(x, 0, z))
		elif node.shape is ConvexPolygonShape3D:
			for point: Vector3 in node.shape.points:
				vertices.append(node.global_transform * point)
		if vertices.size() >= 3:
			var points := PackedVector2Array()
			for vertex: Vector3 in vertices:
				points.append(Vector2(vertex.x, vertex.z))
			var polygon := Geometry2D.convex_hull(points)
			if polygon.size() >= 4:
				polygon.remove_at(polygon.size() - 1)
				footprints.append(polygon)
	for child: Node in node.get_children():
		_collect_geometry(child)

func map_point(world: Vector3) -> Vector2:
	var origin: Vector3 = session.player.global_position
	var delta := Vector2(world.x - origin.x, world.z - origin.z)
	return size * 0.5 + delta.rotated(session.player.rotation.y) * ((size.x * 0.5 - 6) / range_metres)

func clipped_footprints() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for footprint: PackedVector2Array in footprints:
		var projected := PackedVector2Array()
		for point: Vector2 in footprint:
			projected.append(map_point(Vector3(point.x, 0, point.y)))
		for clipped: PackedVector2Array in Geometry2D.intersect_polygons(projected, circle):
			var clean := _clean_polygon(clipped)
			if clean.size() >= 3:
				result.append(clean)
	return result

func _clean_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	# Tangencies at the circular rim can produce subpixel edges and duplicate vertices.
	var clean := PackedVector2Array()
	for point: Vector2 in polygon:
		if clean.is_empty() or clean[-1].distance_squared_to(point) > 0.01:
			clean.append(point)
	if clean.size() > 1 and clean[0].distance_squared_to(clean[-1]) <= 0.01:
		clean.remove_at(clean.size() - 1)
	if clean.size() < 3:
		return PackedVector2Array()
	var area := 0.0
	for index: int in range(clean.size()):
		area += clean[index].cross(clean[(index + 1) % clean.size()])
	if absf(area) < 0.2 or Geometry2D.triangulate_polygon(clean).is_empty():
		return PackedVector2Array()
	return clean

func _diamond(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2.UP * radius, center + Vector2.RIGHT * radius, center + Vector2.DOWN * radius, center + Vector2.LEFT * radius]), color)

func _draw() -> void:
	if not is_instance_valid(session) or not is_instance_valid(session.level) or circle.size() < 3:
		return
	var center := size * 0.5
	var radius := size.x * 0.5 - 3
	draw_circle(center, radius, Color(0.06,0.10,0.09,0.22))
	for polygon: PackedVector2Array in clipped_footprints():
		draw_colored_polygon(polygon, Color(0.57,0.63,0.58,0.22))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, Color(0.65,0.73,0.64,0.22), 1.0, true)
	var cone := PackedVector2Array([center])
	# The camera's horizontal field of view determines the translucent view sector.
	var camera: Camera3D = session.player.camera_rig.camera
	var viewport := get_viewport_rect().size
	var half_angle := atan(tan(deg_to_rad(camera.fov * 0.5)) * viewport.x / maxf(viewport.y, 1))
	for index: int in range(21):
		cone.append(center + Vector2.from_angle(-PI * 0.5 - half_angle + half_angle * 2 * index / 20.0) * (radius - 1))
	draw_colored_polygon(cone, Color(0.85,0.87,0.75,0.09))
	var spawn: Marker3D = session.level.get_node("Spawns").get_child(session.spawn_index)
	var spawn_position := map_point(spawn.global_position)
	spawn_position = center + (spawn_position - center).limit_length(radius - 8)
	_diamond(spawn_position, 4, Color("92d5d0"))
	_diamond(center, 4, Color("ebd473"))
	draw_line(center + Vector2(0,-6), center + Vector2(0,-12), Color("ebd473"), 1.5, true)
	draw_arc(center, radius, 0, TAU, 96, Color(0.78,0.86,0.78,0.75), 1.5, true)
	var north := Vector2.UP.rotated(session.player.rotation.y)
	var north_point := center + north * (radius - 12)
	draw_string(ThemeDB.fallback_font, north_point + Vector2(-5,5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("dce3d2"))
