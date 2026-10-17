extends Node2D
## The journal on its lectern, in the base. Press the interact key next to it to read the
## story of the dungeon (journal_panel.gd). A soft glow draws the eye to it.

const PANEL_SCRIPT: Script = preload("res://scripts/journal_panel.gd")
const FLICKER: Script = preload("res://scripts/light_flicker.gd")
const WOOD := Color(0.36, 0.22, 0.14)
const WOOD_DARK := Color(0.2, 0.12, 0.09)
const PAGE := Color(0.88, 0.80, 0.62)
const INK := Color(0.4, 0.3, 0.2)

static var _glow_texture: GradientTexture2D

var _time: float = 0.0


func _ready() -> void:
	add_to_group("interactable")
	var light := PointLight2D.new()
	light.set_script(FLICKER)
	light.texture = _glow()
	light.color = Color(1.0, 0.78, 0.45)
	light.energy = 0.7
	light.texture_scale = 0.9
	light.position = Vector2(0, -8)
	add_child(light)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# ------------------------------------------------------------------ interactable protocol

func get_prompt() -> String:
	return "READ JOURNAL"


func can_interact() -> bool:
	return true


func interact(_by: Node) -> void:
	var panel := CanvasLayer.new()
	panel.set_script(PANEL_SCRIPT)
	get_tree().root.add_child(panel)


# ------------------------------------------------------------------ drawing

static func _glow() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1), Color(0.4, 0.4, 0.4), Color(0, 0, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		_glow_texture = tex
	return _glow_texture


func _draw() -> void:
	# Lectern: base, stem and a slanted top.
	draw_rect(Rect2(-10, 8, 20, 6), WOOD_DARK)
	draw_rect(Rect2(-5, -2, 10, 12), WOOD)
	draw_colored_polygon(PackedVector2Array([Vector2(-14, -2), Vector2(14, -2), Vector2(10, -10), Vector2(-10, -10)]), WOOD)
	draw_line(Vector2(-14, -2), Vector2(14, -2), WOOD_DARK, 2.0)
	# Open book resting on it, with faint "writing" lines and a bookmark.
	draw_colored_polygon(PackedVector2Array([Vector2(-11, -11), Vector2(0, -9), Vector2(11, -11), Vector2(10, -17), Vector2(0, -15), Vector2(-10, -17)]), PAGE)
	draw_line(Vector2(0, -15), Vector2(0, -9), WOOD_DARK, 1.0)
	for i in 3:
		var y := -15.0 + float(i) * 1.6
		draw_line(Vector2(-8, y), Vector2(-2, y + 0.8), INK, 1.0)
		draw_line(Vector2(2, y + 0.8), Vector2(8, y), INK, 1.0)
	# A thin red ribbon: the first hint that this book is about death.
	draw_line(Vector2(5, -11), Vector2(6, -6), Color(0.75, 0.1, 0.12), 1.5)
	# Sparkle above the book so the player notices it.
	var sparkle := 0.5 + 0.5 * sin(_time * 3.0)
	draw_circle(Vector2(0, -22.0 - sparkle * 2.0), 1.0 + sparkle * 0.6, Color(1.0, 0.9, 0.6, 0.5 + sparkle * 0.4))
