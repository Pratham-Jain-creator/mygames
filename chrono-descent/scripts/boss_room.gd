class_name BossRoomController
extends GauntletController
## A boss fight in a sealed room. It reuses the gauntlet's machinery (wait until the player is well inside,
## seal every doorway with a gate, call the fight off if the player dies or leaves) and replaces the waves
## with ONE boss that may split into many pieces.
##
##   IDLE    waits for the player to step inside
##   ACTIVE  gates close, a short cinematic holds the player still while the boss makes her entrance, the boss
##           bar opens, and the fight runs. The boss bar shows ONE shared health pool: the sum of the health of
##           every piece the boss has split into.
##   DONE    when every piece is dead: slow motion, a reward, the gates open, and the way down appears.
##
## The boss itself is a scene (SlimeQueen, GolemBoss...); the room only needs `setup_boss` with its description
## (see LevelConfig.BOSS_INFO).

const SLOWMO_SCALE: float = 0.3
## Real seconds of slow motion after the last blow.
const SLOWMO_TIME: float = 1.15
## Items strewn around the room when the boss falls.
const REWARD_SCATTER: float = 46.0

var boss_scene_path: String = ""
var boss_title: String = "BOSS"
var boss_subtitle: String = ""
var boss_color: Color = Color(0.78, 0.45, 1.0)
## The stairs down: hidden until the boss is dead.
var reward_stairs: Node2D
## Which boss this is ("slime_queen", "golem", "mimic", "chronos"): decides the first-kill blueprint.
var boss_key: StringName = &"slime_queen"
var floor_depth: int = 1

var _family: Array[EnemyBase] = []
var _pool_max: int = 1
var _player_held: bool = false
var _slowmo: bool = false


func setup_boss(p_room: WFCRoom, info: Dictionary, stairs: Node2D, spawner: Callable, depth: int) -> void:
	setup(p_room, 1, 1, Callable(), spawner, [])
	boss_scene_path = info["scene"]
	boss_title = info["title"]
	boss_subtitle = info["subtitle"]
	boss_color = info["color"]
	boss_key = info["key"]
	reward_stairs = stairs
	floor_depth = depth


# ------------------------------------------------------------------ the fight

## Replaces the first (and only) wave: the boss makes her entrance.
func _next_wave() -> void:
	var fight := _fight_id
	var player := GameManager.player
	var center := room.get_global_bounds().get_center()
	# she appears on the far side of the room from where the player is standing
	var spawn_pos := center + (center - player.global_position).limit_length(110.0)
	if spawn_pos.distance_to(player.global_position) < 90.0:
		spawn_pos = center + Vector2(0.0, -90.0)
	var boss := _spawn.call(room, boss_scene_path, spawn_pos, {}) as EnemyBase
	if boss == null:
		push_warning("BossRoomController: could not spawn %s" % boss_scene_path)
		_victory()
		return
	boss.set("arena", room)
	_family.clear()
	_register(boss)
	_pool_max = maxi(boss.health.max_health, 1)
	boss.wake_up()
	player.set_input_locked(true) # held still for the entrance
	_player_held = true
	GameManager.boss_started.emit(boss_title, boss_subtitle, boss_color)
	GameManager.boss_health_changed.emit(_pool_max, _pool_max, 1)
	Music.play(&"boss")
	GameManager.shake_camera(5.0, 0.6)
	get_tree().create_timer(BossBase.INTRO_TIME).timeout.connect(_end_intro.bind(fight))


func _end_intro(fight: int) -> void:
	if fight != _fight_id or state != State.ACTIVE:
		return
	_release_player()


func _release_player() -> void:
	if _player_held and is_instance_valid(GameManager.player):
		GameManager.player.set_input_locked(false)
	_player_held = false


func _register(member: EnemyBase) -> void:
	_family.append(member)
	member.set_meta("boss_loot_by_room", true)
	member.defeated.connect(_on_member_defeated)
	member.health.health_changed.connect(_on_member_health)
	if member.has_signal("split_into"):
		member.connect("split_into", _on_member_split)


