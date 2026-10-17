extends Node2D

const BULLET = preload("res://scenes/bullet.tscn")

const BURST_COUNT = 5          # bullets per burst
const SHOT_INTERVAL = 0.18     # seconds between bullets inside a burst
const COOLDOWN = 3.0           # seconds of rest between bursts
const FIRST_DELAY = 1.2        # grace period after spawning before the first burst
const MUZZLE_DISTANCE = 34.0   # how far from the centre the bullets appear (barrel tip)
const TURN_SPEED = 4.0         # how fast the turret swings to face the player

var shots_left := 0
var shot_timer := 0.0
var cooldown_timer := FIRST_DELAY


func _process(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	# Swing toward the player. The sprite's barrels point UP, hence + PI/2.
	var target_angle := global_position.direction_to(player.global_position).angle() + PI / 2.0
	rotation = lerp_angle(rotation, target_angle, clampf(TURN_SPEED * delta, 0.0, 1.0))

	if shots_left > 0:
		# In the middle of a burst
		shot_timer -= delta
		if shot_timer <= 0.0:
			_fire()
			shots_left -= 1
			shot_timer = SHOT_INTERVAL
			if shots_left == 0:
				cooldown_timer = COOLDOWN
	else:
		# Resting between bursts
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			shots_left = BURST_COUNT
			shot_timer = 0.0


func _fire() -> void:
	var bullet = BULLET.instantiate()
	bullet.wander = false  # aimed straight at the player (bullet.gd does the aiming)
	# Position FIRST, then add to the tree, so the bullet aims from the muzzle.
	bullet.global_position = global_position + Vector2.UP.rotated(rotation) * MUZZLE_DISTANCE
	get_parent().add_child(bullet)
