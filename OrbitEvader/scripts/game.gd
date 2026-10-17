extends Node2D

const BULLET = preload("res://scenes/bullet.tscn")
const TURRET = preload("res://scenes/turret.tscn")
const TURRET_EVERY_SECONDS = 20.0  # a new turret appears every this many seconds of play
const TURRET_EDGE_INSET = 36.0 # how far inside the screen edge turrets sit
const MAX_AIMED = 3            # max aimed (chasing) asteroids per wave
const items = [
	preload("res://scenes/heal_item.tscn")
]

# EXTRA drifting asteroids spawned on top of the aimed ones (they do not replace them).
# Each wave spawns between these two numbers of drifters, growing a little over time.
const WANDER_MIN = 1
const WANDER_MAX_START = 2
const WANDER_MAX_LATE = 5

var count = 0
var bulletCount = 0
var turret_timer = 0.0

func _process(delta: float) -> void:
	# This node stops processing while the game is paused, so menus don't count as play time
	turret_timer += delta
	if turret_timer >= TURRET_EVERY_SECONDS:
		turret_timer -= TURRET_EVERY_SECONDS
		_spawn_turret()
	if Input.is_action_just_pressed("exit"):
		get_tree().quit()

func _on_spawn_timer_timeout() -> void:
	count = _time_counter(count)
	
	
func _time_counter(count:int) -> int:
	count += 1
	Global.score += 1
	bulletCount = (min((count / 30) , MAX_AIMED - 1 ) + 1)

	# Aimed asteroids: unchanged, same amount as before
	for i in  bulletCount:
		_spawn_bullet(false)
	
	# Extra drifting asteroids on top of those
	var wander_max = WANDER_MAX_START + min(count / 60, WANDER_MAX_LATE - WANDER_MAX_START)
	for i in randi_range(WANDER_MIN, wander_max):
		_spawn_bullet(true)
	
	if (count % 10 == 0) and (count != 0) :
		var random_item = items[randi() % items.size()]
		var item = random_item.instantiate()
		var itemArea = get_tree().get_first_node_in_group("item_area")
		item.global_position = itemArea.global_position + Vector2(randf() * itemArea.size.x, randf() * itemArea.size.y)
		add_child(item)
		
		pass
	
	
	return count


func _spawn_turret() -> void:
	var turret = TURRET.instantiate()
	# Visible screen area in world coordinates, shrunk so the turret sits just inside the edge
	var view: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect()
	var inner := view.grow(-TURRET_EDGE_INSET)
	var corner_pad := 90.0  # keep away from the corners
	match randi() % 4:
		0: turret.position = Vector2(randf_range(inner.position.x + corner_pad, inner.end.x - corner_pad), inner.position.y)  # top
		1: turret.position = Vector2(randf_range(inner.position.x + corner_pad, inner.end.x - corner_pad), inner.end.y)       # bottom
		2: turret.position = Vector2(inner.position.x, randf_range(inner.position.y + corner_pad, inner.end.y - corner_pad))  # left
		3: turret.position = Vector2(inner.end.x, randf_range(inner.position.y + corner_pad, inner.end.y - corner_pad))       # right
	add_child(turret)


func _spawn_bullet(wander: bool) -> void:
	var bullet = BULLET.instantiate()
	bullet.wander = wander
	var spawns = get_tree().get_nodes_in_group("spawners")
	var spawnArea = spawns[randi() % spawns.size()]

	# 1. Set the position FIRST
	bullet.global_position = spawnArea.global_position + Vector2(randf() * spawnArea.size.x, randf() * spawnArea.size.y)

	# 2. THEN add to the tree. Now when bullet.gd runs _ready(),
	# it knows its actual starting location.
	add_child(bullet)
