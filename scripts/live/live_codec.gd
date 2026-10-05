extends RefCounted
## Turns engine values into JSON for the live link and back, and reads or writes a
## property by a dotted path such as "weapon.profile.damage" or "velocity.y".
##
## Vectors travel as [x, y, z], colours as "#rrggbbaa", transforms as
## {"origin": [...], "euler_deg": [...]}. Nodes, resources, and other objects are named
## rather than copied; a resource or plain object is opened one level when asked.

const MAX_ITEMS := 64
const LIST_TYPES: Array[int] = [TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY]
## The parts of a value type that a path may step into.
const PARTS: Dictionary = {
	TYPE_VECTOR2: ["x", "y"], TYPE_VECTOR2I: ["x", "y"],
	TYPE_VECTOR3: ["x", "y", "z"], TYPE_VECTOR3I: ["x", "y", "z"],
	TYPE_VECTOR4: ["x", "y", "z", "w"], TYPE_QUATERNION: ["x", "y", "z", "w"],
	TYPE_COLOR: ["r", "g", "b", "a"],
	TYPE_TRANSFORM3D: ["origin", "basis"], TYPE_BASIS: ["x", "y", "z"],
	TYPE_TRANSFORM2D: ["origin", "x", "y"],
}

static func encode(value: Variant, depth: int = 1) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			return _number(value)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [_number(value.x), _number(value.y)]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [_number(value.x), _number(value.y), _number(value.z)]
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_QUATERNION:
			return [_number(value.x), _number(value.y), _number(value.z), _number(value.w)]
		TYPE_COLOR:
			return "#" + value.to_html()
		TYPE_BASIS:
			return {"euler_deg": _degrees(value.get_euler())}
		TYPE_TRANSFORM3D:
			return {"origin": encode(value.origin), "euler_deg": _degrees(value.basis.get_euler())}
		TYPE_TRANSFORM2D:
			return {"origin": encode(value.origin), "rotation_deg": _number(rad_to_deg(value.get_rotation()))}
		TYPE_RECT2, TYPE_RECT2I:
			return [_number(value.position.x), _number(value.position.y), _number(value.size.x), _number(value.size.y)]
		TYPE_AABB:
			return {"position": encode(value.position), "size": encode(value.size)}
		TYPE_PLANE:
			return [_number(value.normal.x), _number(value.normal.y), _number(value.normal.z), _number(value.d)]
		TYPE_DICTIONARY:
			var entries: Dictionary = {}
			for key: Variant in value:
				if entries.size() >= MAX_ITEMS:
					entries["..."] = "%d more" % (value.size() - MAX_ITEMS)
					break
				entries[str(key)] = encode(value[key], depth - 1)
			return entries
		TYPE_OBJECT:
			return _object(value, depth)
	if typeof(value) in LIST_TYPES:
		var items: Array = []
		for index: int in range(mini(value.size(), MAX_ITEMS)):
			items.append(encode(value[index], depth - 1))
		if value.size() > MAX_ITEMS:
			items.append("... %d more" % (value.size() - MAX_ITEMS))
		return items
	return str(value)

## Every script variable of an object, encoded. Engine properties are left out; ask for
## those by name.
static func script_values(object: Object, depth: int = 1) -> Dictionary:
	var values: Dictionary = {}
	for property: Dictionary in object.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = encode(object.get(property.name), depth)
	return values

static func title(object: Object) -> String:
	var script: Variant = object.get_script()
	if script is Script and script.resource_path != "":
		return script.resource_path.get_file().get_basename()
	return object.get_class()

## Shapes a JSON value like `like`, the value it is about to replace.
## Returns [true, value] or [false, reason].
static func decode(value: Variant, like: Variant) -> Array:
	var wanted := typeof(like)
	match wanted:
		TYPE_BOOL:
			return [true, bool(value)] if value is bool or value is float or value is int else _refuse(value, "true or false")
		TYPE_INT:
			return [true, int(value)] if value is float or value is int or value is bool else _refuse(value, "a whole number")
		TYPE_FLOAT:
			return [true, float(value)] if value is float or value is int else _refuse(value, "a number")
		TYPE_STRING:
			return [true, str(value)]
		TYPE_STRING_NAME:
			return [true, StringName(str(value))]
		TYPE_NODE_PATH:
			return [true, NodePath(str(value))]
		TYPE_VECTOR2:
			return [true, Vector2(value[0], value[1])] if _numbers(value, 2) else _refuse(value, "[x, y]")
		TYPE_VECTOR2I:
			return [true, Vector2i(int(value[0]), int(value[1]))] if _numbers(value, 2) else _refuse(value, "[x, y]")
		TYPE_VECTOR3:
			return [true, Vector3(value[0], value[1], value[2])] if _numbers(value, 3) else _refuse(value, "[x, y, z]")
		TYPE_VECTOR3I:
			return [true, Vector3i(int(value[0]), int(value[1]), int(value[2]))] if _numbers(value, 3) else _refuse(value, "[x, y, z]")
		TYPE_VECTOR4:
			return [true, Vector4(value[0], value[1], value[2], value[3])] if _numbers(value, 4) else _refuse(value, "[x, y, z, w]")
		TYPE_QUATERNION:
			return [true, Quaternion(value[0], value[1], value[2], value[3])] if _numbers(value, 4) else _refuse(value, "[x, y, z, w]")
		TYPE_COLOR:
			if value is String and Color.html_is_valid(value):
				return [true, Color.html(value)]
			if _numbers(value, 3):
				return [true, Color(value[0], value[1], value[2], value[3] if value.size() > 3 else 1.0)]
			return _refuse(value, "\"#rrggbb\" or [r, g, b, a]")
		TYPE_BASIS:
			var angles: Variant = value.get("euler_deg") if value is Dictionary else value
			return [true, Basis.from_euler(_radians(angles))] if _numbers(angles, 3) else _refuse(value, "{\"euler_deg\": [x, y, z]}")
		TYPE_TRANSFORM3D:
			if value is Dictionary and _numbers(value.get("origin"), 3):
				var turned: Variant = value.get("euler_deg")
				var basis: Basis = Basis.from_euler(_radians(turned)) if _numbers(turned, 3) else like.basis
				return [true, Transform3D(basis, Vector3(value.origin[0], value.origin[1], value.origin[2]))]
			return _refuse(value, "{\"origin\": [x, y, z], \"euler_deg\": [x, y, z]}")
	if wanted in LIST_TYPES:
		if not value is Array:
			return _refuse(value, "a list")
		# assign() converts each element, so a typed or packed array keeps its type.
		var list: Variant = like.duplicate()
		list.assign(whole_numbers(value) if wanted in [TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_BYTE_ARRAY] else value)
		return [true, list]
	# No type to go by (null, an object, a dictionary): take the value as it came, loading
	# a resource when it is named by path.
	if value is String and (value.begins_with("res://") or value.begins_with("uid://")) and (wanted == TYPE_OBJECT or wanted == TYPE_NIL):
		var resource := ResourceLoader.load(value)
		return [true, resource] if resource != null else [false, "cannot load '%s'" % value]
	return [true, whole_numbers(value)]

