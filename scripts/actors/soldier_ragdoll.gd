extends Node3D
## A limp physics body that takes over from a soldier's animated proxy when they die.
##
## build() copies the proxy's current pose into jointed rigid bodies (pelvis, chest,
## head, upper and lower limbs, and the dropped weapon), so the fall starts from exactly
## what was on screen. The killing blow shoves the whole body along its direction and
## strikes the part it hit harder: a head shot snaps the head back, a leg shot kicks
## the leg out from under the body, and a blast throws it away from the explosion.
## The body freezes in place once it comes to rest.

## 3D physics layer 4: collides with the world only, never with actors or shots.
const LAYER := 8
const SETTLE_SECONDS := 4.0
## Once the fall is over, a body slower than this everywhere is left lying where it is;
## joint limits pressed against the floor otherwise keep it squirming.
const REST_SPEED := 0.35
const KNEE_FLEX := 150.0
var bodies: Dictionary = {}
var surface := PhysicsMaterial.new()
var elapsed: float = 0.0
var settled: bool = false

## Describes a killing blow for build(): where it landed, which way it travelled, how
## hard, and whether it was a blast. `info` is what Combat.hurt() received.
static func impact(target: Node3D, info: Dictionary, damage: float) -> Dictionary:
	var centre := target.global_position + Vector3.UP * 1.0
	var position: Vector3 = info.get("position", centre)
	var direction := -target.global_basis.z
	var blast: bool = not info.get("regional", true)
	if info.has("origin"):
		direction = position - info.origin
	elif info.get("source") is Node3D and is_instance_valid(info.source):
		direction = position - (info.source.global_position + Vector3.UP * 1.4)
	if direction.length_squared() < 0.0001:
		direction = -target.global_basis.z
	return {"position": position, "direction": direction.normalized(), "blast": blast, "strength": clampf(damage / 34.0, 0.6, 3.0)}

func _ready() -> void:
	# Cloth and gear drag on the ground: no bounce, and enough grip that a body stops
	# where it drops instead of rolling or sliding across the floor.
	surface.friction = 1.0
	surface.rough = true
	surface.bounce = 0.0

## Replaces `proxy` with the ragdoll. `hit` comes from impact(); `carried` is the
## soldier's velocity at the moment of death.
func build(proxy: SoldierProxy, hit: Dictionary = {}, carried := Vector3.ZERO) -> void:
	var frame := proxy.global_transform
	var right := frame.basis.x.normalized()
	var up := frame.basis.y.normalized()
	var parts: Dictionary = proxy.parts
	# Pelvis and chest are one rigid torso. A separate pelvis caught between a waist joint
	# and both hips makes the joints fight, and some poses then never come to rest.
	var pelvis := _upright(parts.Pelvis.global_transform)
	var chest := _upright(parts.Torso.global_transform)
	_body("Torso", pelvis, [[_box(Vector3(0.36, 0.22, 0.26)), Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0))], [_box(Vector3(0.44, 0.56, 0.30)), pelvis.affine_inverse() * chest * Transform3D(Basis.IDENTITY, Vector3(0, -0.06, 0))]], 32.0, ["Pelvis", "Belt", "LPouch", "RPouch", "Abdomen", "Torso", "Vest", "Pack", "PackBand0", "PackBand1", "PackBand2", "LStrap", "RStrap", "Neck"], proxy)
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.12
	_body("Head", _upright(parts.Head.global_transform), [[head_shape, Transform3D.IDENTITY]], 5.0, ["Head", "Helmet", "HatBrim"], proxy)
	var joints: Dictionary = {}
	for side: String in ["L", "R"]:
		var arm: Array = proxy.arm_joints[side]
		var leg: Array = proxy.leg_joints[side]
		for i: int in range(3):
			joints[side + "arm%d" % i] = frame * arm[i]
			joints[side + "leg%d" % i] = frame * leg[i]
		_limb(side + "UpperArm", joints[side + "arm0"], joints[side + "arm1"], right, 0.055, 2.5, [side + "UpperArm"], proxy)
		_limb(side + "Forearm", joints[side + "arm1"], joints[side + "arm2"], right, 0.05, 2.0, [side + "Forearm", side + "Hand"], proxy)
		_limb(side + "Thigh", joints[side + "leg0"], joints[side + "leg1"], right, 0.075, 8.0, [side + "Thigh"], proxy)
		_limb(side + "Shin", joints[side + "leg1"], joints[side + "leg2"], right, 0.06, 5.0, [side + "Shin", side + "Boot"], proxy)
	_weapon(proxy)
	# The neck bends; shoulders and hips swing freely within anatomical cones.
	_cone("Torso", "Head", parts.Neck.global_position, up, 40.0, 45.0)
	for side: String in ["L", "R"]:
		_cone("Torso", side + "UpperArm", joints[side + "arm0"], joints[side + "arm1"] - joints[side + "arm0"], 80.0, 40.0)
		_cone(side + "UpperArm", side + "Forearm", joints[side + "arm1"], joints[side + "arm2"] - joints[side + "arm1"], 70.0, 30.0)
		_cone("Torso", side + "Thigh", joints[side + "leg0"], joints[side + "leg1"] - joints[side + "leg0"], 75.0, 35.0)
		# Knees only fold the shin backward, measured from straight.
		var flexed := rad_to_deg(bodies[side + "Thigh"].global_basis.y.angle_to(bodies[side + "Shin"].global_basis.y))
		_hinge(side + "Thigh", side + "Shin", joints[side + "leg1"], right, -flexed, KNEE_FLEX - flexed)
	if proxy.soldier_skin != null:
		# The modelled soldier goes limp on the bodies in place of copied blocks.
		SoldierSkin.limp(proxy.soldier_skin, self, bodies)
	_strike(hit, carried)

