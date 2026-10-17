extends Node2D
## A staircase. Stand next to it and press the interact key to use it.
## going_up = false: leads one floor DEEPER (the base's stairs and every extraction room's stairs).
## going_up = true:  leads one floor UP (every start room has one; floor 1's lead back to the base).
## What the stairs do is decided by Game, which listens to GameManager.descend_requested /
## ascend_requested.

static var _glow_texture: GradientTexture2D

@export var prompt_text: String = "DESCEND"
@export var glow_color: Color = Color(0.4, 0.7, 1.0)
@export var going_up: bool = false

const WIDTH: float = 56.0
const HEIGHT: float = 44.0
const STEP_COUNT: int = 5
const STONE := Color(0.46, 0.34, 0.36)
const STONE_DARK := Color(0.24, 0.17, 0.21)

var _time: float = 0.0
## True while a boss still guards the way down: the stairs are hidden and cannot be used.
var locked: bool = false


func _ready() -> void:
	add_to_group("interactable")
	if going_up:
		prompt_text = "ASCEND"
		glow_color = Color(1.0, 0.82, 0.5) # warm light from above
	var light := PointLight2D.new()
	light.set_script(preload("res://scripts/light_flicker.gd"))
	light.texture = _get_glow()
	light.color = glow_color
	light.energy = 0.9
	light.texture_scale = 1.3
	light.position = Vector2(0, 4)
	add_child(light)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# ------------------------------------------------------------------ interactable protocol

func get_prompt() -> String:
	return prompt_text


func can_interact() -> bool:
	return not locked


## Hides the stairs until a boss is beaten (see BossRoomController).
func lock() -> void:
	locked = true
	visible = false


## Reveals the stairs. Animated: they grow out of the floor with a flash of light.
func unlock(animated: bool = true) -> void:
	locked = false
	visible = true
	if animated:
		scale = Vector2(0.25, 0.25)
		modulate = Color(2.2, 2.2, 2.6, 0.0)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(self, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "modulate", Color.WHITE, 0.9)


func interact(_by: Node) -> void:
	if going_up:
		GameManager.ascend_requested.emit()
	else:
		GameManager.descend_requested.emit()


# ------------------------------------------------------------------ drawing

static func _get_glow() -> GradientTexture2D:
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
	var half := Vector2(WIDTH, HEIGHT) * 0.5
	# Stone frame around the opening.
	draw_rect(Rect2(-half - Vector2(4, 4), Vector2(WIDTH + 8, HEIGHT + 8)), STONE_DARK)
	draw_rect(Rect2(-half - Vector2(2, 2), Vector2(WIDTH + 4, HEIGHT + 4)), STONE)
	# The stairwell: steps get darker the deeper they go, with a slow pulse of blue from below.
	var pulse := 0.5 + 0.5 * sin(_time * 2.0)
	var step_height := HEIGHT / float(STEP_COUNT)
	for i in STEP_COUNT:
		var depth_factor := float(i) / float(STEP_COUNT - 1)
		var shade := Color(0.30, 0.22, 0.28).lerp(Color(0.02, 0.02, 0.05), depth_factor)
		var inset := 3.0 * float(i)
		var rect := Rect2(-half.x + inset, -half.y + step_height * float(i), WIDTH - inset * 2.0, step_height)
		draw_rect(rect, shade)
		draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 2.0), Color(0.62, 0.50, 0.50).lerp(shade, depth_factor))
	var glow_a := 0.10 + 0.12 * pulse
	if going_up:
		# Light comes from above, and a chevron points up.
		draw_rect(Rect2(-half.x + 6, -half.y + 2, WIDTH - 12, step_height * 1.4), Color(glow_color.r, glow_color.g, glow_color.b, glow_a + 0.1))
		var tip := Vector2(0, -4.0 - 2.0 * pulse)
		var chevron := PackedVector2Array([tip + Vector2(-8, 8), tip, tip + Vector2(8, 8)])
		draw_polyline(chevron, Color(glow_color.r, glow_color.g, glow_color.b, 0.9), 2.0)
	else:
		draw_rect(Rect2(-half.x + 6, half.y - step_height * 1.6, WIDTH - 12, step_height * 1.4), Color(glow_color.r, glow_color.g, glow_color.b, glow_a))
