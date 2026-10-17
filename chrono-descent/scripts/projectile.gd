class_name Projectile
extends Area2D
## Enemy projectile (arrow, magic bolt, fireball). Spawned and configured by RangedEnemy.
## Hits the player (anything with take_damage) or disappears against walls.

enum Style { ARROW, BOLT, FIREBALL }

static var _glow_texture: GradientTexture2D

var velocity: Vector2 = Vector2.ZERO
var damage: int = 8
var knockback: float = 100.0
var style: Style = Style.ARROW
## Radians per second the projectile may turn toward the player. 0 = flies straight.
var homing_turn: float = 0.0
var lifetime: float = 3.0
var target: Node2D
## Player-fired shots (arrows, bolts, spells): they hit enemies (layer 4) and walls, never the player.
var friendly: bool = false


func setup(dir: Vector2, speed: float, dmg: int, kb: float, projectile_style: Style, turn: float, life: float, homing_target: Node2D) -> void:
	velocity = dir.normalized() * speed
	damage = dmg
	knockback = kb
	style = projectile_style
	homing_turn = turn
	lifetime = life
	target = homing_target


func _ready() -> void:
	z_index = 4
	if friendly:
		collision_layer = 0
		collision_mask = 1 | 4
	body_entered.connect(_on_body_entered)
	rotation = velocity.angle()
	if style != Style.ARROW:
		var light := PointLight2D.new()
		light.texture = _get_glow()
		light.color = Color(0.7, 0.45, 1.0) if style == Style.BOLT else Color(1.0, 0.55, 0.2)
		light.energy = 0.9
		light.texture_scale = 0.7
		add_child(light)
	queue_redraw()


static func _get_glow() -> GradientTexture2D:
	if _glow_texture == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1), Color(0.4, 0.4, 0.4), Color(0, 0, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 64
		t.height = 64
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		_glow_texture = t
	return _glow_texture


func _draw() -> void:
	match style:
		Style.ARROW:
			draw_line(Vector2(-7, 0), Vector2(3, 0), Color(0.62, 0.45, 0.28), 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2(6, 0), Vector2(2, -2), Vector2(2, 2)]), Color(0.85, 0.88, 0.95))
			draw_line(Vector2(-7, 0), Vector2(-9, -2), Color(0.9, 0.9, 0.9), 1.0)
			draw_line(Vector2(-7, 0), Vector2(-9, 2), Color(0.9, 0.9, 0.9), 1.0)
		Style.BOLT:
			draw_circle(Vector2.ZERO, 4.0, Color(0.55, 0.25, 0.95, 0.55))
			draw_circle(Vector2.ZERO, 2.5, Color(0.8, 0.55, 1.0))
			draw_circle(Vector2.ZERO, 1.2, Color.WHITE)
		Style.FIREBALL:
			draw_circle(Vector2.ZERO, 5.5, Color(1.0, 0.35, 0.1, 0.55))
			draw_circle(Vector2.ZERO, 3.6, Color(1.0, 0.6, 0.15))
			draw_circle(Vector2.ZERO, 1.8, Color(1.0, 0.95, 0.6))


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if homing_turn > 0.0 and is_instance_valid(target):
		var want := (target.global_position - global_position).angle()
		var cur := velocity.angle()
		var diff := wrapf(want - cur, -PI, PI)
		var step := clampf(diff, -homing_turn * delta, homing_turn * delta)
		velocity = velocity.rotated(step)
	rotation = velocity.angle()
	global_position += velocity * delta


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage, global_position, knockback)
	queue_free()
