extends Node
## Dev helper: opens the Server screen, selects two Nodes and saves screenshots to tools/probe/shots/.

func _ready() -> void:
	RunState.start_new_run()
	var ids: Array = DaemonDB.all_ids()
	for i in 4:
		RunState.add_daemon(ids[i * 9])
	var scr: Control = load("res://scenes/server/server_screen.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(3.0).timeout
	_shot("room_a")
	var cards: Array = scr.get("_cards")
	if cards.size() >= 2:
		scr.call("_on_card_activated", cards[0])
		scr.call("_on_card_activated", cards[1])
	await get_tree().create_timer(1.0).timeout
	var dcs := scr.find_children("*", "DaemonCard", true, false)
	_shot("room_b")
	for d in dcs:
		if not d.inst.is_empty():
			d.flash()
			break
	await get_tree().create_timer(0.35).timeout
	_shot("daemon_fx1")
	await get_tree().create_timer(0.2).timeout
	_shot("daemon_fx2")
	scr.call("_on_weapon_toggle", null)
	await get_tree().create_timer(0.6).timeout
	_shot("room_off")
	var dv = load("res://scenes/components/deck_viewer/deck_viewer.tscn").instantiate()
	scr.add_child(dv)
	dv.open_view()
	await get_tree().create_timer(1.2).timeout
	_shot("deck")
	print("SHOT DONE")


func _shot(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tools/probe/shots/%s.png" % n)
	print("SHOT ", n, " ", img.get_size())
