class_name SafeAreaContainer
extends MarginContainer
## Root layout container of every screen. Keeps content inside the display
## safe area (notches / rounded corners on Android) on top of a base margin.

@export var base_margin := 14

func _ready() -> void:
	get_tree().root.size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var screen := Vector2(DisplayServer.screen_get_size())
	var win := Vector2(DisplayServer.window_get_size())
	var vp := get_viewport().get_visible_rect().size
	var k := Vector2.ONE
	if win.x > 0.0 and win.y > 0.0:
		k = vp / win
	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0
	if OS.has_feature("mobile") and safe.size.x > 0.0:
		l = safe.position.x * k.x
		t = safe.position.y * k.y
		r = (screen.x - safe.end.x) * k.x
		b = (screen.y - safe.end.y) * k.y
	add_theme_constant_override("margin_left", base_margin + int(l))
	add_theme_constant_override("margin_top", base_margin + int(t))
	add_theme_constant_override("margin_right", base_margin + int(r))
	add_theme_constant_override("margin_bottom", base_margin + int(b))
