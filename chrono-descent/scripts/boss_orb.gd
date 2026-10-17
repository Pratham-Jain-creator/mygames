class_name BossOrb
extends Area2D
## A glob of purple slime spat by the Slime Queen. It flies on, hurts the player it touches, and bursts on
## walls (or when its time runs out). The pictures (flying orb, burst) come from the boss effects sheet.

var velocity: Vector2 = Vector2.ZERO
var damage: int = 8
var knockback: float = 120.0
var lifetime: float = 3.5
## Radians per second the orb may curve toward its target. 0 = flies straight.
var homing_turn: float = 0.0
var target: Node2D

var _spent: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func setup(dir: Vector2, speed: float, dmg: int, kb: float, life: float, turn: float = 0.0, homing_target: Node2D = null) -> void:
	velocity = dir.normalized() * speed
	damage = dmg
	knockback = kb
	lifetime = life
	homing_turn = turn
	target = homing_target


func _ready() -> void:
	z_index = 4
	body_entered.connect(_on_body_entered)
	sprite.play(&"fly")


func _physics_process(delta: float) -> void:
	if _spent:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_burst()
		return
	if homing_turn > 0.0 and is_instance_valid(target):
		var want := (target.global_position - global_position).angle()
		var diff := wrapf(want - velocity.angle(), -PI, PI)
		velocity = velocity.rotated(clampf(diff, -homing_turn * delta, homing_turn * delta))
	global_position += velocity * delta


func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, global_position, knockback)
	_burst()


func _burst() -> void:
	_spent = true
	velocity = Vector2.ZERO
	set_deferred("monitoring", false)
	sprite.play(&"impact")
	sprite.animation_finished.connect(queue_free, CONNECT_ONE_SHOT)
