extends Control
## Flux guide (scenes/ui/guide_dialog.tscn). The intro text is in the scene;
## one entry per module is added from the module database.

const NAME_COLOR := Color(0.263, 0.878, 0.776)
const TEXT_COLOR := Color(0.5, 0.62, 0.67)


func _ready() -> void:
	%BtnClose.pressed.connect(func() -> void: visible = false)
	for id in Loadout.ids():
		var d := Loadout.get_data(id)
		var title := Label.new()
		title.text = "%s   (weight %d)" % [d.display_name.to_upper(), int(d.weight)]
		title.add_theme_color_override("font_color", NAME_COLOR)
		%Entries.add_child(title)
		var body := Label.new()
		body.text = d.description
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_color_override("font_color", TEXT_COLOR)
		body.add_theme_font_size_override("font_size", 12)
		%Entries.add_child(body)
