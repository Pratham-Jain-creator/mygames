extends VBoxContainer
## Short pop-up messages stacked at the bottom-left of the screen ("+3 IRON ORE", "NEEDS A PICKAXE").
## Each fades out by itself. HUD forwards GameManager.toast_requested here.

const FONT: Font = preload("res://assets/sprites/dungeon_set/pixel_bars_free/addons/pixel_bars/font/pixel_ui_font.fnt")
const MAX_TOASTS: int = 6
const LIFETIME: float = 2.6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 2)


func push(text: String, icon: Texture2D, color: Color) -> void:
	while get_child_count() >= MAX_TOASTS:
		get_child(0).free()
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	if icon != null:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.custom_minimum_size = Vector2(24, 24)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(picture)
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	add_child(row)
	var tween := create_tween()
	tween.tween_interval(LIFETIME)
	tween.tween_property(row, "modulate:a", 0.0, 0.5)
	tween.tween_callback(row.queue_free)
