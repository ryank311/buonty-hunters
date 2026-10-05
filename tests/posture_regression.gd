extends SceneTree

var failures: Array[String] = []
var checks := 0
var soldier: SoldierProxy

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func settle(stance: int = 0, speed: float = 0, direction: Vector2 = Vector2.UP, pitch: float = 0, focused: bool = false) -> void:
	for i: int in range(90):
		soldier.pose(stance, speed, direction, pitch, 0, 1.0/60.0, 1.0, Vector3.ZERO, true, 0, 0, focused)

func bone_matches(id: String, start: Vector3, end: Vector3) -> bool:
	var mesh: MeshInstance3D = soldier.parts[id]
	# Test actual visible mesh endpoints, not only the solver's joint positions.
	return (mesh.transform * Vector3(0,-0.5,0)).distance_to(start) < 0.0001 and (mesh.transform * Vector3(0,0.5,0)).distance_to(end) < 0.0001 and absf(mesh.basis.x.length() - 1) < 0.0001 and absf(mesh.basis.z.length() - 1) < 0.0001

func check_jumps() -> void:
	var connected := true
	var anatomical := true
	var grips := true
	var tucked := true
	var extended := true
	var planted := true
	var smooth := true
	var max_foot_step := 0.0
	for slot: int in [0,1]:
		soldier.set_weapon(slot)
		for speed: float in [0.0,4.5]:
			for direction: Vector2 in [Vector2.UP,Vector2.LEFT,Vector2.DOWN]:
				soldier.reset_pose()
				settle(0,speed,direction)
				soldier.begin_jump(5.0)
				var previous: Array[Vector3] = [soldier.parts.LBoot.position,soldier.parts.RBoot.position]
				for frame: int in range(34):
					soldier.pose(0,speed,direction,0,0,1.0/60.0,1.0,Vector3.ZERO,false,0,0,false,0,-1,0,0,5.0 - frame * 0.3)
					for index: int in range(2):
						var side := "L" if index == 0 else "R"
						var leg: Array = soldier.leg_joints[side]
						var arm: Array = soldier.arm_joints[side]
						var boot: MeshInstance3D = soldier.parts[side + "Boot"]
						max_foot_step = maxf(max_foot_step,previous[index].distance_to(boot.position))
						previous[index] = boot.position
						connected = connected and bone_matches(side + "Thigh",leg[0],leg[1]) and bone_matches(side + "Shin",leg[1],leg[2]) and (boot.transform * Vector3(0,0.04,0.035)).distance_to(leg[2]) < 0.001
						anatomical = anatomical and absf(leg[0].distance_to(leg[1]) - SoldierProxy.THIGH_LENGTH) < 0.001 and absf(leg[1].distance_to(leg[2]) - SoldierProxy.SHIN_LENGTH) < 0.001
						grips = grips and absf(arm[0].distance_to(arm[1]) - SoldierProxy.UPPER_ARM_LENGTH) < 0.001 and absf(arm[1].distance_to(arm[2]) - SoldierProxy.FOREARM_LENGTH) < 0.001 and soldier.parts[side + "Hand"].position.distance_to(arm[2]) < 0.001
						if frame == 17:
							tucked = tucked and boot.position.y > 0.26 and not soldier.foot_samples[side].contact
						if frame == 33:
							extended = extended and boot.position.y < 0.09
				soldier.land(5.0,1.0)
				for frame: int in range(30):
					soldier.pose(0,0,Vector2.ZERO,0,0,1.0/60.0)
					for side: String in ["L","R"]:
						var boot: MeshInstance3D = soldier.parts[side + "Boot"]
						var bottom := boot.position.y - absf(boot.basis.x.y)*0.09 - absf(boot.basis.y.y)*0.07 - absf(boot.basis.z.y)*0.145
						planted = planted and bottom >= -0.001
				smooth = smooth and soldier.body_drop < 0.01
	check(tucked and extended, "Standing, running and directional jumps tuck at the apex and extend before touchdown")
	check(connected and anatomical, "Jumping keeps visible boots and fixed-length legs connected")
	check(grips, "Rifle and pistol grips remain reachable throughout flight")
	check(max_foot_step < 0.13, "Jump foot trajectories stay continuous (max %.3f m/frame)" % max_foot_step)
	check(planted and smooth, "Landing boots clear the floor and the body recovers from impact")
	soldier.reset_pose()
	check(not soldier.jump_active and soldier.jump_blend == 0 and soldier.landing_compression == 0, "Respawn clears flight and landing animation")

