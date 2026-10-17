class_name ChoiceMenu
extends CanvasLayer
## A pop-up list of choices, used by the special rooms (grafting table, monolith, weapon mold, cartographer...).
## While it is open the player stands still. Navigate with the d-pad / arrow keys, confirm with the accept button,
## cancel with Esc / the cancel button.
##
##   menu.open("DRAFT A GRAFT", "it will not come off", options, func(index): ...)
##   options: [{name, desc, color (optional), enabled (optional, default true)}, ...]
## The callback gets the index of the chosen option, or -1 when the menu was cancelled.

signal closed

var _backdrop: ColorRect
var _window: PanelContainer
var _heading: Label
var _subtitle: Label
var _list: VBoxContainer
var _on_pick: Callable
var _allow_cancel: bool = true
var _open: bool = false


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.62)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var parts := UIKit.window("", Vector2(660, 0))
	_window = parts["root"]
	center.add_child(_window)
	var body: VBoxContainer = parts["body"]
	_heading = parts["heading"]
	_subtitle = UIKit.label("", 16, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_subtitle)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	body.add_child(_list)
	body.add_child(UIKit.label("", 8))


func is_open() -> bool:
	return _open


func open(title: String, subtitle: String, options: Array, on_pick: Callable, allow_cancel: bool = true) -> void:
	if _open:
		return
	_open = true
	_on_pick = on_pick
	_allow_cancel = allow_cancel
	_heading.text = title
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""
	UIKit.clear(_list)
	var first: Button = null
	for i in options.size():
		var option: Dictionary = options[i]
		var button := UIKit.button("")
		button.custom_minimum_size = Vector2(620, 58)
		button.disabled = not bool(option.get("enabled", true))
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 12
		box.offset_top = 6
		box.offset_right = -12
		box.add_theme_constant_override("separation", 2)
		var color: Color = option.get("color", UIKit.GOLD)
		box.add_child(UIKit.label(String(option["name"]).to_upper(), 16, color if not button.disabled else UIKit.DIM))
		var desc := UIKit.label(String(option.get("desc", "")), 12, UIKit.TEXT if not button.disabled else UIKit.DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc)
		button.add_child(box)
		button.pressed.connect(_pick.bind(i))
		_list.add_child(button)
		if first == null and not button.disabled:
			first = button
	if _allow_cancel:
		var cancel := UIKit.button("LEAVE IT")
		cancel.custom_minimum_size = Vector2(620, 40)
		cancel.pressed.connect(_cancel)
		_list.add_child(cancel)
		if first == null:
			first = cancel
	visible = true
	if is_instance_valid(GameManager.player):
		GameManager.player.set_input_locked(true)
	if first != null:
		first.call_deferred("grab_focus")


## Closes the menu without choosing anything (the callback is not called).
func close() -> void:
	if _open:
		_close()


func _pick(index: int) -> void:
	var callback := _on_pick
	_close()
	if callback.is_valid():
		callback.call(index)


func _cancel() -> void:
	_pick(-1)


func _close() -> void:
	_open = false
	visible = false
	if is_instance_valid(GameManager.player):
		GameManager.player.set_input_locked(false)
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if _allow_cancel and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("roll")):
		get_viewport().set_input_as_handled()
		_cancel()
		return
	UIKit.ensure_focus(self, get_viewport())
	if UIKit.press_focused(event, get_viewport()):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open:
		UIKit.ensure_focus(self, get_viewport())
