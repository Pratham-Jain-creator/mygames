class_name SurvivalRoom
extends GauntletController
## The Endurance Hall (the "time survivors" room): the doors seal and waves of enemies keep arriving. Nothing needs to
## be cleared: you only have to stay alive for ONE MINUTE. When time is up whatever still stands crumbles to dust, the
## doors open and a chest unlocks.

const DURATION: float = 60.0
const WAVE_EVERY: float = 12.0
const CHEST_PATH: String = "res://scenes/props/chest.tscn"

var kind: StringName
var cfg: LevelConfig
var generator: Node
var depth: int = 1

var _left: float = 0.0
var _wave_clock: float = 0.0
var _waves_spawned: int = 0


func setup_special(p_room: WFCRoom, p_kind: StringName, p_cfg: LevelConfig, p_generator: Node) -> void:
	kind = p_kind
	cfg = p_cfg
	generator = p_generator
	depth = cfg.depth
	setup(p_room, 1, int(30.0 * cfg.difficulty), Callable(generator, "pick_enemy"), Callable(generator, "_spawn_enemy"), [])
	var chest := generator._spawn_into(room, CHEST_PATH, RoomKit.spot(room, Vector2(0, -50)), {"locked": true}) as Node
	if chest != null:
		_reward_chests.append(chest)


func _next_wave() -> void:
	_left = DURATION
	_wave_clock = 0.0
	_waves_spawned = 0
	_alive = 0


func _physics_process(delta: float) -> void:
	super(delta)
	if state != State.ACTIVE:
		return
	_left -= delta
	_wave_clock -= delta
	GameManager.room_banner.emit("SURVIVE  %d:%02d" % [int(maxf(_left, 0.0)) / 60, int(maxf(_left, 0.0)) % 60], Color(1.0, 0.7, 0.3))
	if _left <= 0.0:
		_finish()
	elif _wave_clock <= 0.0:
		_wave_clock = WAVE_EVERY
		_spawn_wave()


func _spawn_wave() -> void:
	_waves_spawned += 1
	var budget := int(float(base_budget) * (1.0 + WAVE_GROWTH * float(_waves_spawned - 1)))
	var plan: Array[Dictionary] = []
	while plan.size() < 6:
		var choice: Dictionary = generator.pick_enemy(budget)
		if choice.is_empty():
			break
		plan.append(choice)
		budget -= choice["cost"]
	var points := room.find_spawn_points(plan.size(), ENEMY_SPACING, room.get_reserved_points(), 1, SPAWN_DOOR_CLEARANCE)
	for i in mini(plan.size(), points.size()):
		var enemy := _spawn.call(room, plan[i]["path"], points[i], {}) as EnemyBase
		if enemy == null:
			continue
		_alive += 1
		_enemies.append(enemy)
		enemy.defeated.connect(_on_enemy_defeated)
		enemy.wake_up()
	GameManager.shake_camera(2.0, 0.2)


## No wave ever "clears": the minute is what counts.
func _on_enemy_defeated(_enemy: EnemyBase) -> void:
	_alive -= 1


func _finish() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy) and not (enemy as EnemyBase)._dead:
			BossFX.puff(RoomKit.spawned(room), enemy.global_position, 0.8)
			enemy.queue_free()
	_enemies.clear()
	_alive = 0
	GameManager.room_banner.emit("", Color.WHITE)
	var at := RoomKit.center(room)
	Loot.drop_materials(RoomKit.spawned(room), at, 2, depth, RoomKit.tier(depth, 0))
	Loot.drop_ash(RoomKit.spawned(room), at, int(round(60.0 * Loot.floor_scale(depth))))
	RoomKit.toast("YOU OUTLASTED THEM", Color(1.0, 0.85, 0.5))
	_win()


func _reset() -> void:
	if state == State.ACTIVE:
		GameManager.room_banner.emit("", Color.WHITE)
	super()
