class_name ConsumableService
extends RefCounted
## Applies Executables and Corruptions. The UI gathers targets first
## (via DeckViewer / TypePicker) and then calls use().


static func in_server() -> bool:
	return RunState.server != null and RunState.server.turns_left > 0 and not RunState.server.room.is_empty()


## Empty string when usable, otherwise a human readable reason.
static func why_not(item: Dictionary) -> String:
	if item.kind == Enums.ItemKind.CORRUPTION:
		match item.id:
			"format_c":
				if not in_server():
					return "FORMAT C: CAN ONLY RUN INSIDE A SERVER"
			"worm":
				if not RunState.can_add_daemon():
					return "NO FREE DAEMON SLOT"
				if RunState.deck.size() <= RunState.MIN_DECK_SIZE:
					return "TAILBYTES TOO SMALL"
			"trojan_exe":
				if not RunState.can_add_daemon():
					return "NO FREE DAEMON SLOT"
			"memory_wipe":
				if RunState.deck.size() < RunState.MIN_DECK_SIZE + 5:
					return "TAILBYTES TOO SMALL"
	elif item.id == "shred" or item.id == "clone":
		if item.id == "shred" and RunState.deck.size() <= RunState.MIN_DECK_SIZE:
			return "TAILBYTES TOO SMALL"
	return ""


static func target_range(item: Dictionary) -> Vector2i:
	var d := ItemDB.get_item(item.kind, item.id)
	return Vector2i(int(d.min), int(d.max))


## targets: Array[NodeData]; extra.type: chosen NodeType for Reformat.
## Returns {ok, msg}.
static func use(item: Dictionary, targets: Array, extra: Dictionary = {}) -> Dictionary:
	var reason := why_not(item)
	if reason != "":
		return {"ok": false, "msg": reason}
	var msg := ""
	var in_srv := RunState.server != null and not RunState.server.room.is_empty()
	var reps := 2 if RunState.has_daemon("double_dose") else 1
	if item.kind == Enums.ItemKind.EXECUTABLE and RunState.server != null and not RunState.server.turn_stats.is_empty():
		RunState.server.turn_stats["exe_used"] = int(RunState.server.turn_stats.get("exe_used", 0)) + 1
	match item.id:
		"encrypt":
			var n: NodeData = targets[0]
			n.base_value += 4 * reps
			n.eff_value += 4 * reps
			n.encrypted = true
			msg = "ENCRYPTED %s" % n.label()
		"compress":
			targets[0].zipped = true
			msg = "NODE COMPRESSED (+10 Base Bytes)"
		"reformat":
			var n: NodeData = targets[0]
			n.type = int(extra.get("type", n.type))
			msg = "REFORMATTED INTO %s" % Enums.TYPE_NAMES[n.type]
		"overclock_exe":
			targets[0].holo = true
			msg = "NODE OVERCLOCKED (+1 Overclock when resolved)"
		"gild":
			targets[0].gold = true
			msg = "NODE GILDED"
		"clone":
			var c: NodeData = targets[0].duplicate_node()
			for i in reps:
				c = targets[0].duplicate_node()
				RunState.deck.add_node(c, in_srv)
			msg = "CLONED %s" % c.label()
		"shred":
			var done := 0
			for t in targets:
				if RunState.delete_node(t):
					done += 1
			msg = "SHREDDED %d NODE(S)" % done
		"worm":
			RunState.delete_node(targets[0])
			var pool := DaemonDB.ids_with_rarity(Enums.Rarity.RARE, Enums.Rarity.EPIC)
			var id := _pick_unowned(pool)
			RunState.add_daemon(id)
			msg = "WORM INSTALLED: %s" % DaemonDB.get_def(id).name
		"trojan_exe":
			var pool := DaemonDB.ids_with_rarity(Enums.Rarity.RARE, Enums.Rarity.LEGENDARY)
			var id := _pick_unowned(pool)
			RunState.add_daemon(id)
			RunState.perm_health_bonus -= 5
			RunState.refresh_health()
			msg = "TROJAN.EXE INSTALLED: %s (-5 MAX INT)" % DaemonDB.get_def(id).name
		"memory_wipe":
			var pool := RunState.deck.all_nodes.duplicate()
			pool.shuffle()
			for i in 5:
				RunState.delete_node(pool[i])
			RunState.money += 20
			msg = "5 NODES WIPED. +Ø20"
		"format_c":
			for n: NodeData in RunState.server.room:
				n.type = Enums.NodeType.ICE
				n.base_value = randi_range(11, 14)
				n.eff_value = ServerLogic.effective_value(n)
			EventBus.room_changed.emit()
			msg = "ROOM FORMATTED: ALL NODES ARE NOW FACE-CARD GLITCH"
	if item.kind == Enums.ItemKind.EXECUTABLE and RunState.has_daemon("recycler") and randi() % 3 == 0:
		msg += "  (RECYCLED)"
	else:
		RunState.remove_consumable(item)
	EventBus.deck_changed.emit()
	return {"ok": true, "msg": msg}


static func _pick_unowned(pool: Array) -> String:
	var free: Array = pool.filter(func(i): return not RunState.has_daemon(i))
	if free.is_empty():
		free = pool
	return free.pick_random()
