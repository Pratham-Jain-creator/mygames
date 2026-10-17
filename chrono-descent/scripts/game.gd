class_name Game
extends Node2D
## Root of the whole game: it owns the base, the player, the HUD, the menus and the Levels manager, so there is one
## place that knows what is happening everywhere.
##
## The loop
##   BASE      the prisoner's hideout: the workbench (craft armor and charms from what you extracted) and the stairs
##             down. Arriving here ALIVE banks everything you carry (materials, ash, blueprints).
##   DUNGEON   ten floors. Each floor has its own 15-minute timer; in the last minute the screen trembles. When it
##             ends the dungeon SHIFTS: standing in a safe room (the start room or the boss room) you survive and the
##             floor is rebuilt around that room; anywhere else you die. The start room has an EXTRACTION TERMINAL
##             that banks what you carry and refills the canteen. The boss room guards the stairs down.
##   death     loses everything you carry, removes grafts, fractures the charms you wore (see Run.die), and sends you
##             back to the base to try again with whatever you had banked.

enum Phase { BASE, DUNGEON, TRANSITION, WON }

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const FADE_TIME: float = 0.5
## Seconds before the floor shifts when the screen starts to tremble.
const WARNING_TIME: float = 60.0
const WORKBENCH_COLOR: Color = Color(0.45, 0.95, 0.85)

## Length of a floor in seconds (15 minutes). Lower it to test the collapse quickly.
@export var level_duration: float = LevelConfig.DEFAULT_DURATION

var phase: Phase = Phase.BASE
var player: CharacterBody2D
var hud: CanvasLayer
var loadout: LoadoutScreen
var workbench: WorkbenchScreen
var choice: ChoiceMenu

var _run_id: int = 0 # changes every time a run is reset, so stale transitions can abort
var _shake_clock: float = 0.0

@onready var base: WFCRoom = $Base
@onready var levels: Levels = $Levels
@onready var fade: ColorRect = $Transition/Fade


func _ready() -> void:
	add_to_group("game")
	levels.level_duration = level_duration
	levels.boss_defeated.connect(_on_boss_defeated)

	player = PLAYER_SCENE.instantiate() as CharacterBody2D
	add_child(player)
	hud = HUD_SCENE.instantiate()
	add_child(hud)
	loadout = LoadoutScreen.new()
	add_child(loadout)
	loadout.setup(player)
	workbench = WorkbenchScreen.new()
	add_child(workbench)
	workbench.setup(player)
	choice = ChoiceMenu.new()
	add_child(choice)
	GameManager.choice_menu = choice

	var spawn := base.get_node("PlayerSpawn") as Node2D
	player.global_position = spawn.global_position
	GameManager.reset_run()
	GameManager.register_player(player, spawn.global_position)
	hud.initialize(player.get_node("HealthComponent"))
	hud.set_dungeon_ui(false)
	_place_base_stations()

	GameManager.player_respawned.connect(_on_run_reset)
	GameManager.descend_requested.connect(_on_descend_requested)
	GameManager.ascend_requested.connect(_on_ascend_requested)
	GameManager.travel_requested.connect(_travel_to)
	GameManager.reveal_map_requested.connect(_on_reveal_map)
	GameManager.save_requested.connect(Run.save_profile)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Run.save_profile()


func _process(delta: float) -> void:
	if phase == Phase.WON:
		return
	# Every floor's timer keeps running, awake or asleep. Grafts can make it faster; the Chrono-Sanctuary stops it.
	var rate := 0.0 if GameManager.timer_paused else maxf(0.25, 1.0 + Run.stat(&"time_rate"))
	levels.tick(delta * rate)
	var level := levels.current
	if level == null:
		return
	GameManager.level_time_left = maxf(level.time_left, 0.0)
	if phase != Phase.DUNGEON:
		return
	# The last minute: the dungeon starts to tremble.
	if level.time_left > 0.0 and level.time_left <= WARNING_TIME:
		_shake_clock -= delta
		if _shake_clock <= 0.0:
			_shake_clock = 0.45
			GameManager.shake_camera(1.1, 0.4)
	if level.time_left <= 0.0:
		_on_level_expired(level)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and not _menu_open():
		_open_loadout()
		get_viewport().set_input_as_handled()


func _menu_open() -> bool:
	return loadout.is_open() or workbench.is_open() or choice.is_open()


func _open_loadout() -> void:
	if phase != Phase.BASE and phase != Phase.DUNGEON:
		return
	if player.is_dead or player.input_locked:
		return
	loadout.open()


func _open_workbench() -> void:
	if phase != Phase.BASE or player.is_dead or _menu_open():
		return
	workbench.open()


## The room (base room or a room of the current floor) that contains a world position.
func get_room_at(world_pos: Vector2) -> WFCRoom:
	if base.get_global_bounds().has_point(world_pos):
		return base
	if levels.current != null:
		return levels.current.get_room_at(world_pos)
	return null


