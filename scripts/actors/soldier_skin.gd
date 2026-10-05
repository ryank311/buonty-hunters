class_name SoldierSkin
extends Node3D
## The modelled soldier (art/models/soldier.glb), drawn in place of a SoldierProxy's blocks.
##
## The proxy still works out every pose. drive() copies its frames onto the model's
## bones each time it poses, so gait, stances, aiming, and the dive are unchanged; only
## what is drawn differs. limp() makes a second copy that follows a ragdoll's rigid
## bodies once the soldier is down.
##
## The model's rest pose is the proxy's upright layout with the arms lowered 45 degrees
## (art/blender/soldier.blend). Its limb lengths are the proxy's constants, so bones
## move without stretching the mesh.

const MODEL := "res://art/models/soldier.glb"
const SIDES: Array = [["L", "Left"], ["R", "Right"]]
## The boot block's centre, measured from its ankle.
const BOOT_FROM_ANKLE := Vector3(0, -0.04, -0.035)
## Which ragdoll body carries each bone, parents before children.
const CARRIERS: Array = [
	["Hips", "Torso"], ["Spine", "Torso"], ["Chest", "Torso"], ["Head", "Head"],
	["LeftUpperArm", "LUpperArm"], ["LeftLowerArm", "LForearm"], ["LeftHand", "LForearm"],
	["RightUpperArm", "RUpperArm"], ["RightLowerArm", "RForearm"], ["RightHand", "RForearm"],
	["LeftUpperLeg", "LThigh"], ["LeftLowerLeg", "LShin"], ["LeftFoot", "LShin"],
	["RightUpperLeg", "RThigh"], ["RightLowerLeg", "RShin"], ["RightFoot", "RShin"],
]
## Team tint leaves faces and hair alone.
const UNTINTED: Array = ["Skin", "Hair"]

var model: Node3D
var skeleton: Skeleton3D
var bone: Dictionary = {}
## Each bone's rest pose, and the proxy frame that goes with it, in the proxy's space.
var rest: Dictionary = {}
var frame_rest_inverse: Dictionary = {}
var to_skeleton := Transform3D.IDENTITY
## How each hand's bone (X across the knuckles, Y toward the fingers, Z out of the back
## of the hand) sits on the weapon: the right hand wraps the grip from behind with the
## thumb up, the left cups the handguard from below with the thumb forward.
var grip: Dictionary = {
	"L": Basis(Vector3(-0.7071, 0, -0.7071), Vector3(0.7071, 0, -0.7071), Vector3(0, -1, 0)),
	"R": Basis(Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)),
}
var carried: Array = []

## Dresses `proxy` in the model and hides its blocks. Returns null, leaving the blocks
## in place, when the model has not been imported.
static func wear(proxy: SoldierProxy) -> SoldierSkin:
	if not ResourceLoader.exists(MODEL):
		return null
	var skin := SoldierSkin.new()
	skin.name = "Skin"
	proxy.add_child(skin)
	if not skin._build():
		skin.free()
		return null
	for part: MeshInstance3D in proxy.parts.values():
		part.visible = false
	return skin

## Leaves a copy of `from` in `ragdoll`, in the same pose and colours, that goes limp
## with the ragdoll's `bodies`.
static func limp(from: SoldierSkin, ragdoll: Node3D, bodies: Dictionary) -> SoldierSkin:
	var skin := SoldierSkin.new()
	skin.name = "Skin"
	ragdoll.add_child(skin)
	if not skin._build():
		skin.free()
		return null
	skin.global_transform = from.global_transform
	var worn := from._meshes()
	var copies := skin._meshes()
	for index: int in range(copies.size()):
		for surface: int in range(copies[index].mesh.get_surface_count()):
			copies[index].set_surface_override_material(surface, worn[index].get_surface_override_material(surface))
	for index: int in range(skin.skeleton.get_bone_count()):
		skin.skeleton.set_bone_pose(index, from.skeleton.get_bone_pose(index))
	for entry: Array in CARRIERS:
		var body: RigidBody3D = bodies[entry[1]]
		var id: int = skin.bone[entry[0]]
		skin.carried.append([id, body, body.global_transform.affine_inverse() * skin.skeleton.global_transform * skin.skeleton.get_bone_global_pose(id)])
	skin.set_process(true)
	return skin

