class_name ServerLogic
extends RefCounted
## Flow of a single Server: begin, deal rooms, flee, preview, payout.

const TUTORIAL_DATA := preload("res://scripts/data/tutorial_script.gd")


static func begin_server() -> ServerState:
	var sv := ServerState.new()
	sv.network = RunState.network
	sv.kind = RunState.server_index
	sv.quota = Progression.quota_for(sv.network, sv.kind)
	sv.boss_id = RunState.boss_for(sv.network) if sv.kind == Enums.ServerKind.BLACK_ICE else ""
	sv.turns_total = RunState.TURNS_PER_SERVER
	if sv.boss_id == "famine":
		sv.turns_total = RunState.TURNS_PER_SERVER - 1
	sv.turns_left = sv.turns_total
	sv.flees_left = RunState.get_flee_limit()
	if sv.boss_id == "shackle":
		sv.flees_left = mini(sv.flees_left, 1)
	elif sv.boss_id == "warden":
		sv.flees_left = 0
	elif sv.boss_id == "tax":
		RunState.money = maxi(0, RunState.money - 3)
	RunState.server = sv
	sv.turn_stats = TurnResolver.fresh_stats()
	RunState.deck.start_server()
	if RunState.tutorial:
		sv.quota = TUTORIAL_DATA.QUOTA
		RunState.deck.stack_top(TUTORIAL_DATA.deck_order())
	var pops := DaemonLogic.fire("server_start")
	DaemonLogic.emit_pops(pops)
	return sv


## Boss / environment adjusted value of a node (Wall, Mirror).
static func effective_value(node: NodeData) -> int:
	var v := node.base_value
	if RunState.is_boss("mirror") and node.type == Enums.NodeType.ICE:
		v *= 2
	if RunState.is_boss("wall"):
		v = mini(v, 10)
	if RunState.is_boss("static") and node.type == Enums.NodeType.DATA:
		v = maxi(1, v - 1)
	if RunState.is_boss("plague") and node.type == Enums.NodeType.ICE:
		v += 3
	return v


## What each Glitch in the room would do, following the Firewall rules of a real turn.
## `selected` is the player's picks in click order: a Firewall picked before a Glitch is
## equipped first, every blocked Glitch lowers the ceiling for the next one, and a Firewall
## switched OFF blocks nothing. Selected Glitches are read at their place in the order; the
## others are shown as if they were picked next. Returns {node uid: {"dmg", "raw"}}.
static func glitch_forecast(selected: Array, room: Array) -> Dictionary:
	var sv: ServerState = RunState.server
	var w: WeaponState = sv.weapon
	var st := {
		"present": w != null, "enabled": sv.weapon_enabled,
		"strength": w.strength if w != null else 0,
		"ceiling": w.ceiling if w != null else 0,
		"first": w.first_bonus if w != null else 0,
		"duct": w.duct_ready if w != null else false,
		"ablative": bool(sv.turn_stats.get("ablative_used", false)),
	}
	var out := {}
	for n: NodeData in selected:
		if n.type == Enums.NodeType.BREACH:
			var strength := n.eff_value + (3 if RunState.has_daemon("sharp_edge") else 0)
			if RunState.has_daemon("heavy_gauge"):
				strength = maxi(0, strength - 1)
			if RunState.is_boss("sponge"):
				strength = maxi(0, strength - 2)
			st.present = true
			st.strength = strength
			st.ceiling = WeaponState.UNLIMITED
			st.first = 2 if RunState.has_daemon("spare_plating") else 0
			st.duct = true
		elif n.type == Enums.NodeType.ICE:
			out[n.uid] = _forecast_hit(st, n.eff_value)
	for n: NodeData in room:
		if n.type == Enums.NodeType.ICE and not out.has(n.uid):
			out[n.uid] = _forecast_hit(st.duplicate(), n.eff_value)
	return out


static func _forecast_hit(st: Dictionary, v: int) -> Dictionary:
	var extra := 1 if RunState.has_daemon("perfect_mirror") else 0
	var use: bool = st.present and st.enabled and v <= int(st.ceiling)
	if not use:
		if RunState.has_daemon("rebound") and st.present and st.enabled:
			st.present = false
		return {"dmg": v + extra, "raw": true}
	var dmg := maxi(0, v + extra - int(st.strength))
	var skip: bool = RunState.has_daemon("duct_tape") and v == int(st.ceiling) and st.duct
	if skip:
		st.duct = false
	else:
		var old := int(st.ceiling)
		var m := 1
		if RunState.is_boss("furnace"):
			m *= 2
		if RunState.is_boss("shatter"):
			m *= 99
		if RunState.has_daemon("failsafe"):
			m *= 2
		var c := (mini(old, 14) - 2 * m) if RunState.has_daemon("brute_force") else (v - m)
		var saved := int(st.first)
		st.first = 0
		if RunState.has_daemon("heavy_gauge"):
			saved += 1
		if RunState.has_daemon("ablative_coating") and not st.ablative:
			st.ablative = true
			saved += 2
		if saved > 0:
			c = mini(old, c + saved)
		if RunState.has_daemon("ironclad"):
			c = maxi(c, mini(old, 14) - 1)
		st.ceiling = c
		if c <= 1:
			st.present = false
	return {"dmg": dmg, "raw": false}


