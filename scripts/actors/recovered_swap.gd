extends RefCounted
## Recovered draw/stow gestures follow combat's timer. They never change inventory.
var clip := ""
var time := 0.0
var progress := 0.0
var weight := 0.0
var reverse := false
var serial := -1
var drawing := false
var upper_only := false
var source_phase := 0.0
var start_phase := 0.0
var stance_name := "stand"
var last_pose: Array[Transform3D] = []

func reset() -> void:
	clip = ""
	time = 0.0
	progress = 0.0
	weight = 0.0
	serial = -1
	drawing = false
	reverse = false
	upper_only = false
	source_phase = 0.0
	start_phase = 0.0
	last_pose.clear()

func apply(motion: Node, pose: Array[Transform3D], weapon: PracticeWeapon, stance: int, moving: bool, grounded: bool, diving: bool, delta: float, blender: RefCounted) -> void:
	if weapon == null or weapon.profiles.is_empty() or weapon.draw_from == null or diving:
		reset()
		return
	var previous_clip := clip
	var previous_phase := source_phase
	var previous_reverse := reverse
	var previous_weight := weight
	var interrupted := drawing
	var new_draw := serial != weapon.draw_serial
	if new_draw:
		reset()
		serial = weapon.draw_serial
	drawing = weapon.draw_remaining > 0.0
	stance_name = ["stand", "crouch", "prone"][stance]
	if drawing:
		var source := weapon.draw_from
		var target := weapon.profile
		var from_gun := source.kind == "firearm"
		var to_gun := target.kind == "firearm"
		reverse = false
		if from_gun and to_gun and source.hold != target.hold:
			clip = "seal_" + ("prone_" if stance == 2 else "mv_" if moving or not grounded else "crouch_" if stance == 1 else "") + "rifle2pistol"
			reverse = source.hold == "pistol"
		elif from_gun != to_gun:
			clip = "seal_rifle2handsfree" if (source.hold if from_gun else target.hold) == "long" else "seal_pistol2handsfree"
			reverse = to_gun
		elif from_gun and source.hold == "long":
			clip = "seal_swaprifle"
		else:
			reset()
			return
		if new_draw:
			start_phase = 1.0 if reverse else 0.0
			if interrupted and reverse != previous_reverse and (clip == previous_clip or ("rifle2pistol" in clip and "rifle2pistol" in previous_clip)):
				# Reverse where the hand is now, not at the other end of the take.
				start_phase = previous_phase
				weight = previous_weight
		# Pose is evaluated before combat ticks its draw timer this frame.
		progress = clampf(1.0 - maxf(0.0, weapon.draw_remaining - delta) / maxf(target.draw_seconds, 0.001), 0.0, 1.0)
		source_phase = lerpf(start_phase, 0.0 if reverse else 1.0, progress)
		time = source_phase * (motion.get_animation(clip).length - 1.0 / 30.0)
		last_pose = motion.sample(clip, time)
		upper_only = moving or not grounded or "handsfree" in clip or (clip == "seal_swaprifle" and stance != 0)
		weight = minf(1.0, weight + delta / 0.05)
	else:
		weight = maxf(0.0, weight - delta / 0.08)
	if weight > 0.0 and not last_pose.is_empty():
		# Starting to walk during the blend-out must also keep the live leg cycle.
		blender.blend_pose(motion, pose, last_pose, weight, upper_only or moving or not grounded, clip)
		if weapon.profile.kind == "firearm":
			blender.socket = blender.socket.interpolate_with(grip(motion, weapon.profile.hold == "pistol"), weight)
	else:
		clip = ""

## The swap's spare weapon tracks move away from the hand (especially prone).
## Keep a visible weapon on the existing held-weapon grip, then hide it when stowed.
func grip(motion: Node, pistol: bool) -> Transform3D:
	return motion.weapon_track(("seal_p_" if pistol else "seal_") + stance_name, 0.0, "pistol" if pistol else "rifle")

## Show each firearm only during its part of the take.
func show_weapons(skin: SoldierSkin, proxy: SoldierProxy, weapon: PracticeWeapon) -> void:
	if not drawing or clip == "":
		return
	var hand: Transform3D = skin.motion.native_worlds[skin.motion.rig.names.find("rhand")]
	if "rifle2pistol" in clip:
		proxy.rifle_mesh.visible = source_phase < 0.53
		proxy.pistol_mesh.visible = source_phase >= 0.68
		weapon.held_item.visible = false
	elif "handsfree" in clip:
		var long_gun := clip == "seal_rifle2handsfree"
		proxy.rifle_mesh.visible = long_gun and source_phase < 0.8
		proxy.pistol_mesh.visible = not long_gun and source_phase < 0.8
		weapon.held_item.visible = false
	elif clip == "seal_swaprifle":
		proxy.rifle_mesh.visible = true
		proxy.pistol_mesh.visible = false
	for pistol: bool in [false, true]:
		var mesh: Node3D = proxy.pistol_mesh if pistol else proxy.rifle_mesh
		if not mesh.visible:
			continue
		var attachment: Transform3D = hand * grip(skin.motion, pistol)
		mesh.transform = proxy.weapon_pivot.transform.affine_inverse() * attachment * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
