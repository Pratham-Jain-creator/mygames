class_name ModuleCard
extends Button
## One module in the ModulePicker (scenes/ui/module_card.tscn). Shows the
## module, its group and how it would change max Flux in the chosen slot.

signal picked(id: String)
signal hovered(id: String)

const GOOD := Color(0.35, 0.9, 0.55)
const BAD := Color(0.92, 0.38, 0.4)
const NEUTRAL := Color(0.5, 0.62, 0.67)

var module_id: String = ""


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(module_id))
	mouse_entered.connect(func() -> void: hovered.emit(module_id))
	focus_entered.connect(func() -> void: hovered.emit(module_id))


## delta = change in max Flux if this module goes into the slot.
func setup(id: String, delta: float, selected: bool) -> void:
	module_id = id
	button_pressed = selected
	%Chip.color = Loadout.color_of(id)
	if id == "":
		%NameLabel.text = "EMPTY"
		%WeightLabel.text = "wt 0"
		%CategoryLabel.text = "NO MODULE"
	else:
		var d: ModuleData = Loadout.get_data(id)
		%NameLabel.text = d.display_name
		%WeightLabel.text = "wt %d" % int(d.weight)
		%CategoryLabel.text = Loadout.category_of(id)
	var r: int = roundi(delta)
	if r == 0:
		%DeltaLabel.text = "no change"
		%DeltaLabel.add_theme_color_override("font_color", NEUTRAL)
	else:
		%DeltaLabel.text = "%+d Flux" % r
		%DeltaLabel.add_theme_color_override("font_color", GOOD if r > 0 else BAD)