static func deal_room() -> Dictionary:
	var sv: ServerState = RunState.server
	var forced: Array = sv.stash.duplicate()
	sv.stash = []
	var need := maxi(0, RunState.get_room_size() - forced.size())
	var room: Array = forced + RunState.deck.draw(need)
	var notes: Array = []

	var types_shown := (RunState.is_boss("cipher") or (RunState.is_boss("phantom") and sv.turn_number >= 2)) and not RunState.has_daemon("poltergeist")
	var hide_nodes := types_shown or RunState.has_daemon("poltergeist")
	for n: NodeData in room:
		n.eff_value = effective_value(n)
		# A Node carried over in the Stash was revealed when it was stashed: it stays face up.
		n.face_down = hide_nodes and not forced.has(n)
		n.type_known = n.face_down and types_shown
		n.stash_turns = n.stash_turns + 1 if forced.has(n) else 0
		if forced.has(n) and RunState.has_daemon("safe_deposit"):
			n.eff_value += mini(3, n.stash_turns)
		if forced.has(n) and RunState.is_boss("undertow"):
			n.eff_value += 3 * n.stash_turns
	if RunState.has_daemon("blind_trust") and not hide_nodes:
		var fresh: Array = room.filter(func(n): return not forced.has(n))
		if not fresh.is_empty():
			var pick: NodeData = fresh.pick_random()
			pick.face_down = true
			pick.type_known = false
	for n: NodeData in room:
		if n.face_down:
			n.spent_hidden = false
	if RunState.has_daemon("quarantine"):
		for n: NodeData in forced:
			if n.type == Enums.NodeType.ICE:
				n.eff_value = maxi(1, n.eff_value / 2)
				notes.append("QUARANTINE: stashed Glitch halved to %d" % n.eff_value)

	if RunState.has_daemon("honeypot"):
		var weakest: NodeData = null
		var ice_count := 0
		for n: NodeData in room:
			if n.type == Enums.NodeType.ICE:
				ice_count += 1
				if weakest == null or n.eff_value < weakest.eff_value:
					weakest = n
		if ice_count >= 2 and weakest != null:
			var idx := room.find(weakest)
			var repl := RunState.deck.draw(1)
			RunState.deck.discard([weakest])
			notes.append("HONEYPOT: %s self-destructed" % weakest.label())
			DaemonLogic.emit_pops(DaemonLogic.fire("ice_destroyed", {"node": weakest}))
			if repl.is_empty():
				room.remove_at(idx)
			else:
				var r: NodeData = repl[0]
				r.eff_value = effective_value(r)
				r.face_down = hide_nodes
				r.type_known = hide_nodes and types_shown
				room[idx] = r
	sv.room = room
	# Core rule: you ALWAYS resolve exactly 3 Nodes (fewer only if the deck runs dry).
	# No card may change this; the rest of the room is the Stash carried over.
	var need_min := mini(RunState.RESOLVE_COUNT, room.size())
	var need_max := need_min
	return {"room": room, "notes": notes, "required": need_min, "max": need_max}


static func can_flee() -> String:
	var sv: ServerState = RunState.server
	if sv.flees_left <= 0:
		return "NO EJECTS LEFT THIS SERVER"
	if sv.last_action_flee and not RunState.has_voucher("proxy_server"):
		var wind := RunState.has_daemon("second_wind") and int(sv.counters.get("second_wind", 0)) == 0
		if not wind:
			return "CANNOT EJECT TWICE IN A ROW"
	if RunState.deck.draw_pile.size() < RunState.RESOLVE_COUNT:
		return "NOT ENOUGH NODES LEFT TO EJECT"
	if RunState.is_boss("toll") and RunState.money < 3:
		return "THE TOLL BOOTH: EJECTING COSTS Ø3"
	return ""


