class_name SoldierProxy
extends Node3D

const THIGH_LENGTH := 0.43
const SHIN_LENGTH := 0.42
const LEG_REACH := THIGH_LENGTH + SHIN_LENGTH - 0.001
const STANDING_HIP := 0.955
const CROUCH_HIP := 0.60
const KNEEL_HIP := 0.47
const RUN_HIP_DROP := 0.075
const UPPER_ARM_LENGTH := 0.31
const FOREARM_LENGTH := 0.29
const RIFLE_STOCK := Vector3(0, 0, 0.375)

var parts: Dictionary = {}
var weapon_pivot: Node3D
var muzzle: Marker3D
var flash: MeshInstance3D
var rifle_mesh: Node3D
var pistol_mesh: Node3D
var weapon_slot: int = 0
var cycle: float = 0.0
var blend: float = 0.0
var body_drop: float = 0.0
var landing_compression: float = 0.0
var gait_direction := Vector3.FORWARD
var locomotion_yaw: float = 0.0
var torso_yaw: float = 0.0
var leg_joints: Dictionary = {}
var foot_samples: Dictionary = {}
var stance_blend: float = 0.0
var prone_blend: float = 0.0
var focus_blend: float = 0.0
var torso_pitch: float = -0.15
var run_blend: float = 0.0
var step_blend: float = 0.0
var dive_blend: float = 0.0
var crawl_cycle: float = 0.0
var crawl_blend: float = 0.0
var strafe_phase: float = 0.0
var strafe_blend: float = 0.0
var strafe_side: float = 1.0
var strafe_reach: float = 0.0
var strafe_lift: float = 0.0
var jog_bounce: float = 0.0
var kneel_blend: float = 0.0
var hip_shift := Vector3.ZERO
var stride_contact: float = 0.58
var arm_joints: Dictionary = {}
var pose_points: Dictionary = {}

