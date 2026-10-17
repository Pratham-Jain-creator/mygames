extends Node
## Probe: plays the whole guided tutorial by calling the same handlers the UI
## buttons call, checks that wrong inputs are blocked, and logs to
## user://tutorial_probe.log (also copied to res://tools/probe/tutorial_probe.log).

const SERVER := preload("res://scenes/server/server_screen.tscn")

var _screen: Control
var _blocked_checked := false
var _lines: Array = []


func _log(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open("res://tools/probe/tutorial_probe.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))


const SHOT_STEPS := [4, 5, 7, 13]


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tools/probe/shots/%s.png" % name)


func _ready() -> void:
	_log("TUT start")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/probe/shots"))
	var menu = load("res://scenes/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(1.5).timeout
	await _shot("menu")
	menu.get_node("%RulesButton").activated.emit(null)
	await get_tree().create_timer(0.6).timeout
	await _shot("menu_rules")
	menu.queue_free()
	RunState.start_new_run(true)
	_screen = SERVER.instantiate()
	add_child(_screen)
	await get_tree().create_timer(1.2).timeout
	var d = _screen.tutorial
	if d == null or not d.running:
		_log("TUT FAIL: director not running")
		get_tree().quit()
		return
	var guard := 0
	var last_idx := -1
	var stuck := 0
	while d.running and guard < 600:
		guard += 1
		await get_tree().create_timer(0.35).timeout
		if d.idx == last_idx:
			stuck += 1
		else:
			stuck = 0
			last_idx = d.idx
			_log("TUT step %d expect=%s score=%d hp=%d phase=%d" % [d.idx, d.expect, RunState.server.score, RunState.health, _screen.phase])
		if stuck > 40:
			_log("TUT FAIL: stuck at step %d expect=%s" % [d.idx, d.expect])
			break
		if not _blocked_checked and d.expect == "card":
			_blocked_checked = true
			var before: int = d.idx
			_screen._on_flee()
			_screen._on_execute()
			_screen._open_deck()
			_log("TUT gate check ok=%s" % str(d.idx == before and not _screen.deck_viewer.visible))
		if stuck == 0 and SHOT_STEPS.has(d.idx):
			await get_tree().create_timer(2.0).timeout
			await _shot("step_%02d" % d.idx)
		_act(d)
		if d.idx >= d.steps.size() - 1 and d.expect == "next":
			_log("TUT DONE score=%d/%d hp=%d" % [RunState.server.score, RunState.server.quota, RunState.health])
			break
	get_tree().quit()


func _act(d) -> void:
	match d.expect:
		"next":
			d._on_next()
		"card":
			var spec: Array = d.step.card
			var c: NodeCard = _screen.tut_card(int(spec[0]), int(spec[1]))
			if c:
				_screen._on_card_activated(c)
		"execute":
			_screen._on_execute()
		"skip":
			_screen._on_flee()
		"weapon":
			_screen._on_weapon_toggle(null)
		"deck_open":
			_screen._open_deck()
		"deck_close":
			_screen.deck_viewer._finish([])
		"subs_open":
			_screen._open_subs()
		"subs_close":
			_screen._on_subs_close_requested()
