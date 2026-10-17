class_name GauntletController
extends Node
## Locked-door wave fight ("gauntlet") for one room. Created by the level director and added
## as a child of the room.
##
## Flow:
##   IDLE    waits until the player has stepped well inside the room (not standing in a doorway)
##   ACTIVE  every doorway is sealed by an iron gate; waves of enemies spawn, the next wave
##           starts when the previous one is cleared
##   DONE    gates open, the reward chest(s) unlock
##
## If the player dies mid-fight, or gets out of the room some other way (the gates make walking out
## impossible, but a Scroll of Recall teleports), the room resets: gates open, enemies removed, banner
## cleared, so it can be retried. Progress is announced through GameManager.gauntlet_changed.

enum State { IDLE, ACTIVE, DONE }

## Emitted once when the last wave is cleared (used by the boss fight on the final floor).
signal won

const GATE_SCENE := preload("res://scenes/props/gate.tscn")
## Seconds between a cleared wave and the next one.
const WAVE_DELAY: float = 1.5
## The player must be at least this far (px) from every doorway before the gates seal.
const START_DISTANCE: float = 90.0
const SPAWN_DOOR_CLEARANCE: float = 160.0
const ENEMY_SPACING: float = 80.0
## Each later wave is a bit harder: budget = base * (1 + this * wave_index).
const WAVE_GROWTH: float = 0.25
## Seconds the player may be outside the room mid-fight before the fight is called off.
const ABANDON_TIME: float = 0.4
## How far past the walls still counts as "in the room" (px).
const ABANDON_MARGIN: float = 48.0

var room: WFCRoom
var total_waves: int = 2
var base_budget: int = 40
var state: State = State.IDLE
## Chance that the final wave also brings an ELITE (3x health, drops much more, may drop a legendary).
var elite_chance: float = 0.0

var _pick_enemy: Callable   # (budget: int) -> Dictionary {path, cost}, empty when nothing fits
var _spawn: Callable        # (room, scene_path, position, properties) -> Node2D
var _reward_chests: Array[Node] = []
var _gates: Array[Node2D] = []
var _wave: int = 0
var _alive: int = 0
var _enemies: Array[Node] = []
var _away_time: float = 0.0
## Bumped on every reset so a wave timer from the old fight can't start a wave in the new one.
var _fight_id: int = 0


## picker and spawner are the director's own functions, so a gauntlet picks and places enemies
## exactly like the rest of the dungeon does.
func setup(p_room: WFCRoom, waves: int, budget: int, picker: Callable, spawner: Callable, chests: Array) -> void:
	room = p_room
	total_waves = waves
	base_budget = budget
	_pick_enemy = picker
	_spawn = spawner
	_reward_chests.assign(chests)
	room.set_meta("gauntlet", true)
	GameManager.player_died.connect(_reset)


func _physics_process(delta: float) -> void:
	var player := GameManager.player
	if not is_instance_valid(player) or player.is_dead:
		return
	if state == State.ACTIVE:
		_watch_for_abandon(player, delta)
		return
	if state != State.IDLE:
		return
	var p := player.global_position
	if not room.get_global_bounds().grow(-24.0).has_point(p):
		return
	for door in room.get_door_info():
		if p.distance_to(door["center"]) < START_DISTANCE:
			return
	_start()


func _start() -> void:
	state = State.ACTIVE
	_wave = 0
	_away_time = 0.0
	_build_gates()
	for gate in _gates:
		gate.close()
	_next_wave()


func _build_gates() -> void:
	for gate in _gates:
		if is_instance_valid(gate):
			gate.queue_free()
	_gates.clear()
	for door in room.get_door_info():
		var gate := GATE_SCENE.instantiate() as Node2D
		var horizontal: bool = door["dir"] == 0 or door["dir"] == 2
		gate.set("size_px", Vector2(WFCRoom.DOOR_WIDTH_PX, WFCRoom.TILE_PX) if horizontal else Vector2(WFCRoom.TILE_PX, WFCRoom.DOOR_HEIGHT_PX))
		room.add_child(gate)
		# The wall row/column that holds the gap is one tile thick: sit in the middle of it.
		gate.global_position = door["center"] + (door["inward"] as Vector2) * (WFCRoom.TILE_PX * 0.5)
		_gates.append(gate)


