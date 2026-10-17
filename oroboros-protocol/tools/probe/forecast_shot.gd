extends Node
## Probe: screenshot of Glitch forecasts on the real screen (Firewall 6 equipped, one pick made).

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/%s.png" % n)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/probe/shots"))
	RunState.start_new_run()
	RunState.network = 2
	RunState.server_index = 1
	var scr: Control = load("res://scenes/server/server_screen.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(6.0).timeout
	var sv := RunState.server
	var B := Enums.NodeType.BREACH
	var I := Enums.NodeType.ICE
	var D := Enums.NodeType.DATA
	var C := Enums.NodeType.COOLANT
	sv.room = [NodeData.new(B, 10), NodeData.new(I, 9), NodeData.new(I, 12), NodeData.new(D, 7)]
	sv.weapon = null
	scr._build_room_cards(false)
	await get_tree().create_timer(2.0).timeout
	scr._on_card_activated(scr._cards[0])   # Firewall 10 first
	await get_tree().create_timer(0.8).timeout
	await _shot("forecast_a")
	scr._on_weapon_toggle(null)             # Firewall OFF
	await get_tree().create_timer(0.8).timeout
	await _shot("forecast_b")
	get_tree().quit()
