class_name TurnResolver
extends RefCounted
## Resolves one turn: executes the 3 chosen Nodes in order (equip / fight / heal /
## bank data), then scores the Subroutine. Game state is mutated immediately; the UI
## replays the returned `events` and `breakdown` to animate everything.


## Hard ceiling for one turn's score (keeps every number a safe 64-bit integer).
const MAX_SCORE := 1.0e15


static func fresh_stats() -> Dictionary:
	return {
		"damage_instances": 0, "damage_total": 0, "coolant_used": 0,
		"weapons_broken": 0, "ice_destroyed": [], "holo": 0,
		"firewall_left": 3 if RunState.has_daemon("firewall") else 0,
		"perfect_blocks": 0, "perfect_strength": 0, "exe_used": 0,
		"face_down_resolved": 0, "rebound_bytes": 0, "overheal": 0,
		"ablative_used": false, "raw_glitches": [], "face_down_uids": [],
	}


## Applies damage to the Rig. Returns true if the Rig died.
static func hurt(amount: int, source: String, events: Array, node: NodeData = null) -> bool:
	var sv: ServerState = RunState.server
	var stats: Dictionary = sv.turn_stats
	if amount > 0 and source == "ice" and int(stats.firewall_left) > 0:
		var absorbed := mini(int(stats.firewall_left), amount)
		stats.firewall_left = int(stats.firewall_left) - absorbed
		amount -= absorbed
		var fw_ev := {"t": "firewall", "absorbed": absorbed}
		if amount <= 0 and absorbed > 0:
			# Shock Absorber took the whole hit: it still counts as a hit for Overclock.
			sv.bandwidth_bonus += 1
			fw_ev["bw"] = sv.bandwidth_bonus
		events.append(fw_ev)
	if amount > 0 and amount <= RunState.pain_tolerance_limit():
		events.append_array(DaemonLogic.fire("pain_tolerance_pop", {}))
		return false
	if amount <= 0:
		return false
	var had_bo := RunState.has_daemon("buffer_overflow")
	if source != "ice":
		sv.last_hit = {"source": source, "dmg": amount}
	var died := RunState.lose_health(amount)
	sv.damage_taken += amount
	stats.damage_instances = int(stats.damage_instances) + 1
	stats.damage_total = int(stats.damage_total) + amount
	RunState.stats["damage_taken"] = int(RunState.stats.get("damage_taken", 0)) + amount
	sv.bandwidth_bonus += 1
	events.append_array(DaemonLogic.fire("damage", {"amount": amount}))
	events.append({
		"t": "damage", "amount": amount, "health": RunState.health,
		"source": source, "node": node, "bw": sv.bandwidth_bonus,
	})
	if had_bo and not RunState.has_daemon("buffer_overflow"):
		events.append({"t": "buffer_overflow", "health": RunState.health})
	return died