## JSON has one number type. Where nothing says otherwise, 3.0 means 3.
static func whole_numbers(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(whole_numbers(item))
		return items
	if value is Dictionary:
		var copy: Dictionary = {}
		for key: Variant in value:
			copy[key] = whole_numbers(value[key])
		return copy
	return value

## Follows a dotted path from `root`. Returns [true, value] or [false, reason].
static func read_path(root: Variant, path: String) -> Array:
	var current: Variant = root
	for key: String in path.split(".", false):
		var step := _child(current, key)
		if not step[0]:
			return step
		current = step[1]
	return [true, current]

## Sets the value at a dotted path, converting it to the type already there.
## Returns [true, before, after] or [false, reason].
static func write_path(root: Object, path: String, value: Variant) -> Array:
	var keys := path.split(".", false)
	if keys.is_empty():
		return [false, "empty property path"]
	var chain: Array = [root]
	for index: int in range(keys.size() - 1):
		var step := _child(chain[index], keys[index])
		if not step[0]:
			return step
		chain.append(step[1])
	var before := _child(chain.back(), keys[keys.size() - 1])
	if not before[0]:
		return before
	var decoded := decode(value, before[1])
	if not decoded[0]:
		return [false, "%s: %s" % [path, decoded[1]]]
	# A vector or a transform is a copy, so the changed copy is written back into its
	# owner, and that into its owner, until an object takes it.
	var carry: Variant = decoded[1]
	for index: int in range(chain.size() - 1, -1, -1):
		var container: Variant = chain[index]
		if container is Object:
			container.set(keys[index], carry)
			break
		carry = _with(container, keys[index], carry)
	var after := read_path(root, path)
	return [true, before[1], after[1] if after[0] else null]

static func _child(container: Variant, key: String) -> Array:
	if container is Object:
		if not is_instance_valid(container):
			return [false, "'%s' is on an object that no longer exists" % key]
		if key in container:
			return [true, container.get(key)]
		return [false, "%s has no property '%s'" % [title(container), key]]
	if container is Dictionary:
		for candidate: Variant in container:
			if str(candidate) == key:
				return [true, container[candidate]]
		return [false, "no key '%s'" % key]
	if typeof(container) in LIST_TYPES:
		if not key.is_valid_int() or key.to_int() < 0 or key.to_int() >= container.size():
			return [false, "no item '%s' in a list of %d" % [key, container.size()]]
		return [true, container[key.to_int()]]
	if key in PARTS.get(typeof(container), []):
		return [true, container[key]]
	return [false, "cannot read '%s' in a %s" % [key, type_string(typeof(container))]]

static func _with(container: Variant, key: String, value: Variant) -> Variant:
	if container is Dictionary:
		for candidate: Variant in container:
			if str(candidate) == key:
				container[candidate] = value
				return container
	elif typeof(container) in LIST_TYPES:
		container[key.to_int()] = value
	else:
		container[key] = value
	return container

static func _object(value: Object, depth: int) -> Variant:
	if not is_instance_valid(value):
		return null
	if value is Node:
		return {"node": str(value.get_path()) if value.is_inside_tree() else str(value.name), "class": title(value)}
	var named: Dictionary = {"resource" if value is Resource else "object": title(value)}
	if value is Resource and value.resource_path != "":
		named["path"] = value.resource_path
	if depth > 0:
		named["values"] = script_values(value, depth - 1)
	return named

static func _number(value: float) -> Variant:
	# JSON has no NaN or infinity.
	return snappedf(value, 0.00001) if is_finite(value) else str(value)

static func _degrees(radians: Vector3) -> Array:
	return [_number(rad_to_deg(radians.x)), _number(rad_to_deg(radians.y)), _number(rad_to_deg(radians.z))]

static func _radians(degrees: Variant) -> Vector3:
	return Vector3(deg_to_rad(degrees[0]), deg_to_rad(degrees[1]), deg_to_rad(degrees[2]))

static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() < count:
		return false
	for index: int in range(count):
		if not (value[index] is float or value[index] is int):
			return false
	return true

static func _refuse(value: Variant, wanted: String) -> Array:
	return [false, "expected %s, got %s" % [wanted, JSON.stringify(value)]]
