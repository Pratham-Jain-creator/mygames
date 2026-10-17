class_name ModulePicker
extends Control
## Module selector dialog (scenes/ui/module_picker.tscn). Replaces the plain
## dropdown: every module is a card with its group, weight and the Flux it
## would add or cost in the chosen slot; hovering a card shows its description.

signal chosen(hand: int, slot: int, id: String)

const CARD_SCENE := preload("res://scenes/ui/module_card.tscn")

var _hand: int = 0
var _slot: int = 0


func _ready() -> void:
	%BtnCancel.pressed.connect(close)
	%Dim.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed:
			close())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	visible = false


## loadout = the loadout currently shown in the menu; hand/slot = the slot being edited.
func open(hand: int, slot: int, loadout: Array) -> void:
	_hand = hand
	_slot = slot
	var current: String = loadout[hand][slot]
	var base: float = Loadout.max_flux(loadout)
	%TitleLabel.text = "%s HAND  -  SLOT %d" % ["RIGHT" if hand == 0 else "LEFT", slot + 1]
	%FluxLabel.text = "Max Flux now: %d" % int(base)
	for c in %Grid.get_children():
		%Grid.remove_child(c)
		c.queue_free()
	var focus: ModuleCard = null
	for id in [""] + Loadout.ids():
		var trial: Array = loadout.duplicate(true)
		trial[hand][slot] = id
		var card: ModuleCard = CARD_SCENE.instantiate()
		%Grid.add_child(card)
		card.setup(id, Loadout.max_flux(trial) - base, id == current)
		card.picked.connect(_on_picked)
		card.hovered.connect(_show_detail)
		if id == current:
			focus = card
	_show_detail(current)
	visible = true
	if focus != null:
		focus.grab_focus()


func _on_picked(id: String) -> void:
	visible = false
	chosen.emit(_hand, _slot, id)


func _show_detail(id: String) -> void:
	if id == "":
		%DetailLabel.text = "EMPTY\nLeave the slot empty: +3 max Flux, nothing to rotate to."
		return
	var d: ModuleData = Loadout.get_data(id)
	%DetailLabel.text = "%s  -  weight %d  -  %s\n%s" % [d.display_name.to_upper(), int(d.weight), Loadout.category_of(id), d.description]
