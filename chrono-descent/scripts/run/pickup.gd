class_name Pickup
extends Node2D
## Something lying on the floor that is collected by walking close: ash, a macabre material, a blueprint or a
## memory echo. It pops out of where it was dropped, slows down, and is pulled toward the player once near.
## Drawn in code (small glowing gems), so there is no art to import.

enum Kind { ASH, MATERIAL, BLUEPRINT, ECHO }

const COLLECT_RADIUS: float = 13.0
const MAGNET_RADIUS: float = 46.0
const ARM_DELAY: float = 0.45
const LIFETIME: float = 240.0

var kind: Kind = Kind.ASH
var amount: int = 1
var id: StringName = &""

var _velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _clock: float = 0.0
var _collected: bool = false


## Drops something at a position. `parent` is where it lives (a room's Spawned folder, so it goes away with the room).
static func spawn(parent: Node, pos: Vector2, pickup_kind: Kind, pickup_amount: int = 1, pickup_id: StringName = &"") -> Pickup:
	var pickup := Pickup.new()
	pickup.kind = pickup_kind
	pickup.amount = pickup_amount
	pickup.id = pickup_id
	parent.add_child(pickup)
	pickup.global_position = pos
	pickup._velocity = Vector2.from_angle(randf() * TAU) * randf_range(40.0, 90.0)
	return pickup


func _ready() -> void:
	add_to_group("pickup")
	z_index = 2
	_clock = randf() * TAU


func _physics_process(delta: float) -> void:
	_age += delta
	_clock += delta
	if _age > LIFETIME:
		queue_free()
		return
	global_position += _velocity * delta
	_velocity = _velocity.move_toward(Vector2.ZERO, 160.0 * delta)
	queue_redraw()
	var player := GameManager.player
	if _collected or _age < ARM_DELAY or not is_instance_valid(player) or player.is_dead:
		return
	var offset: Vector2 = player.global_position + Vector2(0.0, 2.0) - global_position
	var distance := offset.length()
	if distance <= COLLECT_RADIUS:
		_collect()
	elif distance <= MAGNET_RADIUS:
		global_position += offset.normalized() * (110.0 + (MAGNET_RADIUS - distance) * 4.0) * delta


func _collect() -> void:
	_collected = true
	match kind:
		Kind.ASH:
			Run.add_ash(amount)
		Kind.MATERIAL:
			Run.add_material(id, amount)
			GameManager.toast_requested.emit("+%d %s" % [amount, RunData.material_name(id).to_upper()], null, RunData.material_color(id))
		Kind.BLUEPRINT:
			Run.add_blueprint(id)
			var info: Dictionary = RunData.BLUEPRINTS.get(id, {})
			GameManager.toast_requested.emit("BLUEPRINT: %s" % String(info.get("name", id)).to_upper(), null, Color(1.0, 0.85, 0.4))
		Kind.ECHO:
			Run.echoes += amount
			Run.save_profile()
			GameManager.toast_requested.emit("+%d MEMORY ECHO" % amount, null, Color(0.6, 0.85, 1.0))
	Audio.play(preload("res://assets/sounds/coin.wav"), -14.0, randf_range(0.9, 1.3), 0.05)
	queue_free()


func _draw() -> void:
	var bob := sin(_clock * 5.0) * 1.2
	var center := Vector2(0.0, bob - 2.0)
	var color := Color(0.8, 0.78, 0.74)
	var radius := 2.6
	match kind:
		Kind.ASH:
			color = Color(0.82, 0.8, 0.76)
			radius = 2.2 + minf(float(amount), 30.0) * 0.03
		Kind.MATERIAL:
			color = RunData.material_color(id)
			radius = 3.0
		Kind.BLUEPRINT:
			color = Color(1.0, 0.85, 0.4)
			radius = 4.0
		Kind.ECHO:
			color = Color(0.6, 0.85, 1.0)
			radius = 3.6
	draw_circle(center, radius * 2.1, Color(color.r, color.g, color.b, 0.18))
	draw_circle(Vector2(0.0, 3.5), radius * 0.9, Color(0, 0, 0, 0.35)) # shadow
	if kind == Kind.BLUEPRINT:
		draw_rect(Rect2(center + Vector2(-3.5, -4.5), Vector2(7.0, 9.0)), color)
		draw_rect(Rect2(center + Vector2(-2.0, -2.5), Vector2(4.0, 1.0)), Color(0.4, 0.28, 0.1))
		draw_rect(Rect2(center + Vector2(-2.0, 0.0), Vector2(4.0, 1.0)), Color(0.4, 0.28, 0.1))
		return
	var diamond := PackedVector2Array([center + Vector2(0, -radius * 1.3), center + Vector2(radius, 0), center + Vector2(0, radius * 1.3), center + Vector2(-radius, 0)])
	draw_colored_polygon(diamond, color)
	draw_circle(center + Vector2(-radius * 0.25, -radius * 0.35), radius * 0.3, Color(1, 1, 1, 0.85))
