extends Node
## Autoload "Game": global state, input registration, hit-stop and the signal bus.
## No visuals live here. HUD and fx react to these signals.

signal job_changed(job_id: StringName)
signal jp_changed(job_id: StringName, jp: int, level: int)
signal hurt(amount: float)
signal deflected(perfect: bool)
signal posture_broken
signal message(text: String)
signal player_died(reason: String)
signal level_cleared(time_sec: float)
signal buff_changed(kind: StringName, active: bool)
signal enemy_killed(deathblow: bool, jp: int)

const JobData = preload("res://scripts/job_data.gd")
const JP_PER_LEVEL := 100

var current_job: StringName = &"knight"
var job_jp: Dictionary = {}
var job_level: Dictionary = {}
var checkpoint_pos := Vector3(0.0, 1.0, 4.0)
var checkpoint_yaw := 0.0
var run_time := 0.0
var run_active := false
var deaths := 0
var depth := 0.0
var depth_total := 0.0

var _hitstop_token := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_input()
	for id in JobData.ORDER:
		job_jp[id] = 0
		job_level[id] = 1
	enemy_killed.connect(func(_deathblow: bool, jp: int) -> void: add_jp(jp))


func _process(delta: float) -> void:
	if run_active:
		run_time += delta


# --- input map -------------------------------------------------------------
# WASD move | Space jump (hold against a wall to wall-run, tap to wall-jump)
# Shift dash (aim direction, i-frames) | Ctrl slide / dive
# LMB attack | RMB deflect (tap right before a hit = perfect deflect)
# Q / E job abilities | F change job at a Job Crystal | R restart | Esc free mouse
func _register_input() -> void:
	var keys := {
		&"move_forward": KEY_W,
		&"move_back": KEY_S,
		&"move_left": KEY_A,
		&"move_right": KEY_D,
		&"jump": KEY_SPACE,
		&"dash": KEY_SHIFT,
		&"slide": KEY_CTRL,
		&"interact": KEY_F,
		&"ability_1": KEY_Q,
		&"ability_2": KEY_E,
		&"restart": KEY_R,
		&"release_mouse": KEY_ESCAPE,
	}
	for action in keys:
		_add_key(action, keys[action])
	_add_mouse(&"attack", MOUSE_BUTTON_LEFT)
	_add_mouse(&"deflect", MOUSE_BUTTON_RIGHT)


func _add_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _add_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# --- progression -----------------------------------------------------------
func add_jp(amount: int) -> void:
	var id: StringName = current_job
	job_jp[id] = int(job_jp[id]) + amount
	var lvl: int = mini(1 + int(job_jp[id]) / JP_PER_LEVEL, JobData.MAX_LEVEL)
	if lvl > int(job_level[id]):
		job_level[id] = lvl
		message.emit("%s reached Job Level %d!" % [JobData.JOBS[id]["name"], lvl])
	jp_changed.emit(id, int(job_jp[id]), int(job_level[id]))


func set_checkpoint(pos: Vector3, yaw: float) -> void:
	checkpoint_pos = pos
	checkpoint_yaw = yaw


# --- juice -----------------------------------------------------------------
func hitstop(duration: float, time_scale: float = 0.05) -> void:
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0
