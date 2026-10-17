extends Node
## Probe: screenshots of the main screens to check padding / overlap.

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/ui_%s.png" % n)


func _show(path: String, n: String, wait := 1.5) -> void:
	var scr: Control = load(path).instantiate()
	add_child(scr)
	await get_tree().create_timer(wait).timeout
	await _shot(n)
	scr.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/probe/shots"))
	RunState.start_new_run()
	RunState.money = 12
	await _show("res://scenes/main_menu/main_menu.tscn", "menu")
	await _show("res://scenes/network_map/network_map.tscn", "map")
	await _show("res://scenes/shop/shop_screen.tscn", "shop", 2.5)
	RunState.network = 2
	RunState.server_index = 1
	await _show("res://scenes/server/server_screen.tscn", "server", 8.0)
	get_tree().quit()
