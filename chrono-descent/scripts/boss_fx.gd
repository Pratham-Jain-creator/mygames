class_name BossFX
extends RefCounted
## Visual effects of the boss fights, built in code (they are short-lived). The sprites come from the cleaned
## effects sheet (slime_queen_boss_fx_clean.png); the particle bursts and shockwave rings are drawn here.

const SHEET: Texture2D = preload("res://assets/sprites/enemies/boss/slime_queen_boss_fx_clean.png")
const SUMMON_CIRCLE: Array = [
	Rect2(24, 472, 178, 178), Rect2(216, 472, 178, 178), Rect2(408, 472, 178, 178), Rect2(600, 472, 178, 178),
	Rect2(792, 472, 178, 178), Rect2(984, 472, 178, 178), Rect2(1176, 472, 178, 178), Rect2(1368, 472, 178, 178),
]
const ALERT: Array = [Rect2(18, 162, 28, 28), Rect2(50, 160, 28, 28), Rect2(82, 160, 28, 26), Rect2(114, 160, 28, 28)]
const TARGET: Array = [Rect2(22, 358, 86, 86), Rect2(116, 356, 90, 90), Rect2(210, 354, 94, 94), Rect2(308, 356, 90, 90)]
const PUFF: Array = [Rect2(30, 710, 36, 26), Rect2(96, 710, 32, 26), Rect2(160, 706, 36, 30), Rect2(218, 704, 48, 32), Rect2(272, 702, 120, 40)]
## The red chevron bar that warns where a dash will go.
const LANE: Rect2 = Rect2(16, 232, 768, 32)
const LANE_SCALE: float = 0.5


## An expanding ring of light (shockwaves).
class ShockRing extends Node2D:
	var color: Color = Color.WHITE
	var max_radius: float = 80.0
	var life: float = 0.4
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_t / life, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - k, 3.0)
		var radius := max_radius * eased
		var alpha := 1.0 - k
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 56, Color(color.r, color.g, color.b, alpha), 3.0)
		draw_arc(Vector2.ZERO, radius * 0.82, 0.0, TAU, 56, Color(color.r, color.g, color.b, alpha * 0.45), 2.0)


static func _frames(rects: Array, fps: float, loop: bool) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.set_animation_loop(&"default", loop)
	frames.set_animation_speed(&"default", fps)
	for rect in rects:
		var tex := AtlasTexture.new()
		tex.atlas = SHEET
		tex.region = rect
		frames.add_frame(&"default", tex)
	return frames


static func _animated(parent: Node, pos: Vector2, rects: Array, fps: float, loop: bool, sprite_scale: float, z: int) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _frames(rects, fps, loop)
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.z_index = z
	parent.add_child(sprite)
	sprite.global_position = pos
	sprite.play(&"default")
	return sprite


## The pink summoning circle: fades in, spins for `seconds`, fades out.
static func summon_circle(parent: Node, pos: Vector2, seconds: float, sprite_scale: float = 0.5) -> AnimatedSprite2D:
	var sprite := _animated(parent, pos, SUMMON_CIRCLE, 12.0, true, sprite_scale, 0)
	sprite.modulate = Color(1, 1, 1, 0)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", 0.95, 0.25)
	tween.tween_interval(maxf(seconds - 0.55, 0.0))
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(sprite.queue_free)
	return sprite


## The red "!" above a boss that is about to do something dangerous. Child of the boss, so it follows it.
static func alert(boss: Node2D, seconds: float, height: float = -46.0) -> AnimatedSprite2D:
	var sprite := _animated(boss, boss.global_position, ALERT, 12.0, true, 0.9, 6)
	sprite.position = Vector2(0.0, height)
	var tween := sprite.create_tween()
	tween.tween_interval(seconds)
	tween.tween_callback(sprite.queue_free)
	return sprite


## The warning lane of a dash: a red chevron bar from `from` along `dir`. Returns it so the caller can keep it
## pointing at the player until the aim is locked.
static func dash_lane(parent: Node, from: Vector2, dir: Vector2, length: float) -> Sprite2D:
	var lane := Sprite2D.new()
	lane.texture = SHEET
	lane.region_enabled = true
	lane.region_rect = Rect2(LANE.position.x, LANE.position.y, minf(length / LANE_SCALE, LANE.size.x), LANE.size.y)
	lane.centered = false
	lane.offset = Vector2(0.0, -LANE.size.y * 0.5)
	lane.scale = Vector2.ONE * LANE_SCALE
	lane.rotation = dir.angle()
	lane.z_index = 0
	lane.modulate = Color(1, 1, 1, 0)
	parent.add_child(lane)
	lane.global_position = from
	var tween := lane.create_tween()
	tween.tween_property(lane, "modulate:a", 0.85, 0.12)
	return lane


## The blue spawn puff (a slime pops into the world).
static func puff(parent: Node, pos: Vector2, sprite_scale: float = 0.8) -> void:
	var sprite := _animated(parent, pos, PUFF, 14.0, false, sprite_scale, 5)
	sprite.animation_finished.connect(sprite.queue_free, CONNECT_ONE_SHOT)


## Red target marker on the floor (where something is about to land).
static func target_marker(parent: Node, pos: Vector2, seconds: float, sprite_scale: float = 0.5) -> AnimatedSprite2D:
	var sprite := _animated(parent, pos, TARGET, 10.0, true, sprite_scale, 0)
	sprite.modulate = Color(1, 1, 1, 0.9)
	var tween := sprite.create_tween()
	tween.tween_interval(seconds)
	tween.tween_callback(sprite.queue_free)
	return sprite


## A shockwave ring.
static func ring(parent: Node, pos: Vector2, color: Color, max_radius: float, seconds: float = 0.45) -> void:
	var r := ShockRing.new()
	r.color = color
	r.max_radius = max_radius
	r.life = seconds
	r.z_index = 5
	parent.add_child(r)
	r.global_position = pos


## A one-shot burst of slime droplets.
static func burst(parent: Node, pos: Vector2, color: Color, amount: int = 20, speed: float = 95.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.65
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector2.UP
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0.0, 140.0)
	p.scale_amount_min = 1.6
	p.scale_amount_max = 3.4
	p.color = color
	p.z_index = 5
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