func _next_wave() -> void:
	_wave += 1
	GameManager.gauntlet_changed.emit(_wave, total_waves, true, false)
	var budget := int(base_budget * (1.0 + WAVE_GROWTH * float(_wave - 1)))
	var plan: Array[Dictionary] = []
	while plan.size() < room.get_enemy_capacity():
		var choice: Dictionary = _pick_enemy.call(budget)
		if choice.is_empty():
			break
		plan.append(choice)
		budget -= choice["cost"]
	var points := room.find_spawn_points(plan.size(), ENEMY_SPACING, room.get_reserved_points(), 1, SPAWN_DOOR_CLEARANCE)
	_alive = 0
	for i in mini(plan.size(), points.size()):
		var enemy := _spawn.call(room, plan[i]["path"], points[i], {}) as EnemyBase
		if enemy == null:
			continue
		_alive += 1
		_enemies.append(enemy)
		enemy.defeated.connect(_on_enemy_defeated)
		enemy.wake_up()
	if _wave == total_waves and not plan.is_empty() and randf() < elite_chance:
		_spawn_elite(plan[0]["path"])
	if _alive == 0:
		_on_wave_cleared() # nothing could spawn: never deadlock the player behind closed gates


func _spawn_elite(scene_path: String) -> void:
	var points := room.find_spawn_points(1, ENEMY_SPACING, room.get_reserved_points(), 1, SPAWN_DOOR_CLEARANCE)
	if points.is_empty():
		return
	var elite := _spawn.call(room, scene_path, points[0], {"is_elite": true}) as EnemyBase
	if elite == null:
		return
	_alive += 1
	_enemies.append(elite)
	elite.defeated.connect(_on_enemy_defeated)
	elite.wake_up()
	GameManager.toast_requested.emit("AN ELITE APPEARS!", null, Color(1.0, 0.45, 0.4))
	GameManager.shake_camera(3.0, 0.25)


func _on_enemy_defeated(_enemy: EnemyBase) -> void:
	_alive -= 1
	if _alive <= 0 and state == State.ACTIVE:
		_on_wave_cleared()


## The gates keep the player in, so the only way out mid-fight is a teleport (Scroll of Recall...).
## Then the fight is called off: the room goes back to waiting, the banner disappears.
func _watch_for_abandon(player: Node2D, delta: float) -> void:
	if room.get_global_bounds().grow(ABANDON_MARGIN).has_point(player.global_position):
		_away_time = 0.0
		return
	_away_time += delta
	if _away_time >= ABANDON_TIME:
		_reset()


func _on_wave_cleared() -> void:
	if _wave < total_waves:
		var fight := _fight_id
		await get_tree().create_timer(WAVE_DELAY).timeout
		if state == State.ACTIVE and fight == _fight_id:
			_next_wave()
	else:
		_win()


func _win() -> void:
	state = State.DONE
	for gate in _gates:
		if is_instance_valid(gate):
			gate.open()
	for chest in _reward_chests:
		if is_instance_valid(chest):
			chest.unlock()
	room.set_meta("gauntlet_cleared", true)
	won.emit()
	GameManager.gauntlet_changed.emit(_wave, total_waves, false, true)
	GameManager.shake_camera(4.0, 0.3)


## The player died or left mid-fight: open up, clear the room, wait to be started again.
func _reset() -> void:
	if state != State.ACTIVE:
		return
	state = State.IDLE
	_fight_id += 1
	_away_time = 0.0
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	for gate in _gates:
		if is_instance_valid(gate):
			gate.open()
	_alive = 0
	GameManager.gauntlet_changed.emit(0, total_waves, false, false)