func _run() -> void:
	soldier = SoldierProxy.new()
	root.add_child(soldier)
	settle()
	check(soldier.pose_points.head.z < soldier.pose_points.hip.z - 0.10, "Head and upper back sit forward of the hips in the ready stance")
	check(soldier.torso_pitch < -0.12 and soldier.torso_pitch > -0.21, "Standing posture uses a restrained forward hinge")
	check(soldier.foot_samples.L.ankle.z < soldier.foot_samples.R.ankle.z, "Ready stance places the support foot slightly ahead")
	check((soldier.weapon_pivot.transform * SoldierProxy.RIFLE_STOCK).distance_to(soldier.pose_points.stock) < 0.001, "Rifle butt rests against its shoulder anchor")
	check(absf(soldier.weapon_pivot.position.y - soldier.pose_points.shoulders[1].y) < 0.04, "Rifle is carried at shoulder height")
	var neutral_head: Vector3 = soldier.pose_points.head
	settle(0,0,Vector2.UP,0,true)
	check(soldier.pose_points.head.z < neutral_head.z - 0.02 and soldier.pose_points.head.y < neutral_head.y, "Focus aim brings the head forward and down toward the sights")
	settle(0,4.5)
	check(soldier.torso_pitch < -0.15 and soldier.torso_pitch > -0.21, "Jog keeps the upper body upright with a modest forward hinge")
	settle(1)
	check(soldier.pose_points.head.y < 1.0 and soldier.pose_points.chest.z < -0.17, "Crouch folds the torso over the hips within low-cover height")
	var front: Array = soldier.leg_joints.L
	var rear: Array = soldier.leg_joints.R
	var front_flex := 180.0 - rad_to_deg((front[0] - front[1]).angle_to(front[2] - front[1]))
	check(rear[1].y < 0.12 and rear[2].z > rear[0].z + 0.15, "A stopped crouch rests the right knee on the floor with its foot tucked behind")
	check(front_flex > 70.0 and front_flex < 115.0 and front[2].z < front[0].z - 0.3 and absf(soldier.foot_samples.L.pitch) < 0.001, "The left foot plants flat ahead under a roughly square knee")
	var heel_kick := 0.0
	var flight := false
	for tick: int in range(120):
		soldier.pose(0, 4.5, Vector2.UP, 0, 0, 1.0/60.0)
		flight = flight or not (soldier.foot_samples.L.contact or soldier.foot_samples.R.contact)
		for side: String in ["L", "R"]:
			var leg: Array = soldier.leg_joints[side]
			if leg[2].z > leg[0].z:
				heel_kick = maxf(heel_kick, leg[2].y)
	check(heel_kick > 0.3 and flight, "Jog folds the heel up behind the hip and has a flight phase (heel %.2f m)" % heel_kick)
	settle(1, 2.5)
	var lowest_knee := INF
	var highest_head := 0.0
	for tick: int in range(120):
		soldier.pose(1, 2.5, Vector2.UP, 0, 0, 1.0/60.0)
		highest_head = maxf(highest_head, soldier.pose_points.head.y)
		for side: String in ["L", "R"]:
			lowest_knee = minf(lowest_knee, soldier.leg_joints[side][1].y)
	check(lowest_knee > 0.2 and highest_head < 1.08, "Crouch walk steps with bent knees clear of the floor, head within crouch height (knee %.2f m, head %.2f m)" % [lowest_knee, highest_head])
	var mesh_ends := true
	var leg_lengths := true
	var arm_lengths := true
	var hands_attached := true
	var stock_attached := true
	var elbows_clear := true
	var maximum_arm_error := 0.0
	var worst_arm_pose := ""
	var lowest_elbow := INF
	var worst_elbow_pose := ""
	for slot: int in [0,1]:
		soldier.set_weapon(slot)
		for stance: int in [0,1,2]:
			for direction: Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
				for pitch: float in [deg_to_rad(-50),0.0,deg_to_rad(70)]:
					settle(stance,4.5 if stance == 0 else 2.5 if stance == 1 else 0.9,direction,pitch)
					for frame: int in range(24):
						var kick := 2.5 if frame < 8 else 0.0
						var draw := 1.0 if frame >= 16 else 0.0
						soldier.pose(stance,4.5 if stance == 0 else 2.5 if stance == 1 else 0.9,direction,pitch,0,1.0/60.0,1.0,Vector3.ZERO,true,kick,draw)
						for side: String in ["L","R"]:
							var leg: Array = soldier.leg_joints[side]
							var arm: Array = soldier.arm_joints[side]
							mesh_ends = mesh_ends and bone_matches(side + "Thigh",leg[0],leg[1]) and bone_matches(side + "Shin",leg[1],leg[2]) and bone_matches(side + "UpperArm",arm[0],arm[1]) and bone_matches(side + "Forearm",arm[1],arm[2])
							leg_lengths = leg_lengths and absf(leg[0].distance_to(leg[1])-SoldierProxy.THIGH_LENGTH) < 0.001 and absf(leg[1].distance_to(leg[2])-SoldierProxy.SHIN_LENGTH) < 0.001
							var error := maxf(absf(arm[0].distance_to(arm[1])-SoldierProxy.UPPER_ARM_LENGTH), absf(arm[1].distance_to(arm[2])-SoldierProxy.FOREARM_LENGTH))
							if error > maximum_arm_error:
								worst_arm_pose = "slot %d stance %d direction %s pitch %.2f kick %.1f draw %.1f side %s" % [slot,stance,direction,pitch,kick,draw,side]
							maximum_arm_error = maxf(error,maximum_arm_error)
							arm_lengths = arm_lengths and error < 0.001
							hands_attached = hands_attached and soldier.parts[side + "Hand"].position.distance_to(arm[2]) < 0.0001
							elbows_clear = elbows_clear and (stance != 2 or arm[1].y > 0.075)
							if stance == 2:
								if arm[1].y < lowest_elbow:
									worst_elbow_pose = "slot %d pitch %.2f kick %.1f draw %.1f side %s shoulder %s" % [slot,pitch,kick,draw,side,arm[0]]
								lowest_elbow = minf(lowest_elbow,arm[1].y)
						if slot == 0 and kick == 0 and draw == 0:
							stock_attached = stock_attached and (soldier.weapon_pivot.transform * SoldierProxy.RIFLE_STOCK).distance_to(soldier.pose_points.stock) < 0.001
	check(mesh_ends, "Visible arm and leg meshes meet their joints across stance, strafe, aim, recoil and draw")
	check(leg_lengths, "Leg lengths stay anatomical in standing, crouching and prone")
	check(arm_lengths, "Fixed arm lengths reach both weapons throughout all poses (maximum error %.5f m)" % maximum_arm_error)
	if not arm_lengths:
		print("Worst arm pose: ",worst_arm_pose)
	check(hands_attached, "Hands stay connected to wrists through weapon and crawl poses")
	check(stock_attached, "Rifle pitch pivots around the shoulder through the full look range")
	check(elbows_clear, "Prone elbows stay above the ground")
	if not elbows_clear:
		print("Lowest prone elbow: ",lowest_elbow," at ",worst_elbow_pose)
	soldier.set_weapon(0)
	settle()
	var smooth := true
	var connected := true
	var previous_head: Vector3 = soldier.pose_points.head
	var maximum_head_step := 0.0
	for stance: int in [1,2,0,2,1,0]:
		for frame: int in range(60):
			soldier.pose(stance,0,Vector2.ZERO,0,0,1.0/60.0)
			smooth = smooth and previous_head.distance_to(soldier.pose_points.head) < 0.33
			maximum_head_step = maxf(maximum_head_step,previous_head.distance_to(soldier.pose_points.head))
			previous_head = soldier.pose_points.head
			for side: String in ["L","R"]:
				var leg: Array = soldier.leg_joints[side]
				var ankle: Vector3 = soldier.parts[side + "Boot"].transform * Vector3(0,0.04,0.035)
				connected = connected and ankle.distance_to(leg[2]) < 0.001 and absf(leg[1].distance_to(leg[2])-SoldierProxy.SHIN_LENGTH) < 0.001
	check(smooth, "Standing/crouching/prone transitions blend without a full-pose snap (max %.3f m/frame)" % maximum_head_step)
	check(connected, "Boots, ankles and fixed-length legs stay connected during stance transitions")
	var winding := true
	for part: MeshInstance3D in soldier.parts.values():
		if not part.mesh is ArrayMesh:
			continue
		var arrays := part.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i: int in range(0,vertices.size(),3):
			winding = winding and (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).dot(normals[i]) < -0.0000001
	check(winding, "Faceted cloth meshes face outward with valid nondegenerate triangles")
	check_jumps()
	print("\nRESULT: %d checks, %d failure(s)" % [checks,failures.size()])
	soldier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