func _ready() -> void:
	var cloth := _material(Color("898874"))
	var gear := _material(Color("646a53"))
	var webbing := _material(Color("a7a386"))
	var skin := _material(Color("b5a080"))
	var dark := _material(Color("272d29"))
	# Faceted, tapered cloth volumes keep the proxy human at the play camera distance.
	_form("Torso", [Vector3(0.185,-0.18,0.135), Vector3(0.245,0.145,0.15), Vector3(0.20,0.225,0.12)], cloth)
	_form("Abdomen", [Vector3(0.18,-0.12,0.135), Vector3(0.175,0.12,0.13)], cloth)
	_form("Vest", [Vector3(0.195,-0.17,0.07), Vector3(0.24,0.12,0.075), Vector3(0.18,0.17,0.06)], gear)
	_form("Pack", [Vector3(0.16,-0.19,0.075), Vector3(0.195,-0.13,0.10), Vector3(0.175,0.17,0.09), Vector3(0.13,0.20,0.06)], gear)
	_form("Pelvis", [Vector3(0.18,-0.10,0.14), Vector3(0.20,0.08,0.14)], cloth)
	_form("Neck", [Vector3(0.062,-0.06,0.06), Vector3(0.067,0.06,0.062)], skin)
	_form("Head", [Vector3(0.075,-0.12,0.075), Vector3(0.105,-0.055,0.11), Vector3(0.113,0.065,0.115), Vector3(0.09,0.12,0.10)], skin, 10)
	_form("Helmet", [Vector3(0.14,-0.045,0.145), Vector3(0.125,0.05,0.13), Vector3(0.09,0.065,0.10)], cloth, 10)
	_form("HatBrim", [Vector3(0.195,-0.012,0.20), Vector3(0.195,0.012,0.20)], cloth, 10)
	_box("Belt", Vector3(0.39,0.06,0.30), gear)
	for i: int in range(3):
		_box("PackBand%d" % i, Vector3(0.34,0.032,0.018), webbing)
	for side: String in ["L", "R"]:
		_form(side + "Thigh", [Vector3(0.105,-0.5,0.115), Vector3(0.115,-0.25,0.12), Vector3(0.083,0.5,0.09)], cloth)
		_form(side + "Shin", [Vector3(0.084,-0.5,0.092), Vector3(0.085,-0.2,0.09), Vector3(0.065,0.5,0.07)], cloth)
		_box(side + "Boot", Vector3(0.18, 0.14, 0.29), dark)
		_form(side + "UpperArm", [Vector3(0.095,-0.5,0.10), Vector3(0.097,-0.25,0.105), Vector3(0.072,0.5,0.075)], cloth)
		_form(side + "Forearm", [Vector3(0.075,-0.5,0.078), Vector3(0.075,-0.25,0.08), Vector3(0.047,0.5,0.052)], cloth)
		_box(side + "Hand", Vector3(0.085,0.09,0.095), gear)
		_form(side + "Pouch", [Vector3(0.072,-0.105,0.066), Vector3(0.082,0.105,0.075)], gear)
		_box(side + "Strap", Vector3(0.046,0.32,0.024), webbing)
	weapon_pivot = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	add_child(weapon_pivot)
	rifle_mesh = Node3D.new()
	rifle_mesh.name = "Rifle"
	weapon_pivot.add_child(rifle_mesh)
	for data: Array in [
		[Vector3(0.10, 0.13, 0.42), Vector3(0, 0, 0)],
		[Vector3(0.08, 0.11, 0.23), Vector3(0, 0, 0.26)],
		[Vector3(0.035, 0.04, 0.30), Vector3(0, 0.015, -0.35)],
		[Vector3(0.07, 0.18, 0.10), Vector3(0, -0.13, 0.02)],
		[Vector3(0.06, 0.06, 0.09), Vector3(0, 0.09, -0.12)],
	]:
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = data[0]
		piece.mesh = mesh
		piece.material_override = dark
		piece.position = data[1]
		rifle_mesh.add_child(piece)
	pistol_mesh = Node3D.new()
	pistol_mesh.name = "Pistol"
	weapon_pivot.add_child(pistol_mesh)
	for data: Array in [
		[Vector3(0.075, 0.085, 0.23), Vector3(0, 0.015, -0.09)],
		[Vector3(0.065, 0.16, 0.075), Vector3(0, -0.09, -0.015)],
		[Vector3(0.025, 0.025, 0.08), Vector3(0, 0.015, -0.215)],
	]:
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = data[0]
		piece.mesh = mesh
		piece.material_override = dark
		piece.position = data[1]
		pistol_mesh.add_child(piece)
	muzzle = Marker3D.new()
	muzzle.position = Vector3(0, 0.015, -0.52)
	weapon_pivot.add_child(muzzle)
	flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.09
	flash_mesh.height = 0.18
	flash_mesh.radial_segments = 6
	flash_mesh.rings = 3
	flash.mesh = flash_mesh
	var glow := _material(Color("fff0a1"))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = glow
	flash.visible = false
	muzzle.add_child(flash)
	set_weapon(0)
	pose(0, 0, Vector2.ZERO, 0.0, 0.0, 1.0)

func set_weapon(slot: int) -> void:
	weapon_slot = slot
	rifle_mesh.visible = slot == 0
	pistol_mesh.visible = slot == 1
	muzzle.position = Vector3(0, 0.015, -0.52 if slot == 0 else -0.26)

func reset_pose() -> void:
	cycle = 0.0
	blend = 0.0
	body_drop = 0.0
	landing_compression = 0.0
	stance_blend = 0.0
	prone_blend = 0.0
	run_blend = 0.0
	step_blend = 0.0
	dive_blend = 0.0
	crawl_blend = 0.0
	crawl_cycle = 0.0
	strafe_phase = 0.0
	strafe_blend = 0.0
	strafe_reach = 0.0
	strafe_lift = 0.0
	jog_bounce = 0.0
	kneel_blend = 0.0
	focus_blend = 0.0
	locomotion_yaw = 0.0
	torso_yaw = 0.0
	gait_direction = Vector3.FORWARD
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	pose(0,0,Vector2.ZERO,0,0,1.0)

func land(impact_speed: float, weight: float) -> void:
	landing_compression = minf(impact_speed * 0.012, 0.09) * weight

