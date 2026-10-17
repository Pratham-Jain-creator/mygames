extends Node
## Probe: opens the Settings overlay on each run screen and saves screenshots.

var _lines: Array = []


func _log(msg: String) -> void:
	print(msg)
	_lines.append(msg)
	var f := FileAccess.open("res://tools/probe/pause_probe.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/%s.png" % name)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/probe/shots"))
	RunState.start_new_run()
	RunState.money = 30
	for i in 3:
		RunState.add_daemon(DaemonDB.all_ids()[i * 7])
	for path in ["res://scenes/server/server_screen.tscn", "res://scenes/shop/shop_screen.tscn", "res://scenes/network_map/network_map.tscn"]:
		var scr: Control = load(path).instantiate()
		add_child(scr)
		await get_tree().create_timer(2.2).timeout
		var tag: String = path.get_file().get_basename()
		await _shot("pause_%s_closed" % tag)
		var pm: Control = scr.pause_menu
		_log("%s pause_menu=%s" % [tag, pm])
		pm.get_node("%GearButton").activated.emit(null)
		await get_tree().create_timer(0.5).timeout
		_log("%s open=%s overlay_open=%s" % [tag, pm.is_open(), scr.is_overlay_open()])
		await _shot("pause_%s_open" % tag)
		pm.get_node("%CrtButton").activated.emit(null)
		pm.get_node("%MusicButton").activated.emit(null)
		await get_tree().create_timer(0.2).timeout
		_log("crt=%s music=%s" % [PostFX.is_crt_enabled(), AudioService.music_enabled])
		pm.get_node("%CrtButton").activated.emit(null)
		pm.get_node("%MusicButton").activated.emit(null)
		pm.get_node("%ResumeButton").activated.emit(null)
		await get_tree().create_timer(0.4).timeout
		_log("%s closed=%s" % [tag, not pm.is_open()])
		scr.queue_free()
		await get_tree().process_frame
	_log("PAUSE DONE")
	get_tree().quit()
