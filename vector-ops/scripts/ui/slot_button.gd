class_name SlotButton
extends Button
## One loadout slot on the start menu (scenes/ui/slot_button.tscn). Shows the
## module in the slot; pressing it opens the ModulePicker (wired by Menu).

var module_id: String = ""


func set_module(id: String) -> void:
	module_id = id
	%Chip.color = Loadout.color_of(id)
	if id == "":
		%NameLabel.text = "- empty -"
		%WeightLabel.text = "+3 Flux"
		return
	var d: ModuleData = Loadout.get_data(id)
	%NameLabel.text = d.display_name
	%WeightLabel.text = "wt %d" % int(d.weight)
