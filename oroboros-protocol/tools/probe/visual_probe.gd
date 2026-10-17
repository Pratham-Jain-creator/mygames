extends Node
## Probe: server screen with one Daemon of each rarity (long names) under The Cipher.


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/%s.png" % name)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/probe/shots"))
	RunState.start_new_run()
	RunState.network = 3
	RunState.server_index = 2
	RunState.boss_order = ["cipher", "cipher", "cipher", "cipher", "cipher", "cipher", "cipher", "cipher"]
	RunState.money = 30
	for id in ["antivirus", "dead_letter", "razor_deck", "perfect_mirror", "ledger_of_souls"]:
		RunState.add_daemon(id)
	var scr: Control = load("res://scenes/server/server_screen.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(9.0).timeout
	await _shot("visual_cipher")
	get_tree().quit()
