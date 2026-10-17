extends Node
## Probe: does the Tailbytes viewer scroll with the mouse wheel and with a touch-style drag?

var _lines: Array = []


func _log(msg: String) -> void:
	_lines.append(msg)
	var f := FileAccess.open("res://tools/probe/scroll_probe.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))


func _wheel(pos: Vector2, up: bool) -> void:
	for pressed in [true, false]:
		var b := InputEventMouseButton.new()
		b.position = pos
		b.global_position = pos
		b.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		b.pressed = pressed
		b.factor = 1.0
		get_viewport().push_input(b)
	await get_tree().process_frame


func _mouse(pos: Vector2, pressed: bool, motion := false) -> void:
	var ev: InputEvent
	if motion:
		var m := InputEventMouseMotion.new()
		m.position = pos
		m.global_position = pos
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.relative = Vector2(0, -30)
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


func _ready() -> void:
	RunState.start_new_run()
	var scr: Node = load("res://scenes/network_map/network_map.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(0.8).timeout
	scr.open_deck_tracker()
	await get_tree().create_timer(1.0).timeout
	var sc: ScrollContainer = scr.deck_viewer.get_node("Panel/VBox/Scroll")
	var bar := sc.get_v_scroll_bar()
	_log("scroll rect=%s content=%s max=%s value=%s" % [sc.get_global_rect(), sc.get_child(0).size, bar.max_value, sc.scroll_vertical])
	var center := sc.get_global_rect().get_center()
	for i in 5:
		await _wheel(center, false)
	await get_tree().create_timer(0.3).timeout
	_log("after wheel value=%s" % sc.scroll_vertical)
	sc.scroll_vertical = 0
	# touch-style drag starting on a card
	var p0 := center
	await _mouse(p0, true)
	for i in 10:
		await _mouse(p0 + Vector2(0, -30 * (i + 1)), false, true)
	await _mouse(p0 + Vector2(0, -300), false)
	await get_tree().create_timer(0.3).timeout
	_log("after drag value=%s" % sc.scroll_vertical)
	_log("DONE")
	get_tree().quit()
