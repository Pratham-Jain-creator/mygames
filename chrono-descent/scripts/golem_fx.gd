class_name GolemFX
extends RefCounted
## Effects of the golems, built in code from the cleaned FX sheets (golem_mini_fx_clean.png in cyan for the
## mini golem, golem_boss_fx_clean.png in lava orange for the boss). Both sheets have the same layout, the
## mini one at 75% size, so every function takes a `kind`.
## The sheets are loaded lazily, so a missing / not yet imported sheet just means no effect, never a crash.
##
## Slam telegraphs and shockwaves are ELLIPSES (the art is drawn in perspective); damage zones that go with
## them use the same ellipse, see ellipse_contains().

enum Kind { MINI, BOSS }

const SHEET_PATHS: Dictionary = {
	Kind.MINI: "res://assets/sprites/enemies/mobs/golem_mini_fx_clean.png",
	Kind.BOSS: "res://assets/sprites/enemies/boss/golem_boss_fx_clean.png",
}
## Height / width of the ground ellipses (the slam circle and the shockwave ring).
const ELLIPSE_RATIO: float = 0.636
## The FX sheets are drawn at the golem sheets' NATIVE size, and the golems are shown at this fraction of it
## (their sprite scale). Effects that are not sized by a radius (cracks, dust, impacts, chips) use it too.
const FX_BASE_SCALE: float = 0.55

## Frame rectangles on the sheets (found with the FX analysis tool; irregular rows use even cells).
const RECTS: Dictionary = {
	Kind.BOSS: {
		"orb": [Rect2(22, 102, 54, 54), Rect2(84, 100, 58, 58), Rect2(150, 102, 54, 54), Rect2(210, 98, 62, 62)],
		"charge": [Rect2(16, 172, 96, 104), Rect2(112, 172, 96, 104), Rect2(208, 172, 96, 104), Rect2(304, 172, 96, 104)],
		"burst": [Rect2(16, 286, 96, 100), Rect2(112, 286, 96, 100), Rect2(208, 286, 96, 100), Rect2(304, 286, 96, 100), Rect2(400, 286, 96, 100), Rect2(496, 286, 96, 100)],
		"aim": [Rect2(16, 402, 1024, 12)],
		"chips": [Rect2(20, 452, 24, 22), Rect2(50, 450, 24, 26), Rect2(86, 452, 22, 24), Rect2(116, 450, 26, 24), Rect2(148, 454, 24, 22), Rect2(182, 452, 24, 26), Rect2(212, 452, 22, 24), Rect2(242, 454, 26, 24)],
		"ring": [Rect2(16, 716, 256, 168), Rect2(272, 716, 256, 168), Rect2(528, 716, 256, 168), Rect2(784, 716, 256, 168), Rect2(1040, 716, 256, 168), Rect2(1296, 716, 256, 168), Rect2(1552, 716, 256, 168), Rect2(1808, 716, 256, 168)],
		"cracks": [Rect2(126, 994, 32, 22), Rect2(362, 984, 64, 42), Rect2(588, 964, 130, 80), Rect2(816, 946, 184, 124), Rect2(1048, 932, 222, 148), Rect2(1304, 932, 222, 148)],
		"circle": [Rect2(24, 1348, 242, 154), Rect2(280, 1348, 242, 154), Rect2(536, 1348, 242, 154), Rect2(792, 1348, 242, 154)],
		"dust": [Rect2(50, 1586, 28, 20), Rect2(140, 1580, 42, 30), Rect2(228, 1574, 58, 38), Rect2(316, 1568, 74, 48), Rect2(404, 1556, 188, 66)],
	},
	Kind.MINI: {
		"orb": [Rect2(30, 102, 36, 36), Rect2(75, 99, 42, 42), Rect2(126, 102, 36, 36), Rect2(171, 99, 42, 42)],
		"charge": [Rect2(12, 164, 72, 80), Rect2(84, 164, 72, 80), Rect2(156, 164, 72, 80), Rect2(228, 164, 72, 80)],
		"burst": [Rect2(12, 260, 72, 76), Rect2(84, 260, 72, 76), Rect2(156, 260, 72, 76), Rect2(228, 260, 72, 76), Rect2(300, 260, 72, 76), Rect2(372, 260, 72, 76)],
		"aim": [Rect2(24, 360, 768, 9)],
		"chips": [Rect2(27, 435, 24, 21), Rect2(57, 435, 21, 24), Rect2(90, 435, 21, 24), Rect2(117, 435, 24, 21), Rect2(147, 438, 24, 21), Rect2(180, 435, 21, 24), Rect2(207, 435, 21, 24), Rect2(237, 438, 24, 21)],
		"ring": [Rect2(12, 680, 192, 128), Rect2(204, 680, 192, 128), Rect2(396, 680, 192, 128), Rect2(588, 680, 192, 128), Rect2(780, 680, 192, 128), Rect2(972, 680, 192, 128), Rect2(1164, 680, 192, 128), Rect2(1356, 680, 192, 128)],
		"cracks": [Rect2(105, 900, 24, 18), Rect2(282, 894, 48, 30), Rect2(453, 879, 96, 57), Rect2(624, 864, 138, 93), Rect2(798, 855, 165, 108), Rect2(990, 855, 165, 108)],
		"circle": [Rect2(30, 1191, 180, 114), Rect2(222, 1191, 180, 114), Rect2(414, 1191, 180, 114), Rect2(606, 1191, 180, 114)],
		"dust": [Rect2(48, 1380, 21, 15), Rect2(117, 1377, 30, 21), Rect2(183, 1371, 42, 30), Rect2(249, 1368, 54, 36), Rect2(315, 1359, 141, 48)],
	},
}