## Returns {events, died}. The caller redeals afterwards.
static func flee() -> Dictionary:
	var sv: ServerState = RunState.server
	var events: Array = []
	sv.flees_left -= 1
	if RunState.is_boss("toll"):
		RunState.money = maxi(0, RunState.money - 3)
	sv.counters["ejects"] = int(sv.counters.get("ejects", 0)) + 1
	if sv.last_action_flee and RunState.has_daemon("second_wind") and not RunState.has_voucher("proxy_server"):
		sv.counters["second_wind"] = 1
	sv.last_action_flee = true
	sv.fled_this_turn = true
	if sv.turn_number == 1:
		sv.skipped_first_turn = true
	# Skipped Nodes are removed for the rest of this Server (restored next Server).
	for n in sv.room:
		n.stash_turns = 0
	if RunState.has_daemon("peek"):
		# Second Look: ejected Nodes are not lost, they go to the bottom of the draw pile.
		var back: Array = sv.room.filter(func(n): return not n.temporary)
		RunState.deck.put_bottom(back)
	else:
		RunState.deck.discard(sv.room.duplicate())
	sv.room = []
	events.append_array(DaemonLogic.fire("flee"))
	var died := false
	if RunState.is_boss("needle"):
		died = TurnResolver.hurt(5, "needle", events)
	return {"events": events, "died": died}


## Rough pre-daemon preview for the live equation display.
static func preview(selected: Array) -> Dictionary:
	var sv: ServerState = RunState.server
	if selected.is_empty():
		return {"sub": "", "chips": 0.0, "mult": 1.0 + sv.bandwidth_bonus}
	var id := SubroutineDB.identify(selected) if selected.size() >= 3 else ""
	var chips := 0.0
	var mult := 1.0 + sv.bandwidth_bonus
	if id != "":
		var lvl := 0 if RunState.is_boss("rollback") else int(RunState.sub_levels.get(id, 0))
		chips = 0.0 if (RunState.is_boss("void") or RunState.is_boss("null")) else float(SubroutineDB.base_for(id, lvl))
		if not RunState.is_boss("null"):
			mult += SubroutineDB.mult_for(id, lvl)
	# Only the Subroutine's own values are shown while selecting. Each Node's value and
	# every Daemon trigger are added one by one, in Node order, when the turn resolves.
	return {"sub": SubroutineDB.name_of(id) if id != "" else "", "chips": chips, "mult": mult}


## The fast-clear bonus pays Ø1 for every turn you finish under this number (4, +4 per Extended Contract).
static func bonus_turn_limit() -> int:
	var n := RunState.TURNS_PER_SERVER
	for v in RunState.vouchers:
		if v == "extended_contract":
			n += 4
	return n


## Pays out a cleared Server. Returns {lines:[[label, amount]], total}.
static func payout() -> Dictionary:
	var sv: ServerState = RunState.server
	var lines: Array = []
	if RunState.has_daemon("ransomware"):
		lines.append(["RANSOMWARE SEIZED THE PAYOUT", 0])
		return {"lines": lines, "total": 0}
	var base: int = Progression.KIND_REWARD[sv.kind]
	lines.append(["SERVER CLEARED", base])
	var total := base
	if RunState.has_daemon("spotless_record") and sv.damage_taken == 0:
		lines.append(["SPOTLESS RECORD", 3])
		total += 3
	var half_daemons := RunState.daemons.size() / 2
	if RunState.has_daemon("dividend") and half_daemons > 0:
		lines.append(["DIVIDEND", half_daemons])
		total += half_daemons
	if RunState.has_daemon("vending_unit") and sv.flees_left == RunState.get_flee_limit() and RunState.has_consumable_space():
		var ids: Array = ItemDB.EXECUTABLES.keys()
		var pick: String = ids.pick_random()
		RunState.add_consumable(Enums.ItemKind.EXECUTABLE, pick)
		lines.append(["VENDING UNIT: %s" % ItemDB.EXECUTABLES[pick].name.to_upper(), 0])
	var ci := RunState.find_daemon("compound_interest")
	if not ci.is_empty():
		var gain := mini(3 - int(ci.s.n), RunState.money / 10)
		if gain > 0:
			ci.s.n = float(ci.s.n) + gain
			lines.append(["COMPOUND INTEREST: +%d OVERCLOCK (PERMANENT)" % gain, 0])
	var unused := bonus_turn_limit() - (sv.turn_number - 1)
	if unused > 0:
		lines.append(["FAST-CLEAR BONUS (%d TURNS UNDER %d)" % [unused, bonus_turn_limit()], unused])
		total += unused
	# Interest: Ø1 per Ø5 held, capped at Ø5. Investment Bank doubles both (Ø2 per Ø5, max Ø10).
	var bank := RunState.has_daemon("investment_bank")
	var cap := (10 if bank else 5) + (5 if RunState.has_voucher("offshore_account") else 0)
	var interest := mini(cap, (RunState.money / 5) * (2 if bank else 1))
	if interest > 0:
		lines.append(["INVESTMENT BANK INTEREST" if bank else "INTEREST (Ø1 PER Ø5, MAX Ø%d)" % cap, interest])
		total += interest
	RunState.money += total
	return {"lines": lines, "total": total}