static func resolve(selected: Array, leftover: Array) -> Dictionary:
	var sv: ServerState = RunState.server
	var stats: Dictionary = sv.turn_stats
	var events: Array = []
	var died := false
	var room_types: Array = []
	for n in sv.room:
		room_types.append(n.type)

	var counts := [0, 0, 0, 0]
	for n in selected:
		counts[n.type] += 1

	# The Leak / The Hemorrhage: Integrity drains at the start of every turn.
	if RunState.is_boss("leak") or RunState.is_boss("hemorrhage"):
		died = hurt(1, "leak", events)

	# ---------------------------------------------------- 1. execute nodes
	for node: NodeData in selected:
		if died:
			break
		if node.face_down:
			stats.face_down_resolved = int(stats.face_down_resolved) + 1
			stats.face_down_uids.append(node.uid)
			if RunState.has_daemon("blind_trust"):
				node.spent_hidden = true
		node.face_down = false
		var v := node.eff_value
		match node.type:
			Enums.NodeType.BREACH:
				var strength := v + (3 if RunState.has_daemon("sharp_edge") else 0)
				if RunState.has_daemon("heavy_gauge"):
					strength = maxi(0, strength - 1)
				if RunState.is_boss("sponge"):
					strength = maxi(0, strength - 2)
				sv.weapon = WeaponState.new(node, strength)
				if RunState.has_daemon("spare_plating"):
					sv.weapon.first_bonus = 2
				events.append({"t": "equip", "node": node, "strength": strength, "ceiling": sv.weapon.ceiling})
				events.append_array(DaemonLogic.fire("equip", {"node": node}))
			Enums.NodeType.ICE:
				died = _fight(node, events)
			Enums.NodeType.COOLANT:
				stats.coolant_used = int(stats.coolant_used) + 1
				if RunState.patch_factor() <= 0.0:
					# The Leech / The Reaper: Patch Nodes restore nothing (they do NOT turn into attacks).
					events.append({"t": "leech", "node": node})
				else:
					var amount := int(floor(v * (2 if RunState.has_daemon("antivirus") else 1) * RunState.patch_factor()))
					var healed := RunState.heal(amount)
					events.append({"t": "heal", "node": node, "amount": healed, "health": RunState.health})
			Enums.NodeType.DATA:
				events.append({"t": "data", "node": node})
		if died:
			break
		if node.gold:
			var gain := 3 if RunState.has_daemon("golden_ticket") else 1
			RunState.money += gain
			events.append({"t": "money", "amount": gain, "node": node})
		if node.holo:
			stats.holo = int(stats.holo) + 1
		events.append_array(DaemonLogic.fire("node_resolved", {"node": node}))

	var result := {"events": events, "end_events": [], "died": died, "score": 0, "breakdown": [], "sub_id": "", "chips": 0, "mult": 1.0}
	if died:
		result.end_events = _cleanup(selected, leftover, events, "", "")
		return result

	# ---------------------------------------------------------- 2. scoring
	var most_used := _most_used()
	var sub_id := SubroutineDB.identify(selected)
	sv.subs_played[sub_id] = int(sv.subs_played.get(sub_id, 0)) + 1
	RunState.sub_play_counts[sub_id] = int(RunState.sub_play_counts.get(sub_id, 0)) + 1

	var level: int = 0 if RunState.is_boss("rollback") else int(RunState.sub_levels.get(sub_id, 0))
	var base := SubroutineDB.base_for(sub_id, level)
	var sub_mult := SubroutineDB.mult_for(sub_id, level)
	if RunState.is_boss("void") or RunState.is_boss("null"):
		base = 0
	if RunState.is_boss("null"):
		sub_mult = 0

	var stash_after: Array = [] if RunState.is_boss("lock") else leftover
	var ctx := {
		"nodes": selected, "sub_id": sub_id, "counts": counts, "stats": stats,
		"stash_after": stash_after, "room_types": room_types,
		"first_turn": sv.turn_number == 1, "final_turn": sv.turn_number == RunState.TURNS_PER_SERVER,
		"flee_first": sv.skipped_first_turn,
		"chips": float(base), "mult": 1.0 + sv.bandwidth_bonus + sub_mult,
		"bonus_sum": float(sub_mult), "breakdown": [],
		"trig": {}, "flat": {},
	}
	ctx.breakdown.append({
		"uid": -1, "kind": "sub", "text": SubroutineDB.name_of(sub_id).to_upper(),
		"chips": ctx.chips, "mult": ctx.mult, "name": SubroutineDB.name_of(sub_id),
	})
	for node: NodeData in selected:
		var add := float(node.eff_value) * (2.0 if (node.type == Enums.NodeType.DATA and not RunState.is_boss("sieve")) else 1.0)
		if node.zipped:
			add += 10.0
		ctx.chips += add
		if node.holo:
			ctx.mult += 1.0
			ctx.bonus_sum += 1.0
		ctx.breakdown.append({
			"uid": -1, "kind": "node", "node": node,
			"text": "+%d%s" % [int(add), " +1 Overclock" if node.holo else ""],
			"chips": ctx.chips, "mult": ctx.mult, "name": node.label(),
		})
		# Node-triggered Daemons fire right now, left to right, before the next Node.
		for inst in DaemonLogic.effective_list():
			DaemonLogic.score_node(inst, node, ctx)
	for inst in DaemonLogic.effective_list():
		DaemonLogic.score(inst, ctx)
	for inst in DaemonLogic.effective_list():
		DaemonLogic.score_late(inst, ctx)

	var final_mult := maxf(1.0, ctx.mult)
	var raw_score: float = ctx.chips * final_mult
	if RunState.is_boss("frost") and sv.turn_number == 1:
		raw_score *= 0.5
	# Safety: never let a runaway build become NaN / INF / an overflowed integer.
	if is_nan(raw_score):
		raw_score = 0.0
	raw_score = clampf(raw_score, 0.0, MAX_SCORE)
	var final_score := int(floor(raw_score))
	if RunState.is_boss("choke"):
		final_score = mini(final_score, int(sv.quota * 0.45))
	sv.score += final_score
	sv.best_turn = maxi(sv.best_turn, final_score)
	RunState.stats["best_turn"] = maxi(int(RunState.stats.get("best_turn", 0)), final_score)
	sv.last_turn_bonus = ctx.bonus_sum

	result.score = final_score
	result.breakdown = ctx.breakdown
	result.sub_id = sub_id
	result.chips = ctx.chips
	result.mult = final_mult

	# ------------------------------------------------------- 3. turn end
	# Turn-end income (Mining Rig...) is replayed AFTER the score cascade.
	result.end_events = _cleanup(selected, leftover, events, sub_id, most_used)
	if bool(sv.turn_stats.get("died", false)):
		result.died = true
	result.events = events
	return result