func _physics_process(delta: float) -> void:
	if settled:
		return
	elapsed += delta
	var resting := elapsed > 1.6
	# The fall plays out freely; after it, the limp body loses energy fast and lies still.
	var heavy := smoothstep(0.6, 1.4, elapsed)
	for body: RigidBody3D in bodies.values():
		body.linear_damp = lerpf(0.1, 8.0, heavy)
		body.angular_damp = lerpf(1.6, 12.0, heavy)
		resting = resting and (body.sleeping or body.linear_velocity.length() < REST_SPEED)
	if resting or elapsed > SETTLE_SECONDS:
		settle()

## Stops simulating and leaves the body where it lies.
func settle() -> void:
	settled = true
	for body: RigidBody3D in bodies.values():
		body.freeze = true

## Where the body ended up (the pelvis), for looting and spectating.
func rest_position() -> Vector3:
	return bodies.Torso.global_position if bodies.has("Torso") else global_position

func _strike(hit: Dictionary, carried: Vector3) -> void:
	for body: RigidBody3D in bodies.values():
		body.linear_velocity = carried
	if hit.is_empty():
		# No recorded blow: the knees give way and the body folds where it stands.
		for side: String in ["L", "R"]:
			bodies[side + "Thigh"].apply_central_impulse(-bodies.Torso.global_basis.z * 4.0)
		return
	var direction: Vector3 = hit.direction
	var strength: float = hit.strength
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	if hit.blast:
		# Lifted off the ground and thrown away from the explosion; the upper body is
		# pushed harder than the feet, so the body tumbles over rather than flying upright.
		var feet: float = bodies.Torso.global_position.y - 0.9
		for body: RigidBody3D in bodies.values():
			var height := clampf((body.global_position.y - feet) / 1.6, 0.0, 1.0)
			body.apply_central_impulse(body.mass * strength * (flat * lerpf(0.5, 1.6, height) + Vector3.UP * 1.1))
		return
	# The body staggers along the shot; the struck part takes a sharp hit of its own.
	for body: RigidBody3D in bodies.values():
		body.apply_central_impulse(flat * body.mass * 0.9)
	var struck := _nearest(hit.position)
	struck.apply_impulse(direction * 16.0 * strength, hit.position - struck.global_position)
	# The legs go out from under a limp body instead of toppling it like a plank.
	for side: String in ["L", "R"]:
		bodies[side + "Thigh"].apply_central_impulse(-flat * 3.0)