## The workbench stands in the base, near where the prisoner wakes up.
func _place_base_stations() -> void:
	var origin := (base.get_node("PlayerSpawn") as Node2D).global_position
	var pos := base.nearest_free_point(origin + Vector2(72, -14), 1)
	Altar.make(base.get_node("Spawned"), pos, &"workbench", "WORKBENCH", WORKBENCH_COLOR, func(_by: Node) -> void: _open_workbench())
	# the Reckoner keeps your record
	var reaper_pos := base.nearest_free_point(origin + Vector2(72, 62), 1)
	Altar.make(base.get_node("Spawned"), reaper_pos, &"reaper", "SPEAK WITH THE RECKONER", Color(0.5, 0.9, 1.0), _speak_with_reckoner)


## The reaper in the base reads your record back to you.
func _speak_with_reckoner(_by: Node) -> void:
	if _menu_open():
		return
	var names: Array[String] = []
	for boss: StringName in Run.bosses_beaten:
		names.append(String(LevelConfig.BOSS_INFO[boss]["title"]).capitalize())
	var rows: Array = [
		{"name": "Deepest floor reached: %d of %d" % [Run.best_floor, LevelConfig.FINAL_DEPTH], "desc": "", "color": UIKit.GOLD_BRIGHT, "enabled": false},
		{"name": "Bosses beaten", "desc": ", ".join(names) if not names.is_empty() else "none yet", "color": UIKit.GOLD_BRIGHT, "enabled": false},
		{"name": "Blueprints known: %d of %d" % [Run.blueprints.size(), RunData.BLUEPRINTS.size()], "desc": "Bosses and hidden rooms drop them.", "color": UIKit.GOLD_BRIGHT, "enabled": false},
		{"name": "Banked: %d ash, %d materials" % [Run.stash_ash, _stash_total()], "desc": "What dying cannot take from you.", "color": UIKit.GOLD_BRIGHT, "enabled": false},
	]
	choice.open("THE RECKONER", "\"Every prisoner is counted. Come back alive, and be counted again.\"", rows, func(_i: int) -> void: pass)


func _stash_total() -> int:
	var n := 0
	for id in Run.stash:
		n += int(Run.stash[id])
	return n


# ------------------------------------------------------------------ stairs and travel

func _on_descend_requested() -> void:
	if phase == Phase.TRANSITION or phase == Phase.WON:
		return
	var next_floor := GameManager.current_depth + 1
	if next_floor <= LevelConfig.FINAL_DEPTH:
		_travel_to(next_floor)


func _on_ascend_requested() -> void:
	if phase == Phase.TRANSITION or phase == Phase.WON:
		return
	var target := GameManager.current_depth - 1
	if target >= 0:
		_travel_to(target)


## Moves the player to another floor (0 = the base), up or down. A floor that is still alive is
## resumed exactly as it was left; otherwise a new one is generated.
func _travel_to(depth: int) -> void:
	if phase == Phase.TRANSITION or phase == Phase.WON or depth == GameManager.current_depth:
		return
	var run := _run_id
	var going_up := depth < GameManager.current_depth
	var leaving_base := GameManager.current_depth == 0
	phase = Phase.TRANSITION
	player.set_input_locked(true)
	await _fade_to(1.0)
	if run != _run_id:
		return
	hud.clear_minimap() # before anything is freed, so it never draws freed rooms
	levels.leave_current() # the floor we leave falls asleep, keeping its layout and its timer
	Run.clear_floor_effects()
	GameManager.timer_paused = false
	player.dash_disabled = false

	if depth == 0:
		await _arrive_in_base()
		return

	var level: Level = null
	var built_now := false
	if levels.has_floor(depth):
		level = levels.wake_floor(depth)
	else:
		built_now = true
		# Park the player in the base while a new floor is generated, so no new room is created on top of them
		# (its entry trigger would fire and wake its enemies before the player got there).
		player.global_position = GameManager.hub_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		if run != _run_id:
			return
		for attempt in 3: # generation can (rarely) fail for a seed: try another one
			level = levels.build_level(depth)
			if level:
				break
	if level == null:
		push_error("Could not build floor %d." % depth)
		await _arrive_in_base()
		return

	if leaving_base:
		Run.begin_run()
	# Coming down you appear next to this floor's stairs up; coming up (or through a shortcut), next to its stairs
	# down. A boss floor built fresh while you climb UP into it has no fight: you obviously got past the boss.
	if going_up and built_now:
		levels.skip_boss(level)
	player.global_position = level.get_arrival_from_below() if going_up else level.get_player_spawn()
	GameManager.current_depth = depth
	GameManager.level_time_left = level.time_left
	Run.best_floor = maxi(Run.best_floor, depth)
	Music.play(&"dungeon")
	hud.set_dungeon_ui(true)
	hud.setup_minimap(level.rooms, player) # rooms already visited show up as discovered again
	await get_tree().create_timer(0.2).timeout # let the rooms' physics settle
	await _fade_to(0.0)
	var floor_subtitle: String = LevelConfig.BOSS_INFO[level.config.boss_kind]["floor_line"]
	hud.show_title("FLOOR %d" % depth, floor_subtitle)
	player.set_input_locked(false)
	phase = Phase.DUNGEON


