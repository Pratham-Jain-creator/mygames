extends Node2D

const SPEED = 675
const WANDER_SPEED_RANGE = Vector2(250.0, 550.0)  # drifting asteroids are slower
const OFFSCREEN_MARGIN = 80.0                       # how far past the edge before deleting
const MAX_LIFETIME = 25.0                           # safety net so nothing lives forever

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

# Set by game.gd BEFORE the asteroid is added to the scene.
# false = aimed at the player (classic), true = drifts across the screen at random.
var wander: bool = false

var direction: Vector2 = Vector2.ZERO
var speed: float = SPEED
var spin_speed: float = 0.0
var has_entered_screen := false
var age := 0.0


func _ready() -> void:
	# Random spin for every asteroid
	spin_speed = randf_range(1.0, 4.0) * [-1, 1].pick_random()

	if wander:
		# Head for a random point on screen - usually NOT where the player is.
		var view := _world_view_rect()
		var random_point := Vector2(
			randf_range(view.position.x + 100.0, view.end.x - 100.0),
			randf_range(view.position.y + 100.0, view.end.y - 100.0))
		direction = global_position.direction_to(random_point)
		speed = randf_range(WANDER_SPEED_RANGE.x, WANDER_SPEED_RANGE.y)
	else:
		var player = get_tree().get_first_node_in_group("player")
		if player != null:
			direction = global_position.direction_to(player.global_position)
		speed = SPEED


func _process(delta: float) -> void:
	position += direction * speed * delta
	animated_sprite_2d.rotate(spin_speed * delta)

	age += delta
	if age > MAX_LIFETIME:
		queue_free()
		return

	# Remove the asteroid as soon as it has crossed the screen and left it again.
	var view := _world_view_rect()
	if view.has_point(global_position):
		has_entered_screen = true
	elif has_entered_screen and not view.grow(OFFSCREEN_MARGIN).has_point(global_position):
		queue_free()


# The visible area in world coordinates (works with any window size / camera).
func _world_view_rect() -> Rect2:
	return get_canvas_transform().affine_inverse() * get_viewport_rect()


func _on_killzone_body_entered(body: Node2D) -> void:
	animation_player.play("bullet_hit")
