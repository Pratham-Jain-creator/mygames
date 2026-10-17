extends RefCounted
## Shows the Nullcoin icon in front of an amount. Pass "Ø12" (or any text) to `apply`:
## a leading "Ø" is replaced by the icon, other text is shown as is without an icon.

const ICON := preload("res://assets/buttons/icon_currency.png")
const GAP := 6.0


static func apply(label: Label, text: String) -> void:
	var has := text.begins_with("Ø")
	if has:
		text = text.substr(1)
	label.text = text
	var icon := label.get_node_or_null("MoneyIcon") as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "MoneyIcon"
		icon.texture = ICON
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_child(icon)
		label.resized.connect(func(): _place(label))
	icon.visible = has
	var fs := label.get_theme_font_size("font_size")
	var w := float(fs) * 1.25
	icon.custom_minimum_size = Vector2(w, w)
	icon.size = Vector2(w, w)
	var box := StyleBoxEmpty.new()
	if has and label.horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT:
		box.content_margin_left = w + GAP
	label.add_theme_stylebox_override("normal", box)
	_place(label)


static func _place(label: Label) -> void:
	var icon := label.get_node_or_null("MoneyIcon") as TextureRect
	if icon == null or not icon.visible:
		return
	var w := icon.size.x
	var y := (label.size.y - w) * 0.5
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		var font := label.get_theme_font("font")
		var tw := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		icon.position = Vector2(label.size.x - tw - GAP - w, y)
	else:
		icon.position = Vector2(0, y)
