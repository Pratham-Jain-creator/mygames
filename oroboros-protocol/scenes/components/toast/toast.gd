class_name Toast
extends Control
## One-line status banner. Fade / slide is authored in the AnimationPlayer ("pop").

@onready var _label: Label = %Label
@onready var _anim: AnimationPlayer = $AnimationPlayer


func show_text(text: String, color: Color = Enums.COL_TEXT) -> void:
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	_anim.stop()
	_anim.play(&"pop")
