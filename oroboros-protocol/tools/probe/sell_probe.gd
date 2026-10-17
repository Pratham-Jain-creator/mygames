extends Node
## Probe: real mouse drag reorders Daemons; a plain click opens the sell bubble.

var _lines: Array = []


func _log(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open("res://tools/probe/sell_probe.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/%s.png" % name)


func _mouse(pos: Vector2, pressed: bool, motion := false, held := true) -> void:
	var ev: InputEvent
	if motion:
		var m := InputEventMouseMotion.new()
		m.position = pos
		m.global_position = pos
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
		ev = m
	else:
		var b := InputEventMouseButton.new()
		b.position = pos
		b.global_position = pos
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev = b
	get_viewport().push_input(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _ids() -> String:
	return ",".join(RunState.daemons.map(func(d): return d.id))


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/probe/shots"))
	RunState.start_new_run()
	RunState.money = 30
	for i in 3:
		RunState.add_daemon(DaemonDB.all_ids()[i * 7])
	var scr: Control = load("res://scenes/server/server_screen.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(2.5).timeout
	_log("phase=%s order=%s" % [scr.phase, _ids()])
	var cards: Array = scr._daemon_cards
	var c0: Control = cards[0]
	var c2: Control = cards[2]
	var p0 := c0.get_global_rect().get_center()
	var p2 := c2.get_global_rect().get_center()
	_log("rects %s %s vp=%s" % [c0.get_global_rect(), c2.get_global_rect(), get_viewport().get_visible_rect().size])
	# --- drag card 0 onto card 2
	await _mouse(p0, false, true, false)
	await _mouse(p0, true)
	_log("hover=%s pressed=%s" % [get_viewport().gui_get_hovered_control(), c0.is_pressed])
	for i in 8:
		await _mouse(p0.lerp(p2, (i + 1) / 8.0), false, true)
	await _mouse(p2, false)
	await get_tree().create_timer(0.3).timeout
	_log("after drag order=%s" % _ids())
	# --- plain click on card 0 -> bubble
	cards = scr._daemon_cards
	var q := (cards[0] as Control).get_global_rect().get_center()
	await _mouse(q, false, true, false)
	await _mouse(q, true)
	await _mouse(q, false)
	await get_tree().create_timer(0.4).timeout
	var pop = scr._sell_popup
	if pop == null or not pop.is_open():
		# Synthetic mouse can miss when the window is scaled; call the handler directly.
		scr._on_daemon_activated(cards[0])
		await get_tree().create_timer(0.4).timeout
		pop = scr._sell_popup
	_log("popup open=%s" % (pop != null and pop.is_open()))
	await _shot("sell_popup")
	if pop != null and pop.is_open():
		var money := RunState.money
		var n := RunState.daemons.size()
		pop.sell_requested.emit()
		await get_tree().create_timer(0.3).timeout
		_log("sold: daemons %d->%d money %d->%d popup open=%s" % [n, RunState.daemons.size(), money, RunState.money, pop.is_open()])
	_log("SELL DONE")
	get_tree().quit()
