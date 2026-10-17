class_name BaseScreen
extends Control
## Parent class of the Server and Shop screens. Provides the shared overlays
## (deck viewer, type picker, toast) and the Executable / Corruption flow.
## Derived scenes must contain unique-name nodes: DeckViewer, TypePicker, Toast.

@onready var deck_viewer: DeckViewer = %DeckViewer
@onready var type_picker: TypePicker = %TypePicker
@onready var toast: Toast = %Toast
## Optional in-game settings overlay (a child named PauseMenu).
@onready var pause_menu: Control = get_node_or_null("PauseMenu")   # scenes/pause_menu (duck typed: no class_name needed)


func _ready() -> void:
	EventBus.toast_requested.connect(show_toast)
	if pause_menu != null:
		pause_menu.can_open = can_open_settings


func show_toast(text: String, color: Color = Enums.COL_TEXT) -> void:
	toast.show_text(text, color)


func open_deck_tracker() -> void:
	deck_viewer.open_view()


func is_overlay_open() -> bool:
	return deck_viewer.visible or type_picker.visible or (pause_menu != null and pause_menu.is_open())


## Screens override this to forbid opening Settings at bad moments (mid-animation).
func can_open_settings() -> bool:
	return not (deck_viewer.visible or type_picker.visible)


## Runs the whole use-flow for a consumable: targets -> (type) -> apply.
func use_consumable(item: Dictionary) -> bool:
	var reason := ConsumableService.why_not(item)
	if reason != "":
		show_toast(reason, Enums.COL_ICE)
		AudioService.play("deny")
		return false
	var info := ItemDB.get_item(item.kind, item.id)
	var r := ConsumableService.target_range(item)
	var targets: Array = []
	var extra := {}
	if r.y > 0:
		targets = await deck_viewer.pick(String(info.name).to_upper() + ": SELECT TARGET", r.x, r.y)
		if targets.is_empty():
			return false
	if item.id == "reformat":
		var t: int = await type_picker.choose()
		if t < 0:
			return false
		extra["type"] = t
	var res := ConsumableService.use(item, targets, extra)
	show_toast(String(res.msg), Enums.COL_COOLANT if res.ok else Enums.COL_ICE)
	if res.ok:
		AudioService.play("buy")
		PostFX.glitch_small()
	return res.ok
