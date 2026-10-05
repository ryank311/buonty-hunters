extends SceneTree
## Focus changes leave gameplay running and preserve explicitly opened menus.
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func _run() -> void:
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false})
	var target: Node3D = session.level.get_node("Targets/MovingTarget")
	var before := target.position
	var elapsed: float = session.elapsed
	session.player.pending_mouse = Vector2(40, 20)
	root.focus_exited.emit()
	check(session.player.pending_mouse == Vector2.ZERO, "Losing focus clears queued mouse motion")
	await H.step(self, 10)
	check(not session.modal and session.player.controls_enabled and not session.hud.menu_box.is_visible_in_tree(), "Losing focus keeps gameplay active and the tuning menu closed")
	check(session.elapsed > elapsed and not target.position.is_equal_approx(before), "The world continues advancing while unfocused")
	root.focus_entered.emit()
	check(not session.modal, "Returning focus does not open the menu")
	var toggle := InputEventAction.new()
	toggle.action = "tuning"
	toggle.pressed = true
	session._input(toggle)
	check(session.modal and session.hud.menu_box.is_visible_in_tree(), "Explicit tuning input still opens the menu")
	root.focus_exited.emit()
	root.focus_entered.emit()
	check(session.modal and session.hud.menu_box.is_visible_in_tree(), "Alt-tab preserves an explicitly opened menu")
	session._input(toggle)
	session._controller_connection_changed(0, false)
	check(not session.modal, "A controller disconnect reports status without opening a menu")
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
