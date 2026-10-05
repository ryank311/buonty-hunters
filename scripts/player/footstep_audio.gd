extends RefCounted
## Footfalls follow the recovered leg cycle, including reversed travel. Gait
## loudness follows actual speed, so pushing a wall cannot produce sprint steps.
const Locomotion = preload("res://scripts/actors/recovered_locomotion.gd")
const SOUNDS: Dictionary = {
	"walk": [preload("res://audio/footsteps/walk_1.wav"), preload("res://audio/footsteps/walk_2.wav"), preload("res://audio/footsteps/walk_3.wav")],
	"jog": [preload("res://audio/footsteps/jog_1.wav"), preload("res://audio/footsteps/jog_2.wav"), preload("res://audio/footsteps/jog_3.wav")],
	"sprint": [preload("res://audio/footsteps/sprint_1.wav"), preload("res://audio/footsteps/sprint_2.wav"), preload("res://audio/footsteps/sprint_3.wav")],
}
var contacts: Dictionary = {}
var previous_phase: float = -1.0
var elapsed: float = 1.0
var steps_played: int = 0
var last_gait: String = ""
var last_foot: String = ""
var last_volume: float = -80.0
var last_sound: AudioStream
var variant: int = 0

func reset() -> void:
	previous_phase = -1.0
	elapsed = 1.0

func update(skin: SoldierSkin, output: AudioStreamPlayer3D, speed: float, run_speed: float, stance: int, grounded: bool, delta: float) -> void:
	elapsed += delta
	var driver: RefCounted = skin.driver
	if not grounded or stance == StanceController.Stance.PRONE or speed < 0.25 or driver.mix.is_empty():
		previous_phase = -1.0
		return
	var phase: float = driver.phase
	if previous_phase < 0.0:
		previous_phase = phase
		return
	var clip: String = driver.active_clip
	var base: String = Locomotion.base_clip(skin.motion, clip)
	if base != "":
		clip = base
	var reverse: bool = driver.cadence < 0.0
	var travel := fposmod(previous_phase - phase if reverse else phase - previous_phase, 1.0)
	# A reset/teleport is not a stride. Nor should a gait blend trigger both feet
	# at once when its dominant clip changes near a contact.
	if travel < 0.5 and elapsed >= 0.14:
		for foot: String in ["ltoe", "rtoe"]:
			var contact: float = contact_phases(skin.motion, clip)[foot][1 if reverse else 0]
			var distance := fposmod(previous_phase - contact if reverse else contact - previous_phase, 1.0)
			if distance > 0.0 and distance <= travel:
				_play(output, speed, run_speed, stance, foot)
				break
	previous_phase = phase

func _play(output: AudioStreamPlayer3D, speed: float, run_speed: float, stance: int, foot: String) -> void:
	var amount := clampf(speed / maxf(run_speed, 0.01), 0.0, 1.0)
	last_gait = "walk" if amount < 0.42 or stance == StanceController.Stance.CROUCH else ("jog" if amount < 0.82 else "sprint")
	last_volume = lerpf(-26.0, -8.0, amount) - (6.0 if stance == StanceController.Stance.CROUCH else 0.0)
	last_foot = foot
	# Alternate the native tone variants, with restrained pitch variation.
	variant = (variant + randi_range(1, 2)) % 3
	last_sound = SOUNDS[last_gait][variant]
	steps_played += 1
	elapsed = 0.0
	if DisplayServer.get_name() != "headless":
		# Keep each footfall's tail and gain when the next foot lands. Replacing an
		# AudioStreamPlayer's stream for every variant would cut off the last one.
		if not output.stream is AudioStreamPolyphonic:
			var stream := AudioStreamPolyphonic.new()
			stream.polyphony = 4
			output.stream = stream
			output.volume_db = 0.0
			output.pitch_scale = 1.0
		if not output.playing:
			output.play()
		var playback := output.get_stream_playback() as AudioStreamPlaybackPolyphonic
		playback.play_stream(last_sound, 0.0, last_volume, randf_range(0.97, 1.03))

func contact_phases(motion: Node, clip: String) -> Dictionary:
	if contacts.has(clip):
		return contacts[clip]
	var curves := {"ltoe": [], "rtoe": []}
	const SAMPLES: int = 64
	for index: int in range(SAMPLES):
		var pose: Array[Transform3D] = motion.worlds(motion.sample(clip, motion.get_animation(clip).length * index / SAMPLES))
		for foot: String in curves:
			curves[foot].append(pose[motion.rig.names.find(foot)].origin.y)
	var result := {}
	for foot: String in curves:
		var heights: Array = curves[foot]
		var high: float = heights.max()
		var low: float = heights.min()
		var threshold := low + minf(0.025, (high - low) * 0.25)
		var peak: int = heights.find(high)
		var phases: Array[float] = []
		for direction: int in [1, -1]:
			var contact := 0.0
			for step: int in range(1, SAMPLES):
				var index := posmod(peak + step * direction, SAMPLES)
				if heights[index] <= threshold:
					contact = float(index) / SAMPLES
					break
			phases.append(contact)
		result[foot] = phases
	contacts[clip] = result
	return result
