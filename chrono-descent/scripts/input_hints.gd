extends Node
## Tracks the last-used input device and names the button bound to an action.
## Registered as the autoload "InputHints". The HUD uses it so prompts always match what the
## player is holding: "E" on keyboard, "SQUARE" on a Sony controller.

signal device_changed(using_controller: bool)

## Sony-style names for the standard joypad button indices.
const PAD_NAMES: Dictionary = {
	0: "CROSS", 1: "CIRCLE", 2: "SQUARE", 3: "TRIANGLE", 4: "SHARE", 6: "START",
	9: "L1", 10: "R1", 11: "UP", 12: "DOWN", 13: "LEFT", 14: "RIGHT",
	7: "L3", 8: "R3",
}
## The two triggers are analog axes, not buttons.
const TRIGGER_NAMES: Dictionary = {4: "L2", 5: "R2"}

var using_controller: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	var from_pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	var from_keyboard := (event is InputEventKey and not (event as InputEventKey).echo) or event is InputEventMouseButton
	if from_pad and not using_controller:
		using_controller = true
		device_changed.emit(true)
	elif from_keyboard and using_controller:
		using_controller = false
		device_changed.emit(false)


## Short label (upper case) of the action's binding on the device currently in use.
func get_action_hint(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if using_controller and event is InputEventJoypadButton:
			var index: int = (event as InputEventJoypadButton).button_index
			return PAD_NAMES.get(index, "BTN %d" % index)
		if using_controller and event is InputEventJoypadMotion and TRIGGER_NAMES.has((event as InputEventJoypadMotion).axis):
			return TRIGGER_NAMES[(event as InputEventJoypadMotion).axis]
		if not using_controller and event is InputEventKey:
			var key := event as InputEventKey
			var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code).to_upper()
	return "?"
