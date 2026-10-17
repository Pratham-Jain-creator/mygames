class_name Altar
extends Node2D
## A thing the player uses with the interact key: an altar, a chest, a basin, a workbench, a terminal... Its job is
## the prompt and the callback; its looks are drawn in code (a few simple shapes per STYLE), so there is no art
## to import and every special room can have its own props.
##
## Create one with Altar.make(). The callback receives the player: `func(by) -> void`.

## The things that can be drawn.
const STYLES: Array[StringName] = [&"altar", &"basin", &"chest", &"table", &"anvil", &"corpse", &"terminal", &"workbench", &"hole", &"npc", &"monolith", &"shrine", &"mold", &"font", &"reaper"]

static var _light_texture: GradientTexture2D

var style: StringName = &"altar"
var color: Color = Color(0.6, 0.85, 1.0)
var prompt: String = "USE"
var callback: Callable
## False = shown but not usable (dimmed). `disabled_prompt` is what the prompt says instead.
var enabled: bool = true
var disabled_prompt: String = ""
## Chest style: drawn open.
var opened: bool = false

var _clock: float = 0.0
var _light: PointLight2D
## The reaper style is a real animated character (see SpriteLib.reaper): he faces the player and gestures.
var _sprite: AnimatedSprite2D
var _gesture: float = 0.0


## Puts an Altar into `parent` at a world position.
static func make(parent: Node, pos: Vector2, altar_style: StringName, altar_prompt: String, altar_color: Color, on_use: Callable) -> Altar:
	var altar := Altar.new()
	altar.style = altar_style
	altar.prompt = altar_prompt
	altar.color = altar_color
	altar.callback = on_use
	parent.add_child(altar)
	altar.global_position = pos
	return altar


func _ready() -> void:
	add_to_group("interactable")
	z_index = 1
	_clock = randf() * TAU
	if _light_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.4, 0.4, 0.4, 1), Color(0, 0, 0, 1)])
		_light_texture = GradientTexture2D.new()
		_light_texture.gradient = gradient
		_light_texture.width = 128
		_light_texture.height = 128
		_light_texture.fill = GradientTexture2D.FILL_RADIAL
		_light_texture.fill_from = Vector2(0.5, 0.5)
		_light_texture.fill_to = Vector2(0.5, 0.0)
	_light = PointLight2D.new()
	_light.texture = _light_texture
	_light.color = color
	_light.energy = 0.55
	_light.texture_scale = 0.9
	_light.position = Vector2(0, -10)
	add_child(_light)
	if style == &"reaper":
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = SpriteLib.reaper()
		_sprite.scale = Vector2(0.6, 0.6)
		_sprite.position = Vector2(0, -15)
		add_child(_sprite)
		_sprite.play("idle_down")


func _process(delta: float) -> void:
	_clock += delta
	_light.energy = (0.55 if enabled else 0.12) + 0.08 * sin(_clock * 3.0)
	if _sprite != null:
		_update_reaper(delta)
	queue_redraw()


func _update_reaper(delta: float) -> void:
	_gesture = maxf(0.0, _gesture - delta)
	var to := Vector2.DOWN
	var near := false
	var player := GameManager.player
	if is_instance_valid(player):
		to = player.global_position - global_position
		near = to.length() < 80.0
	var dir := "down"
	if absf(to.x) > absf(to.y):
		dir = "right" if to.x > 0.0 else "left"
	else:
		dir = "down" if to.y >= 0.0 else "up"
	var base := "cast" if _gesture > 0.0 else ("beckon" if near and enabled else "idle")
	var full := "%s_%s" % [base, dir]
	if _sprite.animation != full:
		_sprite.play(full)


# ------------------------------------------------------------------ interaction

func can_interact() -> bool:
	return visible and (enabled or disabled_prompt != "")


func get_prompt() -> String:
	return prompt if enabled else disabled_prompt


