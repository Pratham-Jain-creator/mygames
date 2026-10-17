extends Node
## Dev helper: selects cards (last room card as queue #2, no Glitch picked so nobody dies),
## presses EXECUTE and logs how each card looks while resolving.

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
	print("EXEC picks ", picks, " types ", cards.map(func(c): return c.data.type))
	for i in picks:
		scr.call("_on_card_activated", cards[i])
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(0.5).timeout
	scr.call("_on_execute")
	for t in 22:
		await get_tree().create_timer(0.35).timeout
		var line := "EXEC t=%.2f phase=%s hp=%d " % [(t + 1) * 0.35, str(scr.get("phase")), RunState.health]
		for c in scr.get("_cards"):
			if is_instance_valid(c):
				line += " [a=%.2f s=%.2f]" % [c.visual.modulate.a, c.visual.scale.x]
		print(line)
		if t == 4 or t == 6:
			_shot("exec_mid%d" % t)
	_shot("exec_end")
	print("EXEC DONE")


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/%s.png" % n)
