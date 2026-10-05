extends RefCounted
## Restore original moving leaves from the map export's merged surfaces. Only
## instance-owned meshes/shapes change; the source GLBs and cached resources do not.
const Door = preload("res://scripts/levels/context_door.gd")
var render_lookup: Dictionary = {}
var collision_lookup: Dictionary = {}
var doors: Array[Node3D] = []

func install(level: Node3D, model: Node3D, map_id: String) -> void:
	var path := "res://resources/recovered/actions/%s.json" % map_id.to_lower()
	if not FileAccess.file_exists(path):
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for entry: Dictionary in data.doors:
		var door := Door.new()
		level.add_child(door)
		door.initialize(entry)
		doors.append(door)
		_index(render_lookup, entry.render, door, entry.render_materials)
		_index(collision_lookup, entry.collision, door)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		_split_mesh(level, mesh)
	for collision: CollisionShape3D in model.find_children("*", "CollisionShape3D", true, false):
		if collision.shape is ConcavePolygonShape3D:
			_split_collision(level, collision)
	for door: Node3D in doors:
		if door.render_triangles == 0 or door.collision_triangles == 0:
			push_error("Recovered door %s/%s did not match its exported geometry" % [map_id, door.name])

func _index(lookup: Dictionary, triangles: Array, door: Node3D, materials: Array = []) -> void:
	if not lookup.has("coarse"):
		lookup["coarse"] = {}
	for triangle: int in range(triangles.size()):
		var values: Array = triangles[triangle]
		var points: Array[Vector3] = []
		for index: int in range(0, 9, 3):
			points.append(Vector3(values[index], values[index + 1], values[index + 2]))
		var key := _cell((points[0] + points[1] + points[2]) / 3.0)
		var coarse := Vector3i(((points[0] + points[1] + points[2]) / 3.0).floor())
		for x: int in [-1, 0, 1]:
			for y: int in [-1, 0, 1]:
				for z: int in [-1, 0, 1]:
					lookup.coarse[coarse + Vector3i(x, y, z)] = true
		if not lookup.has(key):
			lookup[key] = []
		lookup[key].append([door, points, materials[triangle] if not materials.is_empty() else ""])

func _cell(point: Vector3) -> Vector3i:
	return Vector3i((point * 100.0).round())

func _owner(lookup: Dictionary, points: Array[Vector3], tolerance: float = 0.001, material: String = "") -> Node3D:
	var center := (points[0] + points[1] + points[2]) / 3.0
	if not lookup.get("coarse", {}).has(Vector3i(center.floor())):
		return null
	var cell := _cell(center)
	# Rounding at cell boundaries can differ after glTF's float32 conversion.
	var candidates: Array = []
	var radius := maxi(1, ceili(tolerance * 100.0))
	for x: int in range(-radius, radius + 1):
		for y: int in range(-radius, radius + 1):
			for z: int in range(-radius, radius + 1):
				candidates.append_array(lookup.get(cell + Vector3i(x, y, z), []))
	for entry: Array in candidates:
		if material != "" and material != entry[2] and not material.begins_with(entry[2] + "_"):
			continue
		var matched := true
		for point: Vector3 in points:
			matched = matched and entry[1].any(func(v: Vector3) -> bool: return v.distance_squared_to(point) < tolerance * tolerance)
		if matched:
			return entry[0]
	return null

func _split_mesh(level: Node3D, instance: MeshInstance3D) -> void:
	if render_lookup.is_empty():
		return
	var original := instance.mesh
	# Godot packs imported render positions into 16-bit coordinates over the mesh
	# bounds. Collision remains full precision. Match render vertices within that
	# quantization error, restricted to their source material to spare nearby trim.
	var tolerance := maxf(0.001, original.get_aabb().size.length() * 2.0 / 65535.0)
	var replacement := ArrayMesh.new()
	var changed := false
	var local_to_map := level.global_transform.affine_inverse() * instance.global_transform
	for surface: int in range(original.get_surface_count()):
		var arrays := original.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		var groups := {0: PackedInt32Array()}
		var material := instance.get_active_material(surface)
		for index: int in range(0, indices.size(), 3):
			var corners: Array[Vector3] = [local_to_map * vertices[indices[index]], local_to_map * vertices[indices[index + 1]], local_to_map * vertices[indices[index + 2]]]
			var door := _owner(render_lookup, corners, tolerance, material.resource_name if material else "")
			var key: int = door.get_instance_id() if door else 0
			if not groups.has(key):
				groups[key] = PackedInt32Array()
			groups[key].append_array(indices.slice(index, index + 3))
		for key: int in groups:
			if groups[key].is_empty():
				continue
			if key == 0:
				var kept := arrays.duplicate()
				kept[Mesh.ARRAY_INDEX] = groups[key]
				replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, kept)
				replacement.surface_set_material(replacement.get_surface_count() - 1, material)
			else:
				changed = true
				var door: Node3D = instance_from_id(key)
				var leaf := MeshInstance3D.new()
				leaf.mesh = ArrayMesh.new()
				leaf.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _subset(arrays, groups[key]))
				leaf.mesh.surface_set_material(0, material)
				door.add_child(leaf)
				leaf.transform = door.closed.affine_inverse() * local_to_map
				door.render_triangles += groups[key].size() / 3
	if changed:
		for surface: int in range(instance.get_surface_override_material_count()):
			instance.set_surface_override_material(surface, null)
		instance.mesh = replacement if replacement.get_surface_count() else null

func _subset(source: Array, indices: PackedInt32Array) -> Array:
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	for slot: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if source[slot] == null or source[slot].is_empty():
			continue
		result[slot] = source[slot].slice(0, 0)
		var stride := 4 if slot == Mesh.ARRAY_TANGENT else 1
		for index: int in indices:
			for component: int in range(stride):
				result[slot].append(source[slot][index * stride + component])
	return result

func _split_collision(level: Node3D, collision: CollisionShape3D) -> void:
	var faces: PackedVector3Array = collision.shape.get_faces()
	var kept := PackedVector3Array()
	var groups: Dictionary = {}
	var to_map := level.global_transform.affine_inverse() * collision.global_transform
	for index: int in range(0, faces.size(), 3):
		var points: Array[Vector3] = [to_map * faces[index], to_map * faces[index + 1], to_map * faces[index + 2]]
		var door := _owner(collision_lookup, points)
		if door == null:
			kept.append_array(faces.slice(index, index + 3))
			continue
		if not groups.has(door):
			groups[door] = PackedVector3Array()
		for point: Vector3 in points:
			groups[door].append(door.closed.affine_inverse() * point)
	if groups.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(kept)
	collision.shape = shape
	for door: Node3D in groups:
		var leaf := CollisionShape3D.new()
		leaf.shape = ConcavePolygonShape3D.new()
		leaf.shape.backface_collision = true
		leaf.shape.set_faces(groups[door])
		door.add_child(leaf)
		door.collision_triangles += groups[door].size() / 3
		var low := Vector3.INF
		var high := -Vector3.INF
		for point: Vector3 in groups[door]:
			low = low.min(point)
			high = high.max(point)
		door.leaf_box = AABB(low, high - low)
