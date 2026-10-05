extends RefCounted
## Named bank events belong to source records, including shared meshes and silencers.
static var _catalogue: Dictionary = {}
static var _streams: Dictionary = {}

static func catalogue() -> Dictionary:
	if _catalogue.is_empty():
		_catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://resources/recovered/weapon_audio.json"))
	return _catalogue

static func event_name(profile: WeaponProfile, event: String = "fire", distance: float = 0.0) -> String:
	var data := catalogue()
	var record: Dictionary = data.records.get(str(int(profile.recovered_stats.get("id", -1))), {})
	var key := event
	if event == "fire":
		key = "fire_far" if distance >= data.distance_far else "fire_med" if distance >= data.distance_med else "fire_close"
	# A missing distant suppressed report is deliberately silent in the source.
	var value: Variant = record.get(key)
	return value if value is String else ""

static func stream_for(name: String, variant: int = 0) -> AudioStream:
	var sound: Dictionary = catalogue().sounds.get(name, {})
	if sound.is_empty():
		return null
	var files: Array = sound.files
	var path: String = files[posmod(variant, files.size())].path
	if not _streams.has(path):
		_streams[path] = load(path)
	return _streams[path]

var shot_output := AudioStreamPlayer3D.new()
var reload_output := AudioStreamPlayer3D.new()
var last_fire: String = ""
var last_reload: String = ""
var shots_played: int = 0
var reloads_played: int = 0

func initialize(parent: Node3D) -> void:
	parent.add_child(shot_output)
	parent.add_child(reload_output)
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 24
	shot_output.stream = poly
	for output: AudioStreamPlayer3D in [shot_output, reload_output]:
		output.bus = &"World"
		output.volume_db = 0.0
		output.unit_size = 8.0
		output.max_distance = 120.0

func fire(profile: WeaponProfile) -> void:
	last_fire = event_name(profile)
	var stream := stream_for(last_fire, shots_played)
	if stream == null:
		return
	shots_played += 1
	if DisplayServer.get_name() != "headless":
		if not shot_output.playing:
			shot_output.play()
		var playback := shot_output.get_stream_playback() as AudioStreamPlaybackPolyphonic
		# Every round keeps its own tail, even when the next is another gun.
		playback.play_stream(stream, 0.0, 0.0, profile.sound_pitch)

func reload(profile: WeaponProfile) -> void:
	last_reload = event_name(profile, "reload")
	reload_output.stop()
	reload_output.stream = stream_for(last_reload, reloads_played)
	if reload_output.stream == null:
		return
	reloads_played += 1
	reload_output.pitch_scale = profile.sound_pitch
	if DisplayServer.get_name() != "headless":
		reload_output.play()

func cancel_reload() -> void:
	reload_output.stop()
	last_reload = ""

func reset() -> void:
	shot_output.stop()
	cancel_reload()
	last_fire = ""