func _build() -> bool:
	set_process(false)
	var scene := load(MODEL) as PackedScene
	if scene == null:
		return false
	model = scene.instantiate() as Node3D
	add_child(model)
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return false
	skeleton = found[0]
	var offset := Transform3D.IDENTITY
	var node: Node3D = skeleton
	while node != self:
		offset = node.transform * offset
		node = node.get_parent()
	to_skeleton = offset.affine_inverse()
	for index: int in range(skeleton.get_bone_count()):
		var id := skeleton.get_bone_name(index)
		bone[id] = index
		rest[id] = offset * skeleton.get_bone_global_rest(index)
	var hip := Vector3(0, SoldierProxy.STANDING_HIP, 0)
	frame_rest_inverse["Hips"] = Transform3D(Basis.IDENTITY, -hip)
	frame_rest_inverse["Spine"] = Transform3D(Basis.IDENTITY, -hip)
	frame_rest_inverse["Chest"] = Transform3D(Basis.IDENTITY, -(hip + Vector3(0, 0.29, 0)))
	frame_rest_inverse["Head"] = Transform3D(Basis.IDENTITY, -(hip + Vector3(0.018, 0.63, -0.06)))
	for side: Array in SIDES:
		var leg: Array[Vector3] = [rest[side[1] + "UpperLeg"].origin, rest[side[1] + "LowerLeg"].origin, rest[side[1] + "Foot"].origin]
		var knee_out := _bend(leg[0], leg[1], leg[2])
		frame_rest_inverse[side[1] + "UpperLeg"] = _frame(leg[0], leg[1], knee_out).affine_inverse()
		frame_rest_inverse[side[1] + "LowerLeg"] = _frame(leg[1], leg[2], knee_out).affine_inverse()
		frame_rest_inverse[side[1] + "Foot"] = Transform3D(Basis.IDENTITY, -(leg[2] + BOOT_FROM_ANKLE))
		# The arms rest straight; their elbows point behind the body.
		var arm: Array[Vector3] = [rest[side[1] + "UpperArm"].origin, rest[side[1] + "LowerArm"].origin, rest[side[1] + "Hand"].origin]
		frame_rest_inverse[side[1] + "UpperArm"] = _frame(arm[0], arm[1], Vector3.BACK).affine_inverse()
		frame_rest_inverse[side[1] + "LowerArm"] = _frame(arm[1], arm[2], Vector3.BACK).affine_inverse()
	return true

## Poses the model from the proxy's current frames. Called at the end of SoldierProxy.pose().
func drive(proxy: SoldierProxy) -> void:
	var parts := proxy.parts
	var pelvis: Transform3D = parts.Pelvis.transform
	_carry("Hips", pelvis)
	_carry("Spine", parts.Abdomen.transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.10, 0)))
	_carry("Chest", parts.Torso.transform)
	_carry("Head", parts.Head.transform)
	for side: Array in SIDES:
		var arm: Array = proxy.arm_joints[side[0]]
		var elbow_out := _bend(arm[0], arm[1], arm[2])
		_carry(side[1] + "UpperArm", _frame(arm[0], arm[1], elbow_out))
		_carry(side[1] + "LowerArm", _frame(arm[1], arm[2], elbow_out))
		skeleton.set_bone_global_pose(bone[side[1] + "Hand"], to_skeleton * Transform3D(parts[side[0] + "Hand"].transform.basis * grip[side[0]], arm[2]))
		# The model's hips are set closer together than the proxy's, so each knee is
		# solved again from the model's own hip to the proxy's planted ankle.
		var leg: Array = proxy.leg_joints[side[0]]
		var knee_out := _bend(leg[0], leg[1], leg[2])
		var hip: Vector3 = pelvis * frame_rest_inverse["Hips"] * rest[side[1] + "UpperLeg"].origin
		var knee := SoldierProxy.solve_knee(hip, leg[2], knee_out)
		_carry(side[1] + "UpperLeg", _frame(hip, knee, knee_out))
		_carry(side[1] + "LowerLeg", _frame(knee, leg[2], knee_out))
		_carry(side[1] + "Foot", parts[side[0] + "Boot"].transform)

## Blends every cloth and gear colour toward `colour`, as the blocks are tinted by team.
func tint(colour: Color, amount: float) -> void:
	var swapped: Dictionary = {}
	for mesh: MeshInstance3D in _meshes():
		for surface: int in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if original == null or UNTINTED.has(original.resource_name):
				continue
			if not swapped.has(original):
				var copy := original.duplicate() as BaseMaterial3D
				copy.albedo_color = original.albedo_color.lerp(colour, amount)
				swapped[original] = copy
			mesh.set_surface_override_material(surface, swapped[original])

func _process(_delta: float) -> void:
	var inverse := skeleton.global_transform.affine_inverse()
	var moving := false
	for entry: Array in carried:
		var body: RigidBody3D = entry[1]
		if not is_instance_valid(body):
			set_process(false)
			return
		moving = moving or not body.freeze
		skeleton.set_bone_global_pose(entry[0], inverse * body.global_transform * entry[2])
	# A settled body no longer moves; its last pose stays.
	set_process(moving)

func _meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	meshes.assign(model.find_children("*", "MeshInstance3D", true, false))
	return meshes

## Moves a bone with a proxy frame: the bone keeps the place it has on that frame at rest.
func _carry(id: String, frame: Transform3D) -> void:
	skeleton.set_bone_global_pose(bone[id], to_skeleton * frame * frame_rest_inverse[id] * rest[id])

## A frame at `start` with Y along the limb and Z toward the side its joint bends out to.
static func _frame(start: Vector3, end: Vector3, bend: Vector3) -> Transform3D:
	var y := (end - start).normalized()
	var x := y.cross(bend)
	if x.length_squared() < 0.000001:
		x = y.cross(Vector3.BACK if absf(y.z) < 0.9 else Vector3.UP)
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), start)

## The direction a two-bone limb's middle joint sticks out from the line between its ends.
static func _bend(start: Vector3, middle: Vector3, end: Vector3) -> Vector3:
	var axis := (end - start).normalized()
	var out := middle - start
	return out - axis * out.dot(axis)