func _on_member_split(parent: EnemyBase, children: Array) -> void:
	_family.erase(parent)
	for child in children:
		_register(child as EnemyBase)
	GameManager.boss_announce.emit(_split_line(parent))
	_refresh_bar()


func _on_member_health(_current: int, _maximum: int) -> void:
	_refresh_bar()


## What the screen says when a boss splits: the first split and the ones after it.
func _split_line(parent: EnemyBase) -> String:
	return "THE QUEEN SPLITS!" if parent.get("generation") == 0 else "THEY SPLIT AGAIN!"


func _on_member_defeated(member: EnemyBase) -> void:
	_family.erase(member)
	_refresh_bar()
	if _family.is_empty() and state == State.ACTIVE:
		_victory()


## The shared health pool: what is left of every living piece, out of what the boss started with.
func _refresh_bar() -> void:
	var total := 0
	var pieces := 0
	for member in _family:
		if is_instance_valid(member) and not member.health.is_dead:
			total += member.health.current_health
			pieces += 1
	GameManager.boss_health_changed.emit(mini(total, _pool_max), _pool_max, pieces)


# ------------------------------------------------------------------ victory

func _victory() -> void:
	if state == State.DONE:
		return
	state = State.DONE # also stops the "player left the room" watch
	_fight_id += 1
	_release_player()
	_free_minions()
	GameManager.boss_health_changed.emit(0, _pool_max, 0)
	GameManager.boss_ended.emit(true)
	GameManager.shake_camera(9.0, 0.7)
	_drop_reward()
	_slowmo = true
	Engine.time_scale = SLOWMO_SCALE
	# real-time timer (ignores the slow motion it is part of)
	get_tree().create_timer(SLOWMO_TIME, true, false, true).timeout.connect(_after_victory)


func _after_victory() -> void:
	_restore_time()
	for gate in _gates:
		if is_instance_valid(gate):
			gate.open()
	room.set_meta("gauntlet_cleared", true)
	if is_instance_valid(reward_stairs) and reward_stairs.has_method("unlock"):
		reward_stairs.call("unlock")
		GameManager.boss_announce.emit("THE WAY DOWN OPENS")
	Music.play(&"dungeon")
	won.emit()


## Loot strewn around the room: ash, materials of the floor's tier and (the first time) the boss's blueprint.
func _drop_reward() -> void:
	var center := room.get_global_bounds().get_center()
	Loot.boss_died(room.get_node("Spawned"), center, boss_key, floor_depth)


func _free_minions() -> void:
	for minion in get_tree().get_nodes_in_group("boss_minion"):
		if is_instance_valid(minion) and room.get_global_bounds().has_point((minion as Node2D).global_position):
			BossFX.puff(room.get_node("Spawned"), (minion as Node2D).global_position, 0.8)
			minion.queue_free()


func _restore_time() -> void:
	if _slowmo:
		_slowmo = false
		Engine.time_scale = 1.0


# ------------------------------------------------------------------ calling the fight off

## The player died or left mid-fight: everything the boss became disappears, the room waits for a new try.
func _reset() -> void:
	if state != State.ACTIVE:
		return
	for member in _family:
		if is_instance_valid(member):
			member.queue_free()
	_family.clear()
	_free_minions()
	_release_player()
	_restore_time()
	GameManager.boss_ended.emit(false)
	Music.play(&"dungeon")
	super()


## Skips the fight: used when the player arrives from below on a freshly built boss floor (they have obviously
## got past the boss already). The way down is simply open.
func skip() -> void:
	state = State.DONE
	set_physics_process(false)
	room.set_meta("gauntlet_cleared", true)
	if is_instance_valid(reward_stairs) and reward_stairs.has_method("unlock"):
		reward_stairs.call("unlock", false)


func _exit_tree() -> void:
	_restore_time()
	# the room is destroyed mid-fight (the dungeon shifted): close the boss bar and give the music and the player back
	if state == State.ACTIVE and get_tree() != null:
		_release_player()
		GameManager.boss_ended.emit(false)
		Music.play(&"dungeon")
