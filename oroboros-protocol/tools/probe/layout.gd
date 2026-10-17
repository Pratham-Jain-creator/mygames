extends Node
## Dev helper: reports the minimum size of the Server screen layout so overflow is caught.


func _ready() -> void:
	RunState.start_new_run()
	for i in 3:
		RunState.add_daemon(DaemonDB.all_ids()[i * 7])
	var scr: Control = load("res://scenes/server/server_screen.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(2.0).timeout
	var vp := get_viewport().get_visible_rect().size
	print("LAYOUT viewport ", vp)
	var layout: Control = scr.get_node("SafeArea/Layout")
	print("LAYOUT min ", layout.get_combined_minimum_size(), " size ", layout.size)
	for path in ["SafeArea/Layout/TopBar/TopRow", "SafeArea/Layout/MiddleZone/ActionRow", "SafeArea/Layout/MiddleZone/StashRow", "SafeArea/Layout/BottomZone/BottomRow"]:
		var c: Control = scr.get_node(path)
		print("LAYOUT ", path, " min ", c.get_combined_minimum_size(), " rect ", c.get_global_rect())
	print("LAYOUT root rect ", scr.get_global_rect())
	print("LAYOUT DONE")