static var _sheets: Dictionary = {}


## Spinning white arcs around a golem while it spins (drawn, not sprites).
class SpinArcs extends Node2D:
	const SQUASH: float = 0.636 # same as GolemFX.ELLIPSE_RATIO
	var radius: float = 40.0
	var color: Color = Color(1, 1, 1, 0.8)
	var speed: float = 14.0
	var _angle: float = 0.0

	func _process(delta: float) -> void:
		_angle += speed * delta
		queue_redraw()

	func _draw() -> void:
		# an ellipse squashed like the ground effects, with two sweeping crescents
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SQUASH))
		for i in 2:
			var start := _angle + PI * float(i)
			draw_arc(Vector2.ZERO, radius, start, start + 1.9, 18, color, 3.0)
			draw_arc(Vector2.ZERO, radius * 0.82, start + 0.3, start + 1.5, 14, Color(color.r, color.g, color.b, color.a * 0.5), 2.0)


## The sheet of a kind (null while it has not been imported: effects then simply do not show).
static func sheet(kind: int) -> Texture2D:
	if not _sheets.has(kind):
		var path: String = SHEET_PATHS[kind]
		_sheets[kind] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _sheets[kind]


static func rects(kind: int, key: String) -> Array:
	return (RECTS[kind] as Dictionary)[key]


## True when `point` is inside the ground ellipse of half-width `radius_x` centred at `center`.
static func ellipse_contains(center: Vector2, radius_x: float, point: Vector2) -> bool:
	var d := point - center
	var radius_y := radius_x * ELLIPSE_RATIO
	return (d.x * d.x) / (radius_x * radius_x) + (d.y * d.y) / (radius_y * radius_y) <= 1.0


static func frames(kind: int, key: String, fps: float, loop: bool) -> SpriteFrames:
	var frames_res := SpriteFrames.new()
	frames_res.set_animation_loop(&"default", loop)
	frames_res.set_animation_speed(&"default", fps)
	var tex := sheet(kind)
	if tex == null:
		return frames_res
	for rect in rects(kind, key):
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = rect
		frames_res.add_frame(&"default", atlas)
	return frames_res


static func animated(parent: Node, pos: Vector2, kind: int, key: String, fps: float, loop: bool, sprite_scale: float, z: int = 3) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames(kind, key, fps, loop)
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.z_index = z
	parent.add_child(sprite)
	sprite.global_position = pos
	if sprite.sprite_frames.get_frame_count(&"default") > 0:
		sprite.play(&"default")
	return sprite