static func solve_knee(hip: Vector3, ankle: Vector3, pole: Vector3 = Vector3.FORWARD) -> Vector3:
	# Anatomical two-bone solve; the standing hip height matches the combined leg length.
	# The pole follows the feet's facing direction, including locomotion turns.
	var axis := (ankle - hip).normalized()
	var distance := clampf(hip.distance_to(ankle), 0.02, LEG_REACH)
	var bend := pole - axis * pole.dot(axis)
	if bend.length_squared() < 0.0001:
		bend = Vector3.UP - axis * axis.y
	var along := (THIGH_LENGTH * THIGH_LENGTH - SHIN_LENGTH * SHIN_LENGTH + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, THIGH_LENGTH * THIGH_LENGTH - along * along))
	return hip + axis * along + bend.normalized() * height

static func sample_prone_strafe(phase: float) -> Dictionary:
	# Reach before translating, pull the torso to the planted hand/foot, then settle.
	# The speed curve integrates to one over a cycle, preserving the crawl speed.
	var reach: float
	var lift := 0.0
	var speed := 0.16
	if phase < 0.22:
		var progress := phase / 0.22
		reach = smoothstep(0.0, 1.0, progress)
		lift = sin(PI * progress)
	elif phase < 0.82:
		var pull := (phase - 0.22) / 0.60
		reach = 1.0 - smoothstep(0.0, 1.0, pull)
		speed += 2.8 * pow(sin(PI * pull), 2.0)
	else:
		reach = 0.0
	return {"reach":reach,"lift":lift,"speed":speed}

static func sample_step(phase: float, stride: float, contact: float, lift_height: float, facing: float = 1.0, jog: float = 0.0) -> Dictionary:
	# Heel contact -> flat support -> toe-off -> low swing -> heel contact.
	var travel: float
	var lift := 0.0
	var pitch := 0.0
	if phase < contact:
		var progress := phase / contact
		travel = lerpf(stride, -stride, progress)
		if progress < 0.18:
			pitch = lerpf(6.0, 0.0, smoothstep(0, 0.18, progress))
		elif progress > lerpf(0.8, 0.55, jog):
			pitch = lerpf(0.0, lerpf(-7.0,-20.0,jog), smoothstep(lerpf(0.8, 0.55, jog), 1.0, progress))
	else:
		var swing := (phase - contact) / (1.0 - contact)
		# A walk carries the foot through on a low arc. A jog first folds the heel up
		# behind the hip, then drives the knee through and reaches out to land.
		travel = lerpf(lerpf(-stride, stride, smoothstep(0, 1, swing)), lerpf(-stride, stride, smoothstep(0.16, 0.9, swing)), jog)
		lift = lerpf(sin(PI * swing), sin(PI * pow(swing, 0.7)), jog) * lift_height
		var jog_pitch := lerpf(-20.0, -48.0, smoothstep(0.0, 0.35, swing)) if swing < 0.35 else lerpf(-48.0, 6.0, smoothstep(0.35, 0.9, swing))
		pitch = lerpf(lerpf(-7.0, 6.0, smoothstep(0, 1, swing)), jog_pitch, jog)
	pitch = deg_to_rad(pitch * facing)
	# Keep the boot sole on the floor during contact, including its heel/toe rotation.
	var sole_height := absf(cos(pitch)) * 0.07 + absf(sin(pitch)) * 0.145
	return {"travel": travel, "lift": lift, "pitch": pitch, "sole_height": sole_height, "contact": phase < contact}

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material

