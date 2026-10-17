class_name UIKit
extends RefCounted
## The look of every menu, taken from the "Dungeon UI sheet" in assets/sprites/ui/inventory: near-black brown windows
## with a brown-gold border and a darker title bar, gold text, square slots whose frame shows what is in them
## (rarity colours), and buttons that turn gold when focused. Everything is built from StyleBoxFlat, so it stays
## crisp at any window size.

const FONT: Font = preload("res://assets/fonts/PixelOperator8.ttf")
const FONT_BOLD: Font = preload("res://assets/fonts/PixelOperator8-Bold.ttf")

const BG := Color(0.075, 0.058, 0.045, 0.97)
const BG_DEEP := Color(0.045, 0.035, 0.028, 1.0)
const BAR := Color(0.16, 0.125, 0.09, 1.0)
const BORDER := Color(0.36, 0.27, 0.16, 1.0)
const GOLD := Color(0.85, 0.7, 0.42, 1.0)
const GOLD_BRIGHT := Color(0.97, 0.84, 0.52, 1.0)
const TEXT := Color(0.88, 0.8, 0.64, 1.0)
const DIM := Color(0.52, 0.46, 0.38, 1.0)
const GOOD := Color(0.42, 0.78, 0.38, 1.0)
const BAD := Color(0.88, 0.38, 0.3, 1.0)
## Slot frames by what they hold (the sheet's "rarity frames").
const COMMON := Color(0.55, 0.52, 0.47)
const FINE := Color(0.35, 0.65, 0.36)
const RARE := Color(0.29, 0.51, 0.78)
const EPIC := Color(0.6, 0.36, 0.77)
const LEGEND := Color(0.88, 0.57, 0.16)
const CURSED := Color(0.75, 0.22, 0.17)


static func box(fill: Color, border: Color, border_width: int = 2, margin: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(margin)
	return style


static func label(text: String, size: int = 16, color: Color = TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A window: a panel with a title bar. Returns {root, body, heading}: add your content to `body`; `heading` is the
## title bar's label.
static func window(title: String, size: Vector2) -> Dictionary:
	var root := PanelContainer.new()
	root.custom_minimum_size = size
	root.size = size
	root.add_theme_stylebox_override("panel", box(BG, BORDER, 3))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	root.add_child(column)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", box(BAR, BORDER, 2, 6))
	var heading := label(title, 16, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	bar.add_child(heading)
	column.add_child(bar)
	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		body_margin.add_theme_constant_override("margin_" + side, 12)
	column.add_child(body_margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body_margin.add_child(body)
	return {"root": root, "body": body, "heading": heading}


## A button in the sheet's style: dark with a brown border, gold when hovered or focused.
static func button(text: String, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	b.add_theme_color_override("font_focus_color", GOLD_BRIGHT)
	b.add_theme_color_override("font_pressed_color", GOLD_BRIGHT)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.add_theme_stylebox_override("normal", box(Color(0.12, 0.09, 0.065), BORDER, 2, 8))
	b.add_theme_stylebox_override("hover", box(Color(0.19, 0.14, 0.09), GOLD, 2, 8))
	b.add_theme_stylebox_override("focus", box(Color(0.22, 0.16, 0.1), GOLD_BRIGHT, 3, 8))
	b.add_theme_stylebox_override("pressed", box(Color(0.1, 0.07, 0.05), GOLD_BRIGHT, 2, 8))
	b.add_theme_stylebox_override("disabled", box(Color(0.08, 0.065, 0.05), Color(0.2, 0.16, 0.12), 2, 8))
	return b


## A square slot frame (empty / holding something of `accent` colour / selected).
static func slot_style(accent: Color = Color(0.3, 0.24, 0.17), selected: bool = false) -> StyleBoxFlat:
	return box(BG_DEEP, GOLD_BRIGHT if selected else accent, 3 if selected else 2)


## A coloured gem icon for materials, charms, grafts and the like, drawn as a Control. `symbol` picks the shape.
class Gem extends Control:
	var color: Color = Color.WHITE
	var shape: int = 0 ## 0 diamond, 1 round, 2 scroll, 3 shard
	var dim: bool = false
	var cracked: bool = false

	func _init(gem_color: Color = Color.WHITE, gem_shape: int = 0) -> void:
		color = gem_color
		shape = gem_shape
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(32, 32)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.34
		var tint := color.darkened(0.6) if dim else color
		draw_circle(c, r * 1.55, Color(tint.r, tint.g, tint.b, 0.16))
		match shape:
			1:
				draw_circle(c, r, tint)
				draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(1, 1, 1, 0.7))
			2:
				draw_rect(Rect2(c + Vector2(-r * 0.7, -r), Vector2(r * 1.4, r * 2.0)), tint)
				draw_rect(Rect2(c + Vector2(-r * 0.4, -r * 0.45), Vector2(r * 0.8, 2)), Color(0.35, 0.25, 0.1))
				draw_rect(Rect2(c + Vector2(-r * 0.4, r * 0.15), Vector2(r * 0.8, 2)), Color(0.35, 0.25, 0.1))
			3:
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.3), c + Vector2(r * 0.8, -r * 0.2), c + Vector2(r * 0.4, r * 1.2), c + Vector2(-r * 0.5, r * 1.1), c + Vector2(-r * 0.9, -r * 0.1)]), tint)
			_:
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.3), c + Vector2(r, 0), c + Vector2(0, r * 1.3), c + Vector2(-r, 0)]), tint)
				draw_circle(c + Vector2(-r * 0.25, -r * 0.4), r * 0.2, Color(1, 1, 1, 0.75))
		if cracked:
			draw_line(c + Vector2(-r, -r), c + Vector2(r, r), Color(1, 0.3, 0.25), 2.0)
			draw_line(c + Vector2(r, -r), c + Vector2(-r, r), Color(1, 0.3, 0.25), 2.0)


static func gem(color: Color, shape: int = 0, dim: bool = false, cracked: bool = false) -> Gem:
	var g := Gem.new(color, shape)
	g.dim = dim
	g.cracked = cracked
	return g


## Keeps a menu usable WITHOUT A MOUSE: whenever nothing has keyboard / controller focus (a list was rebuilt, a
## button was freed), the first enabled button inside `root` takes it. Returns true if focus had to be given.
static func ensure_focus(root: Node, viewport: Viewport) -> bool:
	var current := viewport.gui_get_focus_owner()
	if current != null and current.is_visible_in_tree() and root.is_ancestor_of(current):
		return false
	for node in root.find_children("*", "Button", true, false):
		var b := node as Button
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
			return true
	return false


## Presses the focused button when the accept button (Cross / A / Enter / Space) is pushed. Done by hand so it works
## the same for keyboard and any controller, and the push is not also seen by the game. Returns true when handled.
static func press_focused(event: InputEvent, viewport: Viewport) -> bool:
	if not (event.is_action_pressed("ui_accept") or event.is_action_pressed("attack")):
		return false
	var focused := viewport.gui_get_focus_owner() as BaseButton
	if focused == null or focused.disabled:
		return false
	focused.pressed.emit()
	return true


## Removes and frees every child of a container.
static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
