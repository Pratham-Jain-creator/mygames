class_name Levels
extends Node
## Builds, rebuilds and tracks every dungeon floor of the current run.
##
## Floors PERSIST. Leaving a floor (stairs up or down) only puts it to sleep (hidden, not
## processing): its layout, enemies and loot stay exactly as they were, so the stairs lead back
## to the same place. Every floor has its own countdown that keeps running while it sleeps.
## When a sleeping floor's timer runs out it is discarded; entering that depth again builds a
## brand-new layout with a fresh timer. The floor the player is on shifts instead (see Game).
##
## Each floor lives at its own spot in the world (slot * LEVEL_SPACING) so any number of
## floors can exist at the same time without overlapping.

signal boss_defeated

## Every possible start room. A floor uses exactly ONE of them, and consecutive new floors never
## use the same one, so the arrival room keeps changing as you descend. Add a scene here to
## put another start room in rotation (it needs PlayerSpawn, Bounds and is_spawn_room = true).
const START_ROOMS: Array[String] = [
	"res://scenes/rooms/start/start_atrium.tscn",
	"res://scenes/rooms/start/start_hall.tscn",
	"res://scenes/rooms/start/start_tower.tscn",
	"res://scenes/rooms/start/start_west.tscn",
	"res://scenes/rooms/start/start_center.tscn",
	"res://scenes/rooms/start/start_east.tscn",
]
const STAIRS_SCENE: PackedScene = preload("res://scenes/props/stairs.tscn")
const BOSS_ROOM_SCRIPT: Script = preload("res://scripts/boss_room.gd")
const TERMINAL_COLOR: Color = Color(0.45, 0.95, 0.85)
## Distance between two floors in the world. A floor spans a few thousand pixels at most.
const LEVEL_SPACING: float = 40000.0
## Where the stairs up are tried, relative to the start room's PlayerSpawn (first valid one wins).
const UP_STAIRS_OFFSETS: Array[Vector2] = [
	Vector2(-110, -30), Vector2(110, -30), Vector2(-110, 30), Vector2(110, 30),
	Vector2(0, -90), Vector2(-160, 0), Vector2(160, 0),
]

## Seconds a floor lasts. Exposed so tests / difficulty modes can change it.
@export var level_duration: float = LevelConfig.DEFAULT_DURATION

var generator: LevelGenerator
## The floor the player is on (null while in the base).
var current: Level
## depth -> Level for every floor that is alive this run, including sleeping ones.
var floors: Dictionary = {}

var _last_start: int = -1
var _used_slots: Dictionary = {}


func _ready() -> void:
	generator = LevelGenerator.new()
	generator.name = "Generator"
	for path in START_ROOMS:
		generator.start_room_scenes.append(load(path) as PackedScene)
	add_child(generator)


# ------------------------------------------------------------------ floors

func has_floor(depth: int) -> bool:
	return floors.has(depth) and is_instance_valid(floors[depth])


## Generates and decorates a brand-new floor, and makes it the current one.
func build_level(depth: int) -> Level:
	var config := LevelConfig.for_depth(depth, level_duration)
	config.start_index = _pick_start_index()
	var level := Level.new()
	level.setup(config)
	level.slot = _alloc_slot()
	level.position = Vector2(level.slot * LEVEL_SPACING, 0.0)
	add_child(level)
	var result := generator.generate(config, level)
	if result.is_empty():
		_free_slot(level.slot)
		level.queue_free()
		return null
	level.apply_result(result)
	_decorate(level)
	floors[depth] = level
	current = level
	return level


## Brings a sleeping floor back exactly as the player left it.
func wake_floor(depth: int) -> Level:
	var level := floors[depth] as Level
	level.visible = true
	level.process_mode = Node.PROCESS_MODE_INHERIT
	current = level
	return level


## The player leaves the current floor: it falls asleep but keeps its layout and its timer.
func leave_current() -> void:
	if current == null:
		return
	current.visible = false
	current.process_mode = Node.PROCESS_MODE_DISABLED
	current = null


