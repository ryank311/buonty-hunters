extends SceneTree
## Stance changes and leans move the camera smoothly, never in one jump.
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

## The largest single-tick camera movement over `ticks`, and the total it travelled.
func watch(camera: Camera3D, ticks: int, input: Dictionary) -> Vector2:
	var last := camera.global_position
	var start := last
	var largest := 0.0
	for tick: int in range(ticks):
		await H.step(self, 1, input if tick == 0 or input.has("hold") else {})
		largest = maxf(largest, camera.global_position.distance_to(last))
		last = camera.global_position
	return Vector2(largest, last.distance_to(start))

func _run() -> void:
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	var player: PrototypePlayer = session.player
	var camera: Camera3D = player.camera_rig.camera
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "pitch": 0.0})
	await H.step(self, 30)
	# No tick may cover more than a tenth of the move; the old snap did all of it in one.
	for entry: Array in [["crouch", {"tap": ["crouch"]}, 60], ["prone", {"tap": ["prone"]}, 90], ["stand", {"tap": ["prone"]}, 90]]:
		var moved: Vector2 = await watch(camera, entry[2], entry[1])
		check(moved.y > 0.2 and moved.x < moved.y * 0.1, "Changing to %s moves the camera %.2f m with no jump (largest tick %.3f m)" % [entry[0], moved.y, moved.x])
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "pitch": 0.0})
	await H.step(self, 30)
	var lean: Vector2 = await watch(camera, 30, {"hold": ["lean_left"]})
	check(lean.y > 0.1 and lean.x < lean.y * 0.1, "Leaning left eases the camera over (%.2f m, largest tick %.3f m)" % [lean.y, lean.x])
	var swap: Vector2 = await watch(camera, 40, {"hold": ["lean_right"]})
	check(swap.y > 0.2 and swap.x < swap.y * 0.1, "Switching to a right lean crosses over smoothly (%.2f m, largest tick %.3f m)" % [swap.y, swap.x])
	var back: Vector2 = await watch(camera, 40, {})
	check(back.y > 0.1 and back.x < back.y * 0.1, "Releasing the lean eases back (%.2f m, largest tick %.3f m)" % [back.y, back.x])
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