static func _fight(node: NodeData, events: Array) -> bool:
	var sv: ServerState = RunState.server
	var stats: Dictionary = sv.turn_stats
	var v := node.eff_value
	var w: WeaponState = sv.weapon
	var use_weapon := w != null and sv.weapon_enabled and v <= w.ceiling
	# Rebound: a Glitch above the Ceiling that hits you also breaks the Firewall.
	var overcap_break := RunState.has_daemon("rebound") and w != null and sv.weapon_enabled and not use_weapon
	if not use_weapon:
		stats.raw_glitches.append(node.uid)
	var extra := 1 if RunState.has_daemon("perfect_mirror") else 0
	var dmg := v + extra
	var ev := {"t": "fight", "node": node, "weapon_used": use_weapon, "value": v}
	if use_weapon:
		dmg = maxi(0, v + extra - w.strength)
		ev["strength"] = w.strength
		ev["ceiling_old"] = w.ceiling
		var skip := false
		if RunState.has_daemon("duct_tape") and v == w.ceiling and w.duct_ready:
			w.duct_ready = false
			skip = true
		if not skip:
			var old_ceiling := w.ceiling
			var m := 1
			if RunState.is_boss("furnace"):
				m *= 2
			if RunState.is_boss("shatter"):
				m *= 99
			if RunState.has_daemon("failsafe"):
				m *= 2
			if RunState.has_daemon("brute_force"):
				# An unlimited ceiling first collapses to the highest Node value (14).
				w.ceiling = mini(w.ceiling, 14) - 2 * m
			else:
				w.ceiling = v - m
			# Firewall Daemons: ceiling saved on this hit (never above the previous Ceiling).
			var saved := w.first_bonus
			w.first_bonus = 0
			if RunState.has_daemon("heavy_gauge"):
				saved += 1
			if RunState.has_daemon("ablative_coating") and not bool(stats.ablative_used):
				stats.ablative_used = true
				saved += 2
			if saved > 0:
				w.ceiling = mini(old_ceiling, w.ceiling + saved)
			if RunState.has_daemon("ironclad"):
				w.ceiling = maxi(w.ceiling, mini(old_ceiling, 14) - 1)
		ev["ceiling_new"] = w.ceiling
		ev["strength_after"] = w.strength
	events.append(ev)
	var absorb := mini(int(stats.firewall_left), dmg)
	var perfect := use_weapon and dmg - absorb <= 0
	sv.last_hit = {
		"value": v, "dmg": dmg, "absorbed": absorb,
		"weapon_present": w != null and sv.weapon_enabled, "weapon_used": use_weapon,
		"ceiling": int(ev.get("ceiling_old", 0)) if use_weapon else (w.ceiling if w != null else 0),
		"strength": w.strength if w != null else 0,
	}
	var died := hurt(dmg, "ice", events, node)
	stats.ice_destroyed.append(node)
	events.append_array(DaemonLogic.fire("ice_destroyed", {"node": node}))
	if died:
		return true
	if perfect:
		stats.perfect_blocks = int(stats.perfect_blocks) + 1
		stats.perfect_strength = int(stats.perfect_strength) + w.strength
		events.append_array(DaemonLogic.fire("perfect_block", {"node": node, "weapon": w}))
		ev["ceiling_new"] = w.ceiling
	if (use_weapon and w.ceiling <= 1) or overcap_break:
		w.ceiling = 0
		events.append({"t": "weapon_break", "node": w.node})
		sv.weapon = null
		stats.weapons_broken = int(stats.weapons_broken) + 1
		if RunState.has_daemon("rebound"):
			stats.rebound_bytes = int(stats.rebound_bytes) + 5 * v
		events.append_array(DaemonLogic.fire("weapon_break", {"value": v}))
		events.append({"t": "heal_sync", "health": RunState.health})
	return false