## Floor shift: the whole floor is generated again from scratch, around the SAME start room. The player stays in
## the safe room they stood in. Returns where the player should stand afterwards (the same spot of the same safe
## room), or Vector2.INF if they were not in a safe room.
func regenerate(level: Level, player_pos: Vector2) -> Vector2:
	var safe_kind := ""
	var offset := Vector2.ZERO
	var room := level.get_room_at(player_pos)
	if room != null:
		if level.start_rooms.has(room):
			safe_kind = "start"
		elif room == level.extraction_room:
			safe_kind = "extraction"
		if safe_kind != "":
			offset = player_pos - room.get_global_bounds().get_center()
	var start_scene := ""
	if not level.start_rooms.is_empty():
		start_scene = level.start_rooms[0].scene_file_path
	for old_room in level.rooms:
		if is_instance_valid(old_room):
			level.remove_child(old_room)
			old_room.queue_free()
	var config := LevelConfig.for_depth(level.depth, level_duration)
	var start_index := START_ROOMS.find(start_scene)
	config.start_index = start_index if start_index >= 0 else _pick_start_index()
	level.config = config
	var result := generator.generate(config, level)
	if result.is_empty():
		return Vector2.INF
	level.apply_result(result)
	level.time_left = config.duration
	_decorate(level)
	var target_room: WFCRoom = null
	if safe_kind == "start" and not level.start_rooms.is_empty():
		target_room = level.start_rooms[0]
	elif safe_kind == "extraction":
		target_room = level.extraction_room
	if target_room == null:
		return Vector2.INF
	return target_room.nearest_free_point(target_room.get_global_bounds().get_center() + offset, 1)


## Ends the run: every floor is freed.
func reset_run() -> void:
	for depth in floors.keys():
		_discard_floor(depth)
	current = null
	_last_start = -1


## Resting is gone, but a floor the player is NOT on can still run out of time: every sleeping floor is discarded.
func expire_all_sleeping() -> void:
	for depth in floors.keys():
		if floors[depth] != current:
			_discard_floor(depth)


## Advances every floor's timer, awake or asleep. A sleeping floor whose time runs out is
## discarded; the current floor's expiry is handled by Game (it may collapse around the player).
func tick(delta: float) -> void:
	for depth in floors.keys():
		var level := floors[depth] as Level
		if not is_instance_valid(level):
			floors.erase(depth)
			continue
		level.time_left -= delta
		if level != current and level.time_left <= 0.0:
			_discard_floor(depth)


func _discard_floor(depth: int) -> void:
	var level := floors.get(depth) as Level
	floors.erase(depth)
	if not is_instance_valid(level):
		return
	_free_slot(level.slot)
	if level == current:
		current = null
	remove_child(level)
	level.queue_free()


func _alloc_slot() -> int:
	var slot := 0
	while _used_slots.has(slot):
		slot += 1
	_used_slots[slot] = true
	return slot


func _free_slot(slot: int) -> void:
	_used_slots.erase(slot)


## Picks a start room for a new floor: random, but never the same one as the previous floor.
func _pick_start_index() -> int:
	var count := START_ROOMS.size()
	var choice := randi() % count
	if count > 1 and choice == _last_start:
		choice = (choice + 1 + randi() % (count - 1)) % count
	_last_start = choice
	return choice


# ------------------------------------------------------------------ decoration

func _decorate(level: Level) -> void:
	for start_room in level.start_rooms:
		_add_up_stairs(level, start_room)
		_add_extraction_terminal(start_room)
		_add_merchant(start_room)
	var room := level.extraction_room
	if room == null:
		return
	_setup_boss_room(level, room)


## The ash merchant: ash is volatile (it is lost on death), so he sells TEMPORARY boons that last until the floor
## shifts or you leave it. He stands next to the extraction terminal.
const MERCHANT_STOCK: Array = [
	{"id": "whetstone", "name": "Whetstone", "desc": "+12% sword damage until this floor shifts or you leave it.", "cost": 45, "stats": {"damage": 0.12}},
	{"id": "broth", "name": "Thick Broth", "desc": "+25 maximum health until this floor shifts or you leave it.", "cost": 40, "stats": {"max_hp": 25}},
	{"id": "boots", "name": "Fleet Boots", "desc": "+12% movement speed until this floor shifts or you leave it.", "cost": 35, "stats": {"move": 0.12}},
	{"id": "flask", "name": "Spare Flask", "desc": "Refill one canteen charge right now.", "cost": 30},
]