func interact(by: Node) -> void:
	if enabled and callback.is_valid():
		_gesture = 0.7
		callback.call(by)


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var c := color if enabled else color.darkened(0.6)
	var bob := sin(_clock * 3.0) * 1.2
	var stone := Color(0.34, 0.31, 0.36)
	var stone_dark := Color(0.2, 0.18, 0.23)
	draw_circle(Vector2(0, 2), 8.0, Color(0, 0, 0, 0.2)) # shadow
	match style:
		&"altar":
			draw_rect(Rect2(-7, -8, 14, 9), stone_dark)
			draw_rect(Rect2(-9, -11, 18, 4), stone)
			draw_circle(Vector2(0, -19 + bob), 4.5, c)
			draw_circle(Vector2(-1.5, -20.5 + bob), 1.5, Color(1, 1, 1, 0.8))
		&"basin", &"font":
			draw_rect(Rect2(-9, -6, 18, 7), stone_dark)
			draw_colored_polygon(_ellipse(Vector2(0, -7), 12, 5), stone)
			draw_colored_polygon(_ellipse(Vector2(0, -7), 9.5, 3.6), c.darkened(0.15))
			draw_colored_polygon(_ellipse(Vector2(-2 + bob * 0.4, -7.8), 3.5, 1.3), Color(1, 1, 1, 0.25))
		&"chest":
			draw_rect(Rect2(-9, -10, 18, 11), Color(0.45, 0.28, 0.14))
			draw_rect(Rect2(-9, -4, 18, 2), Color(0.7, 0.62, 0.3))
			if opened:
				draw_rect(Rect2(-9, -20, 18, 8), Color(0.5, 0.32, 0.16))
				draw_circle(Vector2(0, -12), 5.0, Color(c.r, c.g, c.b, 0.5))
			else:
				draw_rect(Rect2(-9, -15, 18, 6), Color(0.52, 0.33, 0.16))
				draw_rect(Rect2(-2, -11, 4, 5), c)
		&"table":
			draw_rect(Rect2(-13, -9, 26, 4), Color(0.4, 0.27, 0.16))
			draw_rect(Rect2(-12, -5, 3, 6), Color(0.3, 0.2, 0.12))
			draw_rect(Rect2(9, -5, 3, 6), Color(0.3, 0.2, 0.12))
			for i in 3:
				draw_circle(Vector2(-7 + 7 * i, -13 + bob * 0.3), 3.0, c.lightened(0.1 * i))
		&"anvil":
			draw_rect(Rect2(-6, -6, 12, 7), stone_dark)
			draw_colored_polygon(PackedVector2Array([Vector2(-12, -13), Vector2(12, -13), Vector2(8, -6), Vector2(-8, -6)]), Color(0.4, 0.4, 0.46))
			draw_rect(Rect2(-12, -14, 24, 2), c)
		&"corpse":
			draw_colored_polygon(_ellipse(Vector2(0, -3), 13, 5), Color(0.42, 0.4, 0.38))
			draw_circle(Vector2(-10, -4), 4.0, Color(0.62, 0.55, 0.48))
			draw_rect(Rect2(2, -9, 8, 6), c)
		&"terminal":
			draw_rect(Rect2(-8, -22, 16, 22), Color(0.28, 0.3, 0.36))
			draw_rect(Rect2(-6, -19, 12, 9), c.darkened(0.3))
			draw_rect(Rect2(-6, -19, 12, 9), c, false, 1.0)
			for i in 3:
				draw_rect(Rect2(-5 + 4 * i, -7, 3, 3), c if (int(_clock * 2.0) + i) % 3 == 0 else c.darkened(0.6))
		&"workbench":
			draw_rect(Rect2(-17, -10, 34, 5), Color(0.42, 0.28, 0.17))
			draw_rect(Rect2(-15, -5, 4, 7), Color(0.3, 0.2, 0.12))
			draw_rect(Rect2(11, -5, 4, 7), Color(0.3, 0.2, 0.12))
			draw_rect(Rect2(-12, -15, 8, 5), c.darkened(0.2))
			draw_circle(Vector2(6, -14 + bob * 0.3), 3.5, c)
			draw_line(Vector2(-2, -12), Vector2(3, -17), Color(0.7, 0.7, 0.75), 1.5)
		&"hole":
			draw_colored_polygon(_ellipse(Vector2(0, -2), 15, 7), stone)
			draw_colored_polygon(_ellipse(Vector2(0, -2), 12, 5), Color(0.02, 0.01, 0.03))
			draw_colored_polygon(_ellipse(Vector2(0, -2), 6 + bob, 2.5), c.darkened(0.7))
		&"npc":
			draw_colored_polygon(PackedVector2Array([Vector2(0, -22), Vector2(9, 0), Vector2(-9, 0)]), Color(0.22, 0.18, 0.26))
			draw_circle(Vector2(0, -16), 5.0, Color(0.14, 0.11, 0.17))
			draw_circle(Vector2(-1.7, -16), 1.0, c)
			draw_circle(Vector2(1.7, -16), 1.0, c)
		&"monolith":
			draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(6, 0), Vector2(5, -30), Vector2(0, -34), Vector2(-5, -30)]), stone_dark)
			draw_line(Vector2(0, -26), Vector2(0, -8), c, 2.0)
			draw_line(Vector2(-3, -20), Vector2(3, -14), c, 1.5)
		&"shrine":
			draw_rect(Rect2(-8, -14, 3, 14), stone)
			draw_rect(Rect2(5, -14, 3, 14), stone)
			draw_rect(Rect2(-10, -17, 20, 4), stone)
			draw_circle(Vector2(0, -8 + bob), 3.5, c)
		&"mold":
			draw_rect(Rect2(-11, -10, 22, 10), stone_dark)
			draw_rect(Rect2(-9, -8, 18, 6), Color(0.9, 0.4, 0.15, 0.85) if enabled else Color(0.3, 0.2, 0.2))
			draw_colored_polygon(PackedVector2Array([Vector2(-1, -18), Vector2(1, -18), Vector2(2, -9), Vector2(-2, -9)]), Color(0.75, 0.78, 0.85))


func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return points