## The filling red / green circle on the floor that warns where a slam will land. It fills up over `seconds`.
static func slam_telegraph(parent: Node, pos: Vector2, kind: int, radius_x: float, seconds: float) -> AnimatedSprite2D:
	var cell: Rect2 = rects(kind, "circle")[0]
	var sprite := animated(parent, pos, kind, "circle", 4.0 / maxf(seconds, 0.1), false, 2.0 * radius_x / cell.size.x, 0)
	sprite.modulate.a = 0.0
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", 0.95, 0.15)
	tween.tween_interval(maxf(seconds - 0.15, 0.0) + 0.1)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.15)
	tween.tween_callback(sprite.queue_free)
	return sprite


## An expanding ground shockwave ring.
static func shock_ring(parent: Node, pos: Vector2, kind: int, radius_x: float, seconds: float = 0.55) -> void:
	var cell: Rect2 = rects(kind, "ring")[0]
	var sprite := animated(parent, pos, kind, "ring", 8.0 / maxf(seconds, 0.1), false, 2.0 * radius_x / (cell.size.x * 0.94), 0)
	sprite.animation_finished.connect(sprite.queue_free, CONNECT_ONE_SHOT)


## Cracks spreading over the floor, which stay a moment and fade.
static func cracks(parent: Node, pos: Vector2, kind: int, sprite_scale: float = 1.0, stay: float = 1.6) -> void:
	var sprite := animated(parent, pos, kind, "cracks", 16.0, false, sprite_scale * FX_BASE_SCALE, 0)
	var tween := sprite.create_tween()
	tween.tween_interval(stay)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.8)
	tween.tween_callback(sprite.queue_free)


static func dust(parent: Node, pos: Vector2, kind: int, sprite_scale: float = 1.0) -> void:
	var sprite := animated(parent, pos, kind, "dust", 11.0, false, sprite_scale * FX_BASE_SCALE, 5)
	sprite.animation_finished.connect(sprite.queue_free, CONNECT_ONE_SHOT)


## The small explosion where an orb lands.
static func impact(parent: Node, pos: Vector2, kind: int, sprite_scale: float = 1.0) -> void:
	var sprite := animated(parent, pos, kind, "burst", 22.0, false, sprite_scale * FX_BASE_SCALE, 5)
	sprite.animation_finished.connect(sprite.queue_free, CONNECT_ONE_SHOT)


## Rock chips flung up by an impact.
static func chips(parent: Node, pos: Vector2, kind: int, amount: int = 10, spread: float = 110.0) -> void:
	var tex := sheet(kind)
	if tex == null:
		return
	var particles := CPUParticles2D.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = rects(kind, "chips")[0]
	particles.texture = atlas
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = 0.75
	particles.explosiveness = 1.0
	particles.spread = 180.0
	particles.direction = Vector2.UP
	particles.initial_velocity_min = spread * 0.45
	particles.initial_velocity_max = spread
	particles.gravity = Vector2(0.0, 320.0)
	particles.angular_velocity_min = -360.0
	particles.angular_velocity_max = 360.0
	particles.scale_amount_min = 0.5 * FX_BASE_SCALE
	particles.scale_amount_max = 0.9 * FX_BASE_SCALE
	particles.z_index = 6
	parent.add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## The dashed aim line of a throw: from `from` along `dir`, `length` px long.
static func aim_line(parent: Node, from: Vector2, dir: Vector2, length: float, kind: int) -> Sprite2D:
	var tex := sheet(kind)
	if tex == null:
		return null
	var cell: Rect2 = rects(kind, "aim")[0]
	var line := Sprite2D.new()
	line.texture = tex
	line.region_enabled = true
	var line_scale := 0.7
	line.region_rect = Rect2(cell.position.x, cell.position.y, minf(length / line_scale, cell.size.x), cell.size.y)
	line.centered = false
	line.offset = Vector2(0.0, -cell.size.y * 0.5)
	line.scale = Vector2.ONE * line_scale
	line.rotation = dir.angle()
	line.z_index = 1
	line.modulate.a = 0.0
	parent.add_child(line)
	line.global_position = from
	line.create_tween().tween_property(line, "modulate:a", 0.9, 0.15)
	return line


static func spin_arcs(host: Node2D, radius: float) -> SpinArcs:
	var arcs := SpinArcs.new()
	arcs.radius = radius
	arcs.z_index = 6
	host.add_child(arcs)
	return arcs
