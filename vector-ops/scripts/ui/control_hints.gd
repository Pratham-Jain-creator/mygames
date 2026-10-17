class_name ControlHints
extends RefCounted
## Names the button for an Input Map action on the device the player is using right
## now: keyboard + mouse, a PlayStation pad or an Xbox / generic pad. The names come
## from the Input Map itself, so rebinding an action changes the on-screen hint too.

const PS_BUTTONS := {0: "Cross", 1: "Circle", 2: "Square", 3: "Triangle", 4: "Share", 6: "Options",
		7: "L3", 8: "R3", 9: "L1", 10: "R1", 11: "D-Up", 12: "D-Down", 13: "D-Left", 14: "D-Right", 15: "Mic", 20: "Touchpad"}
const XBOX_BUTTONS := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "View", 6: "Menu",
		7: "L3", 8: "R3", 9: "LB", 10: "RB", 11: "D-Up", 12: "D-Down", 13: "D-Left", 14: "D-Right"}
const PS_WORDS := ["playstation", "ps3", "ps4", "ps5", "dualshock", "dualsense", "sony", "wireless controller"]


static func using_pad() -> bool:
	return GameState.using_pad and not Input.get_connected_joypads().is_empty()


static func is_sony() -> bool:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		return false
	var n: String = Input.get_joy_name(pads[0]).to_lower()
	for w in PS_WORDS:
		if n.contains(w):
			return true
	return false


## "Cross", "RT", "E", "LMB" ... for the first binding of the action on the active device.
static func key(action: StringName) -> String:
	var pad: bool = using_pad()
	var fallback: String = ""
	for ev in InputMap.action_get_events(action):
		var is_pad: bool = ev is InputEventJoypadButton or ev is InputEventJoypadMotion
		var text: String = _pad_name(ev) if is_pad else _kb_name(ev)
		if is_pad == pad:
			return text
		if fallback == "":
			fallback = text
	return fallback


static func move() -> String:
	return "L Stick" if using_pad() else "WASD"


static func _pad_name(ev: InputEvent) -> String:
	if ev is InputEventJoypadButton:
		var table: Dictionary = PS_BUTTONS if is_sony() else XBOX_BUTTONS
		return table.get(ev.button_index, "Button %d" % ev.button_index)
	var m: InputEventJoypadMotion = ev
	match m.axis:
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
			return "L Stick"
		JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
			return "R Stick"
		JOY_AXIS_TRIGGER_LEFT:
			return "L2" if is_sony() else "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "R2" if is_sony() else "RT"
	return "Axis %d" % m.axis


static func _kb_name(ev: InputEvent) -> String:
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
		return "Mouse %d" % ev.button_index
	var k: InputEventKey = ev
	return (k.as_text_physical_keycode() if k.physical_keycode != 0 else k.as_text_keycode())


## One-glance summary for the main menu.
static func summary() -> String:
	return "%s move - %s run - %s slide - %s jump\n%s right hand - %s left hand\n%s / %s rotate hand - %s spectate\n%s pause" % [
		move(), key(&"toggle_run"), key(&"slide"), key(&"jump"),
		key(&"fire"), key(&"fire_left"),
		key(&"rotate_left"), key(&"rotate_right"), key(&"spectate_next"),
		key(&"ui_cancel")]