func _nearest(point: Vector3) -> RigidBody3D:
	var best: RigidBody3D = bodies.Torso
	var distance := INF
	for body: RigidBody3D in bodies.values():
		if body.name == "Weapon":
			continue
		var gap := body.global_position.distance_to(point)
		if gap < distance:
			distance = gap
			best = body
	return best

func _upright(source: Transform3D) -> Transform3D:
	return Transform3D(source.basis.orthonormalized(), source.origin)

func _box(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape

func _limb(id: String, start: Vector3, end: Vector3, right: Vector3, radius: float, mass: float, meshes: Array, proxy: SoldierProxy) -> void:
	var along := (end - start).normalized()
	var across := (right - along * right.dot(along)).normalized()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(start.distance_to(end), radius * 2.0 + 0.01)
	_body(id, Transform3D(Basis(across, along, across.cross(along)), (start + end) * 0.5), [[shape, Transform3D.IDENTITY]], mass, meshes, proxy)

## `shapes` holds [Shape3D, local Transform3D] pairs.
func _body(id: String, frame: Transform3D, shapes: Array, mass: float, meshes: Array, proxy: SoldierProxy) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = id
	body.collision_layer = LAYER
	body.collision_mask = 1
	body.mass = mass
	# Damped enough to read as dead weight rather than a flailing puppet.
	body.linear_damp = 0.1
	body.angular_damp = 1.6
	body.can_sleep = true
	body.physics_material_override = surface
	for entry: Array in shapes:
		var collider := CollisionShape3D.new()
		collider.shape = entry[0]
		collider.transform = entry[1]
		body.add_child(collider)
	for part: String in meshes if proxy.soldier_skin == null else []:
		var source: MeshInstance3D = proxy.parts[part]
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		copy.material_override = source.material_override
		copy.transform = frame.affine_inverse() * source.global_transform
		body.add_child(copy)
	add_child(body)
	body.global_transform = frame
	bodies[id] = body
	return body

func _weapon(proxy: SoldierProxy) -> void:
	var held := proxy.weapon_pivot
	var frame := _upright(held.global_transform)
	var pistol := proxy.weapon_slot == 1
	var body := _body("Weapon", frame, [[_box(Vector3(0.08, 0.16, 0.30 if pistol else 0.80)), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.08 if pistol else -0.12))]], 1.2 if pistol else 3.5, [], proxy)
	var copy := (proxy.pistol_mesh if pistol else proxy.rifle_mesh).duplicate() as Node3D
	body.add_child(copy)
	copy.global_transform = held.global_transform * copy.transform
	copy.visible = true

## A ball-and-socket joint whose twist axis follows `axis` (the child bone or spine).
func _cone(parent: String, child: String, at: Vector3, axis: Vector3, swing: float, twist: float) -> void:
	var joint := ConeTwistJoint3D.new()
	add_child(joint)
	joint.global_transform = Transform3D(_axis_basis(axis), at)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist))
	joint.node_a = joint.get_path_to(bodies[parent])
	joint.node_b = joint.get_path_to(bodies[child])

## A hinge about the body's left-right axis. Angles are degrees from the starting pose;
## positive folds the child forward over the parent (or the shin back under the thigh).
func _hinge(parent: String, child: String, at: Vector3, right: Vector3, lower: float, upper: float) -> void:
	var joint := HingeJoint3D.new()
	add_child(joint)
	var along: Vector3 = (bodies[parent].global_position - at).normalized()
	var across := (right - along * right.dot(along)).normalized()
	joint.global_transform = Transform3D(Basis(along.cross(across), along, across), at)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(lower))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(upper))
	joint.node_a = joint.get_path_to(bodies[parent])
	joint.node_b = joint.get_path_to(bodies[child])

func _axis_basis(axis: Vector3) -> Basis:
	var x := axis.normalized()
	var helper := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var z := x.cross(helper).normalized()
	return Basis(x, z.cross(x), z)