func _add_merchant(room: WFCRoom) -> void:
	if room.has_meta("merchant"):
		return
	var spawn := room.get_node_or_null("PlayerSpawn") as Node2D
	var origin := spawn.global_position if spawn else room.get_global_bounds().get_center()
	var spot := Vector2.ZERO
	var found := false
	for offset: Vector2 in [Vector2(-64, -34), Vector2(64, 34), Vector2(-64, 34), Vector2(-100, 0), Vector2(0, -70), Vector2(100, 0)]:
		var p := origin + offset
		if room.is_valid_spawn_point(p, 1, 0.0) and (not room.has_meta("terminal") or p.distance_to((room.get_meta("terminal") as Node2D).global_position) > 40.0):
			spot = p
			found = true
			break
	if not found:
		spot = room.nearest_free_point(origin + Vector2(-64, -34), 1)
	var merchant := Altar.make(room.get_node("Spawned"), spot, &"reaper", "TRADE: ASH FOR A TEMPORARY BOON", Color(0.95, 0.8, 0.4), func(_by: Node) -> void: pass)
	merchant.callback = _open_merchant.bind(room)
	room.set_meta("merchant", merchant)


func _open_merchant(_by: Node, room: WFCRoom) -> void:
	var bought: Array = room.get_meta("bought") if room.has_meta("bought") else []
	var options: Array = []
	for item: Dictionary in MERCHANT_STOCK:
		var sold: bool = bought.has(item["id"]) and item["id"] != "flask"
		var affordable := Run.ash >= int(item["cost"])
		options.append({"name": "%s  -  %d ash" % [item["name"], item["cost"]], "desc": "SOLD" if sold else item["desc"], "color": Color(0.95, 0.8, 0.4), "enabled": affordable and not sold})
	GameManager.choice_menu.open("THE ASH PEDDLER", "You carry %d ash. It is lost if you die: spend it, or bank it at the terminal." % Run.ash, options, func(index: int) -> void:
		if index < 0:
			return
		var item: Dictionary = MERCHANT_STOCK[index]
		if bought.has(item["id"]) and item["id"] != "flask":
			return # one of each per visit to the floor
		if not Run.spend_ash(int(item["cost"])):
			return
		if item.has("stats"):
			Run.add_floor_buff("%s" % String(item["name"]).to_upper(), item["stats"])
		else:
			Run.canteen = mini(Run.canteen + 1, Run.canteen_max())
			Run.canteen_changed.emit()
			Run.changed.emit()
		bought.append(item["id"])
		room.set_meta("bought", bought)
		Audio.play(preload("res://assets/sounds/coin.wav"), -4.0, 0.9)
		GameManager.toast_requested.emit("BOUGHT: %s" % String(item["name"]).to_upper(), null, Color(0.95, 0.8, 0.4)))


## The terminal next to the arrival point: extracting banks everything you carry (materials, ash, blueprints) and
## refills the canteen. It is the Safe Room's whole purpose: get back here before the timer runs out.
func _add_extraction_terminal(room: WFCRoom) -> void:
	if room.has_meta("terminal"):
		return
	var spawn := room.get_node_or_null("PlayerSpawn") as Node2D
	var origin := spawn.global_position if spawn else room.get_global_bounds().get_center()
	var spot := Vector2.ZERO
	var found := false
	for offset: Vector2 in [Vector2(64, -34), Vector2(-64, -34), Vector2(64, 34), Vector2(-64, 34), Vector2(0, -70), Vector2(100, 0), Vector2(-100, 0)]:
		var p := origin + offset
		if room.is_valid_spawn_point(p, 1, 0.0):
			spot = p
			found = true
			break
	if not found:
		spot = room.nearest_free_point(origin + Vector2(64, -34), 1)
	var terminal := Altar.make(room.get_node("Spawned"), spot, &"terminal", "EXTRACT: BANK YOUR LOOT", TERMINAL_COLOR, _use_terminal)
	room.set_meta("terminal", terminal)


