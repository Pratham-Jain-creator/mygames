extends Node
## Probe: stage a death by a Glitch 12 and show the game-over screen.


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/probe/shots"))
	seed(7)
	RunState.start_new_run()
	RunState.network = 3
	RunState.server_index = 2
	RunState.boss_order = ["cipher", "cipher", "cipher", "cipher", "cipher", "cipher", "cipher", "cipher"]
	for id in ["antivirus", "razor_deck", "perfect_mirror", "ledger_of_souls"]:
		RunState.add_daemon(id)
	var sv := ServerLogic.begin_server()
	sv.score = 4368
	RunState.stats["servers_cleared"] = 7
	RunState.health = 3
	var g := NodeData.new(Enums.NodeType.ICE, 12)
	g.eff_value = 12
	var a := NodeData.new(Enums.NodeType.DATA, 5)
	a.eff_value = 5
	var b := NodeData.new(Enums.NodeType.DATA, 6)
	b.eff_value = 6
	sv.room = [g, a, b]
	var res := TurnResolver.resolve([g, a, b], [])
	RunState.end_run(false, "SERVER DESTROYED")
	print("died=", res.died, " report=", RunState.death_report)
	var scr: Control = load("res://scenes/game_over/game_over.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/death.png")
	get_tree().quit()
