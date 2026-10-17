extends Node
## Probe: 5-Node room (RAM Expansion) fits on one row and the hand label stays visible.

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/probe/shots"))
	RunState.start_new_run()
	RunState.vouchers.append("ram_expansion")
	var scr: Control = load("res://scenes/server/server_screen.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(2.6).timeout
	for i in 3:
		scr._on_card_activated(scr._cards[i])
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/ram_5nodes.png")
	print("room=", scr._cards.size(), " room_rect=", scr._room.get_global_rect(), " vp=", get_viewport().get_visible_rect().size)
	get_tree().quit()
