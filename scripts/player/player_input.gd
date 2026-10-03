class_name PlayerInput
extends RefCounted

const KEYS: Dictionary = {
	"move_forward": KEY_W, "move_back": KEY_S,
	"move_left": KEY_A, "move_right": KEY_D,
	"walk": KEY_SHIFT, "jump": KEY_SPACE, "crouch": KEY_C,
	"prone": KEY_Z, "lean_left": KEY_Q, "lean_right": KEY_E,
	"reload": KEY_R, "reset_player": KEY_BACKSPACE,
	"pause": KEY_ESCAPE, "tuning": KEY_F1, "debug_view": KEY_F3,
	"switch_level": KEY_F2, "start_lap": KEY_T, "next_spawn": KEY_N,
	"equip_rifle": KEY_1, "equip_pistol": KEY_2,
}

static func setup() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = KEYS[action]
		InputMap.action_add_event(action, event)
	for action: String in ["fire", "aim", "pad_stance", "look_left", "look_right", "look_up", "look_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)
	_button("jump", JOY_BUTTON_A)
	_button("pad_stance", JOY_BUTTON_B)
	_button("reload", JOY_BUTTON_X)
	_button("lean_left", JOY_BUTTON_LEFT_SHOULDER)
	_button("lean_right", JOY_BUTTON_RIGHT_SHOULDER)
	_button("pause", JOY_BUTTON_START)
	_button("tuning", JOY_BUTTON_BACK)
	_button("equip_rifle", JOY_BUTTON_DPAD_LEFT)
	_button("equip_pistol", JOY_BUTTON_DPAD_RIGHT)
	_button("next_spawn", JOY_BUTTON_DPAD_UP)
	_button("reset_player", JOY_BUTTON_DPAD_DOWN)
	_button("start_lap", JOY_BUTTON_Y)
	_button("walk", JOY_BUTTON_LEFT_STICK)
	_button("debug_view", JOY_BUTTON_RIGHT_STICK)
	# Explicit UI bindings keep menu navigation independent of gameplay actions.
	for action: String in ["menu_previous", "menu_next"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_button("menu_previous", JOY_BUTTON_LEFT_SHOULDER)
	_button("menu_next", JOY_BUTTON_RIGHT_SHOULDER)
	_button("ui_accept", JOY_BUTTON_A)
	_button("ui_cancel", JOY_BUTTON_B)
	_button("ui_up", JOY_BUTTON_DPAD_UP)
	_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis("aim", JOY_AXIS_TRIGGER_LEFT, 1.0)
	InputMap.action_set_deadzone("fire", 0.15)
	InputMap.action_set_deadzone("aim", 0.15)

static func _mouse(action: String, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

static func _button(action: String, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

static func _axis(action: String, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

static func look_vector(deadzone: float) -> Vector2:
	var value := Input.get_vector("look_left", "look_right", "look_up", "look_down", deadzone)
	return value.normalized() * pow(value.length(), 1.5)

static func vibrate(strength: float, duration: float = 0.07) -> void:
	if strength <= 0.0 or DisplayServer.get_name() == "headless":
		return
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		Input.start_joy_vibration(pads[0], strength * 0.45, strength, duration)

static func stop_vibration() -> void:
	for pad: int in Input.get_connected_joypads():
		Input.stop_joy_vibration(pad)
