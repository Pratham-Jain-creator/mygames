extends Node
## Dev helper: runs one Execute and saves a frame every 0.1s of the first 1.6s (flight_NN.png).

func _ready() -> void:
	var scr: Control = null
	var cards: Array = []
	var picks: Array = []
	for attempt in 12:
		RunState.start_new_run()
		scr = load("res://scenes/server/server_screen.tscn").instantiate()
		add_child(scr)
		await get_tree().create_timer(2.5).timeout
		cards = scr.get("_cards")
		var last: int = cards.size() - 1
		var others: Array = []
		for i in last:
			if cards[i].data.type != Enums.NodeType.ICE:
				others.append(i)
		if cards[last].data.type != Enums.NodeType.ICE and others.size() >= 2:
			picks = [others[0], last, others[1]]
			break
		scr.queue_free()
		await get_tree().create_timer(0.3).timeout
	for i in picks:
		scr.call("_on_card_activated", cards[i])
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(0.5).timeout
	scr.call("_on_execute")
	for n in 20:
		await get_tree().create_timer(0.2).timeout
		get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/flight_%02d.png" % n)
	print("FLIGHT DONE")
