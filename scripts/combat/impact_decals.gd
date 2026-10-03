class_name ImpactDecals
extends Node

# Surface meshes avoid the Mobile renderer's eight projected decals per mesh limit.
# They share one small texture/material and never participate in collision queries.
const MAX_MARKS := 128
const SURFACE_OFFSET := 0.0015
const TEXTURE := preload("res://art/decals/bullet_impact.svg")
var marks: Array[MeshInstance3D] = []
var material := StandardMaterial3D.new()
var rng := RandomNumberGenerator.new()

func _init() -> void:
	material.albedo_texture = TEXTURE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	rng.randomize()

func clear() -> void:
	for mark: MeshInstance3D in marks:
		if is_instance_valid(mark):
			mark.queue_free()
	marks.clear()

func add_impact(hit: Dictionary, diameter: float) -> MeshInstance3D:
	var collider: Object = hit.get("collider")
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if not is_instance_valid(collider) or not collider is Node3D or normal.length_squared() < 0.5 or not hit.has("position"):
		return null
	normal = normal.normalized()
	var point: Vector3 = hit.position
	var reference := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var right := reference.cross(normal).normalized()
	var up := normal.cross(right).normalized()
	var orientation := Basis(normal, rng.randf() * TAU) * Basis(right, up, normal)
	var size := maxf(0.01, diameter) * rng.randf_range(0.9, 1.1)
	var surface := Transform3D(orientation, point)
	var mesh := _surface_mesh(surface, size, _hit_box(collider, hit))
	if mesh == null:
		return null
	# Removing destroyed surfaces also removes their marks; prune stale handles lazily.
	for index: int in range(marks.size() - 1, -1, -1):
		if not is_instance_valid(marks[index]) or marks[index].is_queued_for_deletion():
			marks.remove_at(index)
	while marks.size() >= MAX_MARKS:
		var oldest := marks.pop_front() as MeshInstance3D
		oldest.queue_free()
	var mark := MeshInstance3D.new()
	mark.name = "BulletImpact"
	mark.mesh = mesh
	mark.material_override = material
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mark.add_to_group("bullet_impacts")
	# A local transform on the actual collider carries the mark with moving surfaces.
	collider.add_child(mark)
	surface.origin += normal * SURFACE_OFFSET
	mark.global_transform = surface
	marks.append(mark)
	return mark

func _hit_box(collider: Object, hit: Dictionary) -> CollisionShape3D:
	if not collider is CollisionObject3D or not hit.has("shape"):
		return null
	var owner_id: int = collider.shape_find_owner(hit.shape)
	var owner: Object = collider.shape_owner_get_owner(owner_id)
	if owner is CollisionShape3D and owner.shape is BoxShape3D:
		return owner
	return null

func _surface_mesh(surface: Transform3D, diameter: float, box: CollisionShape3D) -> ArrayMesh:
	var polygon: Array[Dictionary] = []
	for uv: Vector2 in [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]:
		var local := Vector3((uv.x - 0.5) * diameter, (0.5 - uv.y) * diameter, 0)
		polygon.append({"point": surface * local, "uv": uv})
	# Clip to the struck box so marks on cover edges don't hang in space or wrap onto its back.
	if box:
		var inverse := box.global_transform.affine_inverse()
		var half: Vector3 = box.shape.size * 0.5
		for axis: int in range(3):
			for sign_side: float in [-1.0, 1.0]:
				polygon = _clip_plane(polygon, inverse, axis, sign_side, half[axis] + 0.00005)
				if polygon.size() < 3:
					return null
	var local_space := surface.affine_inverse()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for index: int in range(1, polygon.size() - 1):
		for vertex: Dictionary in [polygon[0], polygon[index], polygon[index + 1]]:
			vertices.append(local_space * vertex.point)
			normals.append(Vector3.BACK)
			uvs.append(vertex.uv)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _clip_plane(polygon: Array[Dictionary], inverse: Transform3D, axis: int, side: float, limit: float) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if polygon.is_empty():
		return output
	var previous: Dictionary = polygon.back()
	var previous_distance: float = (inverse * previous.point)[axis] * side - limit
	for current: Dictionary in polygon:
		var distance: float = (inverse * current.point)[axis] * side - limit
		if (distance <= 0.0) != (previous_distance <= 0.0):
			var fraction := previous_distance / (previous_distance - distance)
			output.append({"point": previous.point.lerp(current.point, fraction), "uv": previous.uv.lerp(current.uv, fraction)})
		if distance <= 0.0:
			output.append(current)
		previous = current
		previous_distance = distance
	return output
