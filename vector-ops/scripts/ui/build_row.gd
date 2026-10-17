class_name BuildRow
extends HBoxContainer
## One saved build in the BuildsPanel (scenes/ui/build_row.tscn).

signal load_pressed
signal delete_pressed

const ACTIVE := Color(0.263, 0.878, 0.776)
const NORMAL := Color(0.9, 0.95, 0.96)

var sel: Array = []


func setup(build_name: String, selection: Array) -> void:
	sel = selection
	%NameLabel.text = build_name
	%FluxLabel.text = "%d" % int(Loadout.max_flux(selection))
	%NameLabel.tooltip_text = "Right: %s\nLeft: %s" % [_hand_text(selection[0]), _hand_text(selection[1])]
	%BtnLoad.pressed.connect(func() -> void: load_pressed.emit())
	%BtnDelete.pressed.connect(func() -> void: delete_pressed.emit())


## Highlights the build that matches what is currently selected in the menu.
func set_active(on: bool) -> void:
	%NameLabel.add_theme_color_override("font_color", ACTIVE if on else NORMAL)


func _hand_text(hand: Array) -> String:
	var names: PackedStringArray = []
	for id in hand:
		if String(id) != "":
			names.append(Loadout.get_data(String(id)).display_name)
	return ", ".join(names) if not names.is_empty() else "(empty)"
