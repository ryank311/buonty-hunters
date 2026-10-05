extends RefCounted
## Native HUD pixels, original reader tables and ELF equations (research 84).
## World velocity is converted from metres to the source's decimetres.
const HALF_HFOV := 0.6109
const TANGENT := Vector2(tan(tan(HALF_HFOV)) / 320.0, tan(tan(HALF_HFOV) * 448.0 / 640.0) / 224.0)
var profile: WeaponProfile
var stance: int = 0
var size: float = 0.0
var knock := Vector2.ZERO
var sway := Vector2.ZERO
var sway_sign := Vector2.ONE
var exertion: float = 1.0
var scope_kick: float = 0.0
var kick_target: float = 0.0
var kick_rising: bool = false

func bind(next: WeaponProfile, posture: int) -> void:
	stance = posture
	if profile == next:
		size = clampf(size, table().TargetMin, table().TargetMax)
		return
	profile = next
	size = table().TargetMin
	knock = Vector2.ZERO
	sway = Vector2.ZERO
	sway_sign = Vector2.ONE
	scope_kick = 0.0
	kick_target = 0.0
	kick_rising = false
	exertion = 1.0

func table() -> Dictionary:
	return profile.recovered_stats.stances[stance]

func tick(delta: float, velocity: Vector3, look_rate: Vector2, airborne: bool, scoped: bool, effort: float) -> void:
	var t := table()
	knock.x = move_toward(knock.x, 0.0, t.ReticuleKnockReturn * delta)
	knock.y = move_toward(knock.y, 0.0, t.ReticuleKnockReturn * delta)
	var source_velocity := velocity * 10.0
	var target: float = source_velocity.length_squared() / 65.0 * t.TargetDilateUponMovementMult + 158.7 * look_rate.length_squared()
	if airborne:
		target += Vector2(source_velocity.x, source_velocity.z).length_squared() / 65.0
	target = clampf(target, t.TargetMin, t.TargetMax)
	size = move_toward(size, target, (t.TargetDilateUponMovement * 60.0 if size < target else t.TargetConstrict) * delta)
	exertion = clampf(exertion + effort, 0.0, 1.0)
	exertion = maxf(0.0, exertion + t.SniperDecayRate * exertion * delta)
	if not scoped:
		scope_kick = 0.0
		kick_rising = false
		return
	if kick_rising:
		scope_kick = move_toward(scope_kick, kick_target, t.FireRifleKickRate * delta)
		if scope_kick >= kick_target:
			kick_rising = false
	else:
		scope_kick = move_toward(scope_kick, 0.0, t.FireRifleKickReturnRate * delta)
	if exertion <= 0.2:
		return
	var limits := Vector2(t.SniperDistLimitX, t.SniperDistLimitY) * (0.8 * exertion + 0.2)
	var speeds := Vector2(t.SniperDistPPFrameX, t.SniperDistPPFrameY) * sway_sign
	for axis: int in range(2):
		if limits[axis] <= 0.0:
			sway[axis] = 0.0
			continue
		sway[axis] += delta * ((speeds[axis] + 0.75) * absf(sway[axis] / limits[axis]) + speeds[axis] + 0.25)
		if absf(sway[axis]) >= limits[axis]:
			sway[axis] = clampf(sway[axis], -limits[axis], limits[axis])
			sway_sign[axis] = -signf(sway[axis])

func fired(round_of_pull: int, scoped: bool, random: float) -> void:
	var t := table()
	exertion = minf(1.0, exertion + 0.35)
	if scoped:
		if round_of_pull == 1:
			kick_target = t.FireRifleKickBaseDist + t.FireRifleKickRandomDist * random
			scope_kick = 0.0
			kick_rising = true
		return
	var burst: Dictionary = profile.recovered_stats.burst
	var span: float = burst.AccBurstCnt_Max - burst.AccBurstCnt_Min
	var n := maxi(0, round_of_pull + 1 - int(burst.AccBurstCnt_Min))
	var scalar: float = 0.0 if span <= 0.0 else minf(n, burst.AccBurstCnt_Max) * (burst.AccScalar_Max - burst.AccScalar_Min) / span
	size = clampf(size + t.TargetDilateUponFire * (1.0 + scalar), t.TargetMin, t.TargetMax)
	if round_of_pull >= int(t.KnockCount):
		knock.y -= t.ReticuleKnock * (t.KnockEntryStrength if round_of_pull == int(t.KnockCount) else 1.0)
	knock.y = clampf(knock.y, -t.ReticuleKnockMax, t.ReticuleKnockMax)

func spread_degrees(scoped: bool) -> float:
	# Maximum corner angle at level aim. The source pattern is a square, not a cone.
	return 0.0 if scoped else rad_to_deg(atan(size * TANGENT.y * 0.707 * sqrt(2.0) * profile.recovered_spread_scale))

func direction(base: Vector3, scoped: bool, magnification: float, sample: Vector2 = Vector2.ZERO) -> Vector3:
	var offset := -sway if scoped else knock * Vector2(1, -1)
	offset *= TANGENT * profile.recovered_recoil_scale / magnification
	var radius := 0.0 if scoped else size * TANGENT.y * 0.707 * profile.recovered_spread_scale
	var right := base.cross(Vector3.UP)
	var up := right.cross(base)
	return (base + right * (offset.x + radius * sample.x * absf(sample.x)) + up * (offset.y + radius * sample.y * absf(sample.y))).normalized()
