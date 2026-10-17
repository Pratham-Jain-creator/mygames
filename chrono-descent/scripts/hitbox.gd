class_name Hitbox
extends Area2D
## Deals damage (and optional knockback) to any body that has take_damage().
## The knockback direction is "away from the nearest CharacterBody2D ancestor"
## (the player for a sword, the enemy for its own attack box).

@export var damage: int = 10
## Push strength applied to the victim (pixels/second, decays on its own). 0 = none.
@export var knockback_force: float = 0.0
@export var continuous_damage: bool = false
@export var damage_interval: float = 0.5 # How often to re-apply damage
## A moving blade overlaps the same target on many frames: with this on, each target is hit once per
## swing. Call reset_hits() when a new swing starts.
var one_hit_per_target: bool = false
var _hit_targets: Dictionary = {}

## Emitted after this hitbox damaged a body.
signal hit_landed(body: Node2D)

var source: Node2D
var pulse_timer: Timer


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	var p: Node = get_parent()
	while p != null and not (p is CharacterBody2D):
		p = p.get_parent()
	source = p as Node2D

	# If this is a continuous hitbox (like an enemy body), create a looping timer
	if continuous_damage:
		pulse_timer = Timer.new()
		pulse_timer.wait_time = damage_interval
		pulse_timer.autostart = true
		pulse_timer.timeout.connect(_on_pulse_timeout)
		add_child(pulse_timer)


func _hit(body: Node2D) -> void:
	if body == source:
		return
	if one_hit_per_target and _hit_targets.has(body):
		return
	if body.has_method("take_damage"):
		_hit_targets[body] = true
		var origin := source.global_position if source else global_position
		body.take_damage(damage, origin, knockback_force)
		hit_landed.emit(body)
		# Landing a hit with the player's weapon: a brief freeze + tiny shake makes it feel heavy.
		if source != null and source.is_in_group("player") and body.is_in_group("enemy"):
			GameManager.hit_stop()
			GameManager.shake_camera(1.5, 0.1)


func _on_body_entered(body: Node2D) -> void:
	_hit(body)


## Forgets who was already hit (start of a new swing).
func reset_hits() -> void:
	_hit_targets.clear()


## Hits everything overlapping right now, once more (a spin attack calls this every few tenths of a second).
func pulse() -> void:
	reset_hits()
	for body in get_overlapping_bodies():
		_hit(body)


func _on_pulse_timeout() -> void:
	for body in get_overlapping_bodies():
		_hit(body)
