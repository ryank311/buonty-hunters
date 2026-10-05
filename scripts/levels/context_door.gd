extends AnimatableBody3D
## A recovered door's leaf, original hinge and original relative swing.
var spec: Dictionary = {}
var closed := Transform3D.IDENTITY
var opened: bool = false
var busy: bool = false
var blocked: bool = false
var progress: float = 0.0
var from_rotation := Quaternion.IDENTITY
var to_rotation := Quaternion.IDENTITY
var leaf_box := AABB()
var render_triangles: int = 0
var collision_triangles: int = 0

func initialize(entry: Dictionary) -> void:
	spec = entry
	name = entry.node.validate_node_name()
	var m: Array = entry.world
	closed = Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14]))
	sync_to_physics = false
	transform = closed
	collision_layer = 1
	collision_mask = 0
	add_to_group("context_doors")
	opened = entry.initial != 0 and entry.initial != 99
	if opened:
		basis = closed.basis * Basis(_open_rotation())

func _open_rotation() -> Quaternion:
	var q: Array = spec.rotation
	return Quaternion(q[0], q[1], q[2], q[3]).normalized()

func offer(player: PrototypePlayer, point: Vector3) -> Dictionary:
	var offset := point - player.global_position
	if Vector2(offset.x, offset.z).length() > float(spec.range) or (float(spec.elevation) >= 0 and absf(offset.y) > float(spec.elevation)):
		return {}
	var locked: bool = spec.initial == 99 or (spec.team >= 0 and spec.team != player.get_meta("team", 0))
	var reason := "LOCKED" if locked else "DOOR BLOCKED" if blocked else "OPENING" if busy and opened else "CLOSING" if busy else ""
	return {"kind": "door", "target": self, "label": "CLOSE DOOR" if opened else "OPEN DOOR", "icon": spec.bitmap,
		"enabled": not locked and not busy, "reason": reason}

func activate() -> bool:
	if busy or spec.initial == 99:
		return false
	opened = not opened
	from_rotation = (closed.basis.inverse() * basis).get_rotation_quaternion()
	to_rotation = _open_rotation() if opened else Quaternion.IDENTITY
	progress = 0.0
	busy = true
	return true

func _physics_process(delta: float) -> void:
	if not busy:
		return
	var next := minf(1.0, progress + delta / maxf(float(spec.seconds), 0.05))
	var next_transform := Transform3D(closed.basis * Basis(from_rotation.slerp(to_rotation, next)), closed.origin)
	# Do not sweep the leaf through a soldier. The swing waits until they clear it.
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = leaf_box.size.max(Vector3(0.04, 0.04, 0.04))
	query.shape = box
	query.transform = get_parent().global_transform * next_transform * Transform3D(Basis.IDENTITY, leaf_box.get_center())
	query.collision_mask = 2
	query.exclude = [get_rid()]
	blocked = not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	if blocked:
		return
	progress = next
	transform = next_transform
	busy = progress < 1.0