func _box(id: String, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = id
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	add_child(part)
	parts[id] = part

func _form(id: String, rings: Array, material: Material, sides: int = 8) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[PackedVector3Array] = []
	for ring: Vector3 in rings:
		var row := PackedVector3Array()
		for i: int in range(sides):
			var angle := TAU * (i + 0.5) / sides
			row.append(Vector3(cos(angle) * ring.x, ring.y, sin(angle) * ring.z))
		points.append(row)
	for row: int in range(points.size() - 1):
		for i: int in range(sides):
			var next := (i + 1) % sides
			var a := points[row][i]
			var b := points[row + 1][i]
			var c := points[row + 1][next]
			var d := points[row][next]
			surface.set_normal((b - a).cross(c - a).normalized())
			for point: Vector3 in [a, d, c, a, c, b]:
				surface.add_vertex(point)
	for row: int in [0, points.size() - 1]:
		surface.set_normal(Vector3.DOWN if row == 0 else Vector3.UP)
		for i: int in range(sides):
			var next := (i + 1) % sides
			surface.add_vertex(Vector3(0, rings[row].y, 0))
			surface.add_vertex(points[row][next if row == 0 else i])
			surface.add_vertex(points[row][i if row == 0 else next])
	var part := MeshInstance3D.new()
	part.name = id
	part.mesh = surface.commit()
	part.material_override = material
	add_child(part)
	parts[id] = part

func _rig_part(id: String, frame: Transform3D, offset: Vector3) -> void:
	parts[id].transform = frame * Transform3D(Basis.IDENTITY, offset)

func _bone(id: String, start: Vector3, end: Vector3, amount: float) -> void:
	var part: MeshInstance3D = parts[id]
	var direction := end - start
	# Scale along the bone's local Y before rotating it into place. Basis.scaled()
	# scales world axes and visibly stretches bent limbs away from their own joints.
	var target := Transform3D(Basis(Quaternion(Vector3.UP, direction.normalized())) * Basis.from_scale(Vector3(1, direction.length(), 1)), (start + end) * 0.5)
	part.transform = part.transform.interpolate_with(target, amount)

func pose(stance: int, speed: float, movement: Vector2, aim_pitch: float, lean: float, delta: float, weight: float = 1.0, acceleration: Vector3 = Vector3.ZERO, grounded: bool = true, recoil_kick: float = 0.0, draw_amount: float = 0.0, focused: bool = false, dive: float = 0.0, crawl_phase: float = -1.0, lateral_intent: float = 0.0) -> void:
	var amount := 1.0 - exp(-16.0 * delta)
	blend = lerpf(blend, minf(speed / 4.5, 1.0) if grounded else 0.0, 1.0 - exp(-12.0 * delta))
	if movement.length() > 0.05:
		gait_direction = gait_direction.lerp(Vector3(movement.x, 0, movement.y).normalized(), amount)
	var crouching := stance == StanceController.Stance.CROUCH
	var prone := stance == StanceController.Stance.PRONE
	dive_blend = lerpf(dive_blend,dive,1.0 - exp(-20.0 * delta))
	run_blend = lerpf(run_blend,smoothstep(1.6,4.5,speed) if not crouching and not prone else 0.0,amount)
	step_blend = lerpf(step_blend,clampf(speed / 0.4,0,1) if grounded else 0.0,amount)
	crawl_blend = lerpf(crawl_blend,clampf(speed / 0.38,0,1) if prone and grounded and dive == 0 else 0.0,amount)
	crawl_cycle += speed * TAU / 0.5 * delta if prone and grounded else 0.0
	var strafe_intent := lateral_intent if crawl_phase >= 0.0 else (movement.normalized().x if speed > 0.02 else 0.0)
	var reversing := absf(strafe_intent) > 0.05 and strafe_side != signf(strafe_intent)
	if reversing and strafe_blend < 0.03:
		strafe_side = signf(strafe_intent)
		reversing = false
	strafe_blend = lerpf(strafe_blend,absf(strafe_intent) if prone and grounded and dive == 0 and not reversing else 0.0,amount)
	strafe_phase = crawl_phase if crawl_phase >= 0.0 else fposmod(strafe_phase + delta / 1.15,1.0)
	var strafe_pose := sample_prone_strafe(strafe_phase)
	strafe_reach = lerpf(strafe_reach,strafe_pose.reach,amount)
	strafe_lift = lerpf(strafe_lift,strafe_pose.lift,amount)
	stance_blend = lerpf(stance_blend, 1.0 if crouching else 0.0, amount)
	# A stopped crouch drops onto the right knee; any travel lifts straight back out of it.
	var kneeling := crouching and grounded and speed < 0.2 and dive == 0
	kneel_blend = lerpf(kneel_blend, 1.0 if kneeling else 0.0, 1.0 - exp(-(9.0 if kneeling else 16.0) * delta))
	prone_blend = lerpf(prone_blend, 1.0 if prone else 0.0, 1.0 - exp(-(22.0 if dive > 0 else 10.0) * delta))
	focus_blend = lerpf(focus_blend, 1.0 if focused else 0.0, amount)
	# Walks retain overlapping foot contact and a longer, slower stride. A jog has
	# shorter contact and a distinct cadence, instead of playing a tiny run at walking speed.
	# A crouch walk takes long, rolling, knee-bent steps rather than a quick squat shuffle.
	var walk_stride := lerpf(0.11,0.34,sqrt(clampf(speed / 1.6,0.0,1.0)))
	var crouch_stride := lerpf(0.14,0.40,sqrt(clampf(speed / 2.5,0.0,1.0)))
	var stride_span := lerpf(lerpf(walk_stride,0.40,run_blend),crouch_stride,stance_blend) * step_blend
	var plant_fraction := lerpf(lerpf(0.58,0.30,run_blend),0.46,stance_blend)
	var stride_style := maxf(run_blend,0.35 * stance_blend)
	stride_contact = plant_fraction
	# During contact, local foot travel cancels body travel instead of skating sideways.
	cycle += speed * TAU * plant_fraction / (2.0 * maxf(stride_span, 0.12)) * delta if grounded else 0.0
	var desired_yaw := 0.0
	if speed > 0.12 and not prone:
		desired_yaw = atan2(-movement.x, -movement.y)
		# Backpedal when moving behind the aim direction, rather than twisting 180°.
		if absf(desired_yaw) > PI * 0.5 + 0.01:
			desired_yaw = wrapf(desired_yaw + PI, -PI, PI)
	locomotion_yaw = lerp_angle(locomotion_yaw, desired_yaw, 1.0 - exp(-10.0 * delta))
	torso_yaw = lerp_angle(torso_yaw, clampf(desired_yaw * 0.65, -0.96, 0.96), 1.0 - exp(-8.0 * delta))
	var gait_basis := Basis(Vector3.UP, locomotion_yaw)
	hip_shift = gait_basis * Vector3(sin(cycle) * 0.012 * step_blend * weight,0,0)
	landing_compression *= exp(-13.0 * delta)
	var compression := (0.006 * (1.0 - cos(cycle * 2.0)) * blend + minf(acceleration.length() / 1500.0, 0.012)) * weight
	body_drop = lerpf(body_drop, compression + landing_compression, amount)
	# Two authored loading/push-off arcs per stride. Only the visual pelvis bounces;
	# the collision body and camera stay grounded and the aim remains steady.
	jog_bounce = (-0.035 + 0.09 * (0.5 - 0.5 * cos(cycle * 2.0 - TAU * 0.34))) * run_blend * weight
	var hip_height := lerpf(lerpf(STANDING_HIP - RUN_HIP_DROP * run_blend, CROUCH_HIP, stance_blend), KNEEL_HIP, kneel_blend) - body_drop + jog_bounce
	var feet: Array[Dictionary] = []
	var facing := 1.0 if gait_direction.dot(gait_basis * Vector3.FORWARD) >= 0 else -1.0
	for index: int in range(2):
		var sign_side := -1.0 if index == 0 else 1.0
		var phase := fposmod(cycle / TAU + index * 0.5, 1.0)
		# Backpedals keep the low walking arc; a heel kick reads wrong in front of the body.
		var step := sample_step(phase, stride_span, plant_fraction, lerpf(lerpf(0.024,0.22,run_blend),0.075,stance_blend) * step_blend, facing,stride_style if facing > 0 else 0.0)
		step.pitch *= step_blend
		step.sole_height = absf(cos(step.pitch)) * 0.07 + absf(sin(step.pitch)) * 0.145
		var foot_basis := gait_basis * Basis(Vector3.RIGHT, step.pitch)
		var boot_center: Vector3 = gait_basis * Vector3(sign_side * lerpf(0.155,0.11,run_blend), 0, -0.035) + gait_direction * step.travel
		# Left foot slightly ahead at rest, without a permanent deep bend at either knee.
		boot_center.z += sign_side * 0.025 * (1.0 - blend)
		boot_center.y = step.sole_height + step.lift
		if not grounded:
			boot_center.y += 0.06
		if kneel_blend > 0.0:
			# Kneel: the left boot plants flat ahead under a square knee; the right knee
			# rests on the floor with its toes tucked under, sole facing back.
			var kneel_pitch := 0.0 if index == 0 else deg_to_rad(-62.0)
			var kneel_basis := gait_basis * Basis(Vector3.UP, 0.14 if index == 0 else 0.0) * Basis(Vector3.RIGHT, kneel_pitch)
			var kneel_center := gait_basis * Vector3(-0.17 if index == 0 else 0.16, 0, -0.42 if index == 0 else 0.23)
			kneel_center.y = absf(kneel_basis.x.y) * 0.09 + absf(kneel_basis.y.y) * 0.07 + absf(kneel_basis.z.y) * 0.145
			var placed := Transform3D(foot_basis, boot_center).interpolate_with(Transform3D(kneel_basis, kneel_center), kneel_blend)
			foot_basis = placed.basis
			# Each foot steps clear of the floor while it moves between gait and kneel.
			boot_center = placed.origin + Vector3.UP * sin(PI * kneel_blend) * 0.06
			step.pitch = lerpf(step.pitch, kneel_pitch, kneel_blend)
		var ankle: Vector3 = boot_center + foot_basis * Vector3(0, 0.04, 0.035)
		var hip_horizontal := gait_basis * Vector3(sign_side * 0.14,0,0) + hip_shift
		var horizontal := Vector2(ankle.x, ankle.z) - Vector2(hip_horizontal.x,hip_horizontal.z)
		if not prone:
			# Lower the pelvis to accommodate a planted foot; never pull the ankle off the floor.
			hip_height = minf(hip_height, ankle.y + sqrt(maxf(0.01, LEG_REACH * LEG_REACH - horizontal.length_squared())))
		step["ankle"] = ankle
		step["boot"] = boot_center
		step["basis"] = foot_basis
		feet.append(step)
	for index: int in range(2):
		var side := "L" if index == 0 else "R"
		var sign_side := -1.0 if index == 0 else 1.0
		var hip := gait_basis * Vector3(sign_side * 0.14, hip_height, 0) + hip_shift
		var ankle: Vector3 = feet[index].ankle
		var crawl_stroke := sin(crawl_cycle + index * PI) * crawl_blend
		var prone_ankle := Vector3(sign_side * (0.22 + crawl_stroke * 0.025),0.11,0.875 + crawl_stroke * 0.07)
		var lead := sign_side == strafe_side
		var lateral_ankle := Vector3(sign_side * (0.22 + (0.23 * strafe_reach if lead else 0.03 * strafe_reach)),0.11 + (strafe_lift * 0.045 if lead else 0.0),0.875 - (0.14 * strafe_reach if lead else 0.0))
		prone_ankle = prone_ankle.lerp(lateral_ankle,strafe_blend)
		prone_ankle = prone_ankle.lerp(Vector3(sign_side * 0.145,0.23,0.955),dive_blend)
		var prone_hip := Vector3(sign_side * 0.14 + sin(crawl_cycle) * crawl_blend * 0.01,0.23,0.12)
		hip = hip.lerp(prone_hip,prone_blend)
		# The ankle and boot share a transform; no disconnected foot flick or toe hovering.
		var boot_frame := Transform3D(feet[index].basis,feet[index].boot)
		var prone_boot := Transform3D(Basis(Vector3.UP,PI),prone_ankle + Vector3(0,-0.04,0.035))
		parts[side + "Boot"].transform = boot_frame.interpolate_with(prone_boot,prone_blend)
		ankle = parts[side + "Boot"].transform * Vector3(0,0.04,0.035)
		var pole := (gait_basis * Vector3.FORWARD).lerp(Vector3(sign_side * 0.7,-0.15,0),prone_blend)
		var knee := solve_knee(hip,ankle,pole)
		feet[index].ankle = ankle
		leg_joints[side] = [hip, knee, ankle]
		foot_samples[side] = feet[index]
		_bone(side + "Thigh", hip, knee, 1.0)
		_bone(side + "Shin", knee, ankle, 1.0)
	_pose_upper_body(hip_height, aim_pitch, acceleration, weight, recoil_kick, draw_amount, amount)
	position.x = lerpf(position.x, lean * 0.16, amount)
	rotation.z = lerpf(rotation.z, -lean * 0.08 - clampf(acceleration.x * 0.002, -0.04, 0.04) * weight, amount)

func _pose_upper_body(hip_height: float, aim_pitch: float, acceleration: Vector3, weight: float, kick: float, draw: float, amount: float) -> void:
	# The waist follows travel. The shoulder girdle counter-turns to keep a shouldered rifle
	# reachable by both arms, especially when moving left across the aim direction.
	var gait_twist := sin(cycle) * step_blend * lerpf(0.035, 0.06, run_blend) * weight
	var waist_yaw := torso_yaw - 0.14 * (1.0 - blend) + gait_twist
	var shoulder_yaw := clampf(torso_yaw * 0.5 - 0.14 * (1.0 - blend) - gait_twist * 0.65, -0.62, 0.16)
	# A jog leans into the run; the kneel sits a little taller over the planted knee.
	var target_pitch := -lerpf(0.15 + 0.10 * run_blend + 0.035 * focus_blend, lerpf(0.66, 0.60, kneel_blend), stance_blend)
	target_pitch += clampf(acceleration.z * 0.002, -0.04, 0.04) * weight
	target_pitch += clampf(aim_pitch * 0.12, -0.06, 0.08)
	torso_pitch = lerpf(torso_pitch, target_pitch, amount)
	var sway := sin(cycle) * 0.008 * blend * weight * (1.0 - 0.5 * focus_blend)
	var spine := Transform3D(Basis(Vector3.UP, shoulder_yaw) * Basis(Vector3.RIGHT, torso_pitch), Vector3(sway, hip_height, 0) + hip_shift * 0.65)
	var pelvis := Transform3D(Basis(Vector3.UP, locomotion_yaw + gait_twist), Vector3(0, hip_height, 0) + hip_shift)
	var waist := Transform3D(Basis(Vector3.UP, waist_yaw) * Basis(Vector3.RIGHT, torso_pitch * 0.45), spine.origin)
	var crawl_sway := sin(crawl_cycle) * crawl_blend
	var side_load := strafe_side * strafe_reach * strafe_blend
	var prone_spine := Transform3D(Basis(Vector3.FORWARD,side_load * 0.07) * Basis(Vector3.UP,crawl_sway * 0.04) * Basis(Vector3.RIGHT,-PI / 2.0),Vector3(crawl_sway * 0.01 - side_load * 0.015,0.30 + strafe_reach * strafe_blend * 0.012,0.12))
	spine = spine.interpolate_with(prone_spine,prone_blend)
	pelvis = pelvis.interpolate_with(Transform3D(prone_spine.basis,Vector3(crawl_sway * 0.01,0.23,0.12)),prone_blend)
	waist = waist.interpolate_with(prone_spine,prone_blend)
	_rig_part("Pelvis", pelvis, Vector3.ZERO)
	_rig_part("Belt", pelvis, Vector3(0,0.06,0))
	_rig_part("Abdomen", waist, Vector3(0,0.10,0))
	var chest := spine * Transform3D(Basis.IDENTITY, Vector3(0,0.29,0))
	_rig_part("Torso", chest, Vector3.ZERO)
	_rig_part("Vest", chest, Vector3(0,0,-0.145))
	_rig_part("Pack", chest, Vector3(0,0.005,0.18))
	for i: int in range(3):
		_rig_part("PackBand%d" % i, chest, Vector3(0, -0.105 + i * 0.105, 0.274))
	for i: int in range(2):
		var side := "L" if i == 0 else "R"
		var sign_side := -1.0 if i == 0 else 1.0
		_rig_part(side + "Pouch", pelvis, Vector3(sign_side * 0.215, -0.10, 0.075))
		_rig_part(side + "Strap", chest, Vector3(sign_side * 0.145,0.015,-0.218))
	var head_point := spine * Vector3(0.018 + focus_blend * 0.018, 0.63 - stance_blend * 0.035, -0.06 - focus_blend * 0.02)
	head_point.y -= stance_blend * 0.055 + focus_blend * 0.008
	head_point.x = lerpf(head_point.x,0.025,prone_blend)
	head_point.y += 0.10 * prone_blend
	var head_frame := Transform3D(Basis(Vector3.UP, shoulder_yaw * 0.2) * Basis(Vector3.RIGHT, aim_pitch * 0.32 - 0.055), head_point)
	_rig_part("Neck", spine, Vector3(0,0.50,0))
	_rig_part("Head", head_frame, Vector3.ZERO)
	_rig_part("Helmet", head_frame, Vector3(0,0.135,0.006))
	_rig_part("HatBrim", head_frame, Vector3(0,0.09,0.006))
	var shoulders: Array[Vector3] = []
	for i: int in range(2):
		# Raised, forward shoulders shorten the exposed neck and keep the rifle high,
		# matching the compact upper-body silhouette in the supplied gameplay references.
		var shoulder := spine * Vector3(-0.235 if i == 0 else 0.235,0.49,-0.055)
		shoulder.y += 0.065 * prone_blend
		shoulders.append(shoulder)
	# Pivot pitch at the stock, rather than rotating a floating rifle around its center.
	var gun_pitch := aim_pitch + deg_to_rad(kick * (3.0 if weapon_slot == 0 else 7.0)) - draw * 0.5
	# A prone body cannot shoulder a barrel through the floor. The camera still chooses
	# the hitscan aim point; the muzzle ray continues to resolve near-ground obstruction.
	gun_pitch = lerpf(gun_pitch,clampf(gun_pitch,deg_to_rad(-8),deg_to_rad(45)),prone_blend)
	var gun_basis := Basis(Vector3.RIGHT, lerpf(gun_pitch,-0.03,dive_blend))
	var stock_point := shoulders[1] + Vector3(-0.025,-0.018,0.012)
	var gun_pos := stock_point - gun_basis * RIFLE_STOCK
	if weapon_slot == 1:
		gun_pos = (shoulders[0] + shoulders[1]) * 0.5 + gun_basis * Vector3(0.10,-0.035,-lerpf(0.38,0.20,draw))
	gun_pos += Vector3(0,-draw * lerpf(0.10 if weapon_slot == 0 else 0.18,0.025,prone_blend),kick * 0.03)
	# Stretch the weapon and both arms ahead during the airborne dive; on landing
	# the elbows return beneath the body and the rifle comes back into its prone hold.
	gun_pos = gun_pos.lerp(Vector3(0.06,0.31,-0.93),dive_blend)
	weapon_pivot.transform = Transform3D(gun_basis, gun_pos)
	for i: int in range(2):
		var side := "L" if i == 0 else "R"
		var sign_side := -1.0 if i == 0 else 1.0
		var grip := Vector3(-0.015,-0.075,-0.08) if i == 0 else Vector3(0,-0.105,0.10)
		if weapon_slot == 1:
			grip = Vector3(-0.035 if i == 0 else 0.0,-0.065,-0.005)
		var shoulder := shoulders[i]
		var hand := weapon_pivot.transform * grip
		# The support hand can slide back along the handguard when looking steeply up/down.
		if i == 0 and weapon_slot == 0:
			for adjustment: int in range(12):
				if shoulder.distance_to(hand) <= UPPER_ARM_LENGTH + FOREARM_LENGTH - 0.005:
					break
				grip.z += 0.02
				hand = weapon_pivot.transform * grip
		if sign_side == strafe_side:
			# The leading hand releases the gun, reaches sideways and plants. The
			# other hand keeps the weapon; the body catches up during the pull phase.
			var planted_hand := Vector3(shoulder.x + sign_side * (0.04 + strafe_reach * 0.23),0.075 + strafe_lift * 0.045,shoulder.z - 0.15)
			hand = hand.lerp(planted_hand,strafe_blend * prone_blend * (1.0 - dive_blend))
		var pole := Vector3(sign_side * 0.28,-1.0,0.08).lerp(Vector3(sign_side,-0.04,0.1),prone_blend)
		var elbow := solve_elbow(shoulder, hand, pole)
		arm_joints[side] = [shoulder, elbow, hand]
		_bone(side + "UpperArm", shoulder, elbow, 1.0)
		_bone(side + "Forearm", elbow, hand, 1.0)
		parts[side + "Hand"].transform = Transform3D(gun_basis, hand)
	pose_points = {"hip": pelvis.origin, "chest": chest.origin, "head": head_point, "stock": stock_point, "shoulders": shoulders}

static func solve_elbow(shoulder: Vector3, hand: Vector3, pole: Vector3) -> Vector3:
	var axis := (hand - shoulder).normalized()
	var distance := clampf(shoulder.distance_to(hand), 0.02, UPPER_ARM_LENGTH + FOREARM_LENGTH - 0.001)
	var bend := (pole - axis * pole.dot(axis)).normalized()
	var along := (UPPER_ARM_LENGTH * UPPER_ARM_LENGTH - FOREARM_LENGTH * FOREARM_LENGTH + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, UPPER_ARM_LENGTH * UPPER_ARM_LENGTH - along * along))
	return shoulder + axis * along + bend * height

func set_close_fade(close: bool) -> void:
	# Hide only the local proxy when the camera retracts into it.
	visible = not close