static func _most_used() -> String:
	var best := ""
	var best_n := 0
	for k in RunState.sub_play_counts:
		if int(RunState.sub_play_counts[k]) > best_n:
			best_n = int(RunState.sub_play_counts[k])
			best = k
	return best


static func _cleanup(selected: Array, leftover: Array, events: Array, sub_id: String, most_used: String) -> Array:
	var sv: ServerState = RunState.server
	var stats: Dictionary = sv.turn_stats
	# Unresolved nodes: stashed (forced into the next room) or lost under The Lock.
	# The Cipher / Poltergeist: the one Node that goes to the Stash is revealed, so the
	# face-down game is about reading the Tailbytes, not pure luck.
	for n in leftover:
		n.face_down = false
	for n in selected:
		n.stash_turns = 0
	if sub_id != "" and sub_id == sv.last_sub:
		sv.counters["habit"] = int(sv.counters.get("habit", 0)) + 1
	else:
		sv.counters["habit"] = 0
	sv.last_sub = sub_id
	if sv.fled_this_turn:
		sv.counters["eject_turns"] = int(sv.counters.get("eject_turns", 0)) + 1
		sv.counters["tempo"] = 0
	else:
		sv.counters["tempo"] = int(sv.counters.get("tempo", 0)) + 1
	for n in leftover:
		events.append_array(DaemonLogic.fire("bypass", {"node": n}))
	if RunState.is_boss("lock"):
		RunState.deck.discard(leftover)
		sv.stash = []
	else:
		sv.stash = leftover.duplicate()
	RunState.deck.discard(selected)
	var data_count := 0
	for n in selected:
		if n.type == Enums.NodeType.DATA:
			data_count += 1
	var te := {"data_count": data_count, "sub": sub_id, "most_used": most_used, "died": false}
	var end_events: Array = DaemonLogic.fire("turn_end", te)
	if te.died:
		sv.turn_stats["died"] = true
	sv.turn_number += 1
	sv.turns_left -= 1
	sv.last_action_flee = false
	sv.fled_this_turn = false
	sv.room = []
	var keep_died: bool = bool(sv.turn_stats.get("died", false))
	sv.turn_stats = fresh_stats()
	if keep_died:
		sv.turn_stats["died"] = true
	stats.clear()
	return end_events