func _use_terminal(_by: Node) -> void:
	var game := get_tree().get_first_node_in_group("game") as Game
	var needs_flask := Run.canteen < Run.canteen_max()
	if not Run.has_anything_to_extract() and not needs_flask:
		GameManager.toast_requested.emit("NOTHING TO EXTRACT", null, Color(0.8, 0.8, 0.8))
		return
	var summary := Run.extract()
	Run.refill_canteen()
	Audio.play(preload("res://assets/sounds/power_up.wav"), -6.0, 1.3)
	GameManager.shake_camera(1.5, 0.15)
	if game != null:
		game.announce_extraction(summary)
	if needs_flask:
		GameManager.toast_requested.emit("CANTEEN REFILLED", null, Color(0.5, 1.0, 0.6))


## Stairs up in the start room, next to where the player arrives. Floor 1's lead to the base.
func _add_up_stairs(level: Level, room: WFCRoom) -> void:
	var existing = room.get_meta("up_stairs") if room.has_meta("up_stairs") else null
	if existing is Node and is_instance_valid(existing):
		level.up_stairs = existing # the start room survived a floor shift: keep its stairs
		return
	var spawn := room.get_node_or_null("PlayerSpawn") as Node2D
	var origin := spawn.global_position if spawn else room.get_global_bounds().get_center()
	var chosen := origin + UP_STAIRS_OFFSETS[0]
	for offset in UP_STAIRS_OFFSETS:
		var p := origin + offset
		# The stairs need clear floor, and so does the spot where the player will appear.
		if room.is_valid_spawn_point(p, 2, 0.0) and room.is_valid_spawn_point(p + Level.ARRIVAL_OFFSET, 1, 0.0):
			chosen = p
			break
	var stairs := STAIRS_SCENE.instantiate() as Node2D
	stairs.set("going_up", true)
	room.get_node("Spawned").add_child(stairs)
	stairs.global_position = chosen
	room.set_meta("up_stairs", stairs)
	level.up_stairs = stairs


## Stairs down in the middle of the extraction room.
func _add_down_stairs(level: Level, room: WFCRoom) -> void:
	var existing = room.get_meta("stairs") if room.has_meta("stairs") else null
	if existing is Node and is_instance_valid(existing):
		level.down_stairs = existing # the extraction room survived a floor shift
		return
	var stairs := STAIRS_SCENE.instantiate() as Node2D
	room.get_node("Spawned").add_child(stairs)
	stairs.global_position = room.get_global_bounds().get_center()
	room.set_meta("stairs", stairs)
	level.down_stairs = stairs


## The extraction room is the BOSS ROOM: the stairs down are there, but hidden until the boss is dead. Which boss
## guards which floor: RunData.BOSS_BY_FLOOR. The doors seal and the fight starts when the player steps in (see
## BossRoomController). The final floor has no stairs down: beating Chronos ends the game.
func _setup_boss_room(level: Level, room: WFCRoom) -> void:
	var is_final := level.config.is_boss
	var stairs: Node2D = null
	if not is_final:
		_add_down_stairs(level, room)
		stairs = level.down_stairs
		if stairs == null:
			return
		stairs.call("lock")
	if room.has_meta("boss_room"):
		return
	var controller := BOSS_ROOM_SCRIPT.new() as BossRoomController
	controller.name = "BossRoom"
	room.add_child(controller)
	controller.setup_boss(room, LevelConfig.BOSS_INFO[level.config.boss_kind], stairs, Callable(generator, "_spawn_enemy"), level.depth)
	room.set_meta("boss_room", controller)
	if is_final:
		controller.won.connect(func() -> void: boss_defeated.emit())


## Opens the way down without a fight (the player came UP from below onto a fresh floor).
func skip_boss(level: Level) -> void:
	var room := level.extraction_room
	if room == null:
		return
	var controller = room.get_meta("boss_room") if room.has_meta("boss_room") else null
	if controller is BossRoomController:
		controller.skip()