## Back in the base, standing next to the stairs down. Arriving alive banks everything you carry.
func _arrive_in_base() -> void:
	var stairs := base.get_node("Stairs") as Node2D
	player.global_position = stairs.global_position + Level.ARRIVAL_OFFSET
	GameManager.current_depth = 0
	GameManager.level_time_left = 0.0
	if Run.in_run:
		var summary := Run.extract()
		Run.end_run_alive()
		announce_extraction(summary)
	Run.refill_canteen()
	Music.play(&"base")
	hud.set_dungeon_ui(false)
	await _fade_to(0.0)
	player.set_input_locked(false)
	phase = Phase.BASE


## Toasts of what an extraction banked.
func announce_extraction(summary: Dictionary) -> void:
	var parts: Array[String] = []
	if int(summary["ash"]) > 0:
		parts.append("%d ASH" % int(summary["ash"]))
	for id: StringName in summary["materials"]:
		parts.append("%d %s" % [int(summary["materials"][id]), RunData.material_name(id).to_upper()])
	for bp: StringName in summary["blueprints"]:
		parts.append(String(RunData.BLUEPRINTS[bp]["name"]).to_upper())
	if parts.is_empty():
		return
	GameManager.toast_requested.emit("EXTRACTED: " + ", ".join(parts), null, Color(0.55, 1.0, 0.7))


# ------------------------------------------------------------------ the dungeon shifts

func _on_level_expired(level: Level) -> void:
	phase = Phase.TRANSITION # stops the timer from firing again
	for menu: CanvasLayer in [loadout, workbench]:
		if menu.is_open():
			menu.close()
	if level.get_anchor_rooms_for(player.global_position).is_empty():
		# Caught between floors: the dungeon swallows the player.
		hud.show_title("THE DUNGEON SHIFTS", "you were caught between floors", 3.0)
		GameManager.shake_camera(8.0, 1.5)
		GameManager.kill_player()
	else:
		_shift_floor(level)


## The floor is rebuilt around the room the player is standing in (see Levels.regenerate).
func _shift_floor(level: Level) -> void:
	var run := _run_id
	hud.show_title("THE DUNGEON SHIFTS", "only the safe rooms remain", 3.0)
	GameManager.shake_camera(8.0, 1.6)
	await get_tree().create_timer(1.4).timeout
	if run != _run_id:
		return
	player.set_input_locked(true)
	await _fade_to(1.0)
	if run != _run_id:
		return
	hud.clear_minimap()
	Run.clear_floor_effects()
	GameManager.timer_paused = false
	player.dash_disabled = false
	var arrival := levels.regenerate(level, player.global_position)
	if arrival != Vector2.INF:
		player.global_position = arrival
	else:
		push_error("Could not rebuild floor %d." % level.depth)
	GameManager.level_time_left = level.time_left
	hud.setup_minimap(level.rooms, player)
	await get_tree().create_timer(0.2).timeout
	await _fade_to(0.0)
	player.set_input_locked(false)
	phase = Phase.DUNGEON


# ------------------------------------------------------------------ the memory echo

func _on_reveal_map() -> void:
	if phase == Phase.DUNGEON:
		hud.minimap.reveal_all()
		GameManager.toast_requested.emit("THE FLOOR IS REVEALED", null, Color(0.6, 0.85, 1.0))
	else:
		GameManager.toast_requested.emit("THE ECHO SHOWS ONLY BLANK STONE HERE", null, Color(0.8, 0.8, 0.8))


# ------------------------------------------------------------------ death / victory

## The player died and was revived in the base: this run is over, start again with what you had banked.
func _on_run_reset() -> void:
	_run_id += 1
	for menu: CanvasLayer in [loadout, workbench]:
		if menu.is_open():
			menu.close()
	if choice.is_open():
		choice.close()
	hud.clear_minimap()
	levels.reset_run()
	GameManager.reset_run()
	GameManager.timer_paused = false
	Run.die()
	hud.set_dungeon_ui(false)
	fade.color.a = 0.0
	player.dash_disabled = false
	player.set_input_locked(false)
	Music.play(&"base")
	phase = Phase.BASE


func _on_boss_defeated() -> void:
	phase = Phase.WON
	Run.best_floor = LevelConfig.FINAL_DEPTH
	hud.show_title("COUNT DRACULA IS DEFEATED", "the dungeon falls silent", 8.0)
	GameManager.game_won.emit()


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade, "color:a", alpha, FADE_TIME)
	await tween.finished
