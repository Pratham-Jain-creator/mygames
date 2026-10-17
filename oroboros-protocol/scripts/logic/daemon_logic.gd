class_name DaemonLogic
extends RefCounted
## Behaviour of all 167 Daemons.
##  * score()  - called per Daemon (left to right) while a turn is scored.
##  * fire()   - event hooks (growth, money, healing...). Returns "pop" dictionaries
##               so the UI can flash the right Daemon.
## Daemon instance: {id, uid, sell_bonus, s:{n:float,...}}.
## Blueprint produces virtual copies {copy:true} that share the source's state `s`.

const FIBS := [2, 3, 5, 8, 13]
const PRIMES := [2, 3, 5, 7, 11, 13]


# ------------------------------------------------------------------ helpers
## The Gag / The Purge disable the leftmost Daemon slots.
static func is_disabled(i: int) -> bool:
	if RunState.is_boss("gag"):
		return i < 1
	if RunState.is_boss("purge"):
		return i < 2
	return false


static func effective_list() -> Array:
	var out: Array = []
	var list: Array = RunState.daemons
	for i in list.size():
		if is_disabled(i):
			continue
		var d: Dictionary = list[i]
		if d.id == "blueprint":
			var j := i + 1
			while j < list.size() and list[j].id == "blueprint":
				j += 1
			if j < list.size():
				var src: Dictionary = list[j]
				out.append({"id": src.id, "uid": d.uid, "s": src.s, "copy": true, "sell_bonus": 0})
		else:
			out.append(d)
	return out


static func _fmt(v: float) -> String:
	var s := "%.2f" % v
	s = s.rstrip("0").rstrip(".")
	return s


## `money` is the $ this pop earned, so the UI can raise the displayed balance
## exactly when the Daemon visibly triggers (logic applies it instantly).
static func _pop(d: Dictionary, text: String, money := 0) -> Dictionary:
	return {"t": "pop", "uid": d.uid, "text": text, "money": money}


static func emit_pops(pops: Array) -> void:
	for p in pops:
		EventBus.daemon_popup.emit(p.uid, p.text)


static func _log(ctx: Dictionary, inst: Dictionary, kind: String, text: String) -> void:
	ctx.breakdown.append({
		"uid": inst.uid, "kind": kind, "text": text,
		"chips": ctx.chips, "mult": ctx.mult,
		"name": DaemonDB.get_def(inst.id).name,
	})


## Remembers which Daemons triggered and their flat Overclock (Conductor, Hall of Mirrors).
static func _track(ctx: Dictionary, inst: Dictionary, flat: float) -> void:
	if not ctx.has("trig"):
		return
	ctx.trig[inst.uid] = true
	if flat > 0.0:
		ctx.flat[inst.uid] = float(ctx.flat.get(inst.uid, 0.0)) + flat


# ---- small queries used by the newer Daemons
static func _idx(inst: Dictionary) -> int:
	for i in RunState.daemons.size():
		if RunState.daemons[i].uid == inst.uid:
			return i
	return -1


static func _rarity_count(pred: Callable) -> int:
	var n := 0
	for d in RunState.daemons:
		if pred.call(int(DaemonDB.get_def(d.id).rarity)):
			n += 1
	return n


static func _cnt(key: String) -> int:
	return int(RunState.server.counters.get(key, 0)) if RunState.server != null else 0


static func _bump(key: String) -> void:
	RunState.server.counters[key] = _cnt(key) + 1


static func _chips(ctx: Dictionary, inst: Dictionary, amount: float) -> void:
	if amount == 0.0:
		return
	ctx.chips += amount
	_track(ctx, inst, 0.0)
	_log(ctx, inst, "chips", "+%s Base" % _fmt(amount))


static func _mult(ctx: Dictionary, inst: Dictionary, amount: float) -> void:
	if amount == 0.0:
		return
	ctx.mult += amount
	_track(ctx, inst, amount)
	if inst.id != "echo":
		ctx.bonus_sum += amount
	_log(ctx, inst, "mult", "%s%s Overclock" % ["+" if amount > 0.0 else "", _fmt(amount)])


static func _xmult(ctx: Dictionary, inst: Dictionary, x: float) -> void:
	ctx.mult *= x
	_track(ctx, inst, 0.0)
	_log(ctx, inst, "xmult", "x%s" % _fmt(x))


# ------------------------------------------------------------------ scoring
static func score(inst: Dictionary, ctx: Dictionary) -> void:
	var s: Dictionary = inst.s
	var nodes: Array = ctx.nodes
	var counts: Array = ctx.counts          # [data, ice, breach, coolant]
	var stats: Dictionary = ctx.stats
	var sv: ServerState = RunState.server
	match inst.id:
		# ---- Base Data ----
		# (floppy_disk, binary_*, low_level_format, mainframe_access, prime_directive,
		#  fibonacci, syringe, neon_sign, redundant_array fire per Node: see score_node)
		"overload":
			if ctx.sub_id == "data_dump":
				_chips(ctx, inst, 20.0)
		"basic_overclock":
			# First turn of the Server only (it used to stick for every turn).
			if ctx.first_turn:
				_mult(ctx, inst, 3.0)
		"cache_clear":
			if ctx.first_turn:
				_chips(ctx, inst, 25.0)
		"cloud_sync":
			if ctx.stash_after.any(func(st): return st.type == Enums.NodeType.DATA):
				_chips(ctx, inst, 10.0)
		"scraper_script":
			_chips(ctx, inst, 5.0 * int(stats.damage_instances))
		"memory_leak":
			_chips(ctx, inst, float(randi_range(0, 23)))
		"overwritten_file":
			_chips(ctx, inst, 2.0 * s.n)
			_mult(ctx, inst, minf(5.0, 0.25 * s.n))
		"scrap_metal":
			var total := 0
			for n in stats.ice_destroyed:
				total += n.eff_value
			_chips(ctx, inst, float(total))
		"bloatware":
			_chips(ctx, inst, 50.0)
		"heat_sink":
			if RunState.health < 5:
				_chips(ctx, inst, 30.0)
		"flash_drive":
			if ctx.final_turn:
				_chips(ctx, inst, 30.0)
		"ram_check":
			var types := {}
			for t in ctx.room_types:
				types[t] = true
			if types.size() == 4:
				_chips(ctx, inst, 60.0)
		# ---- Bandwidth (flat) ----
		"masochist":
			_mult(ctx, inst, s.n)
		"diamond_chip":
			if counts[Enums.NodeType.DATA] == 1:
				_mult(ctx, inst, 4.0)
		"gold_wire":
			if counts[Enums.NodeType.DATA] == 0:
				_mult(ctx, inst, 5.0)
		"multi_thread":
			var w := 0
			for st in ctx.stash_after:
				if st.type == Enums.NodeType.BREACH:
					w += 1
			_mult(ctx, inst, 2.0 * w)
		"trojan":
			_mult(ctx, inst, s.n)
		"keylogger":
			if ctx.final_turn:
				_mult(ctx, inst, 10.0)
		"logic_bomb":
			if ctx.sub_id == "surgical_strike":
				_mult(ctx, inst, 4.0)
		"proxy":
			_mult(ctx, inst, minf(8.0, float(floori(RunState.money / 5.0))))
		"vampire":
			_mult(ctx, inst, float(stats.coolant_used))
		"rust":
			_chips(ctx, inst, 50.0)
			_mult(ctx, inst, s.n)
			s.n = maxf(0.0, s.n - 1.0)
		"echo":
			_mult(ctx, inst, sv.last_turn_bonus)
		"stutter":
			var seen := {}
			var hit := false
			for n in nodes:
				if seen.has(n.eff_value):
					hit = true
				seen[n.eff_value] = true
			if hit:
				_mult(ctx, inst, 4.0)
		"benchmark":
			if ctx.chips * ctx.mult > 500.0:
				_mult(ctx, inst, 4.0)
		"cooling_paste":
			if RunState.health == RunState.get_max_health():
				_mult(ctx, inst, 3.0)
		"blood_magic":
			_mult(ctx, inst, 5.0)
		"synergizer":
			var my_r: int = DaemonDB.get_def(inst.id).rarity
			var diff := 0
			for d in RunState.daemons:
				if d.id != inst.id and DaemonDB.get_def(d.id).rarity != my_r:
					diff += 1
			_mult(ctx, inst, float(diff))
		"overvolt":
			_mult(ctx, inst, 2.0 * int(stats.weapons_broken))
		# ---- Bandwidth multipliers ----
		"bottleneck":
			if nodes.size() >= 3 and nodes.all(func(n): return n.eff_value <= 6):
				_xmult(ctx, inst, 2.0)
		"spyware":
			if s.n > 0.0:
				_xmult(ctx, inst, 1.0 + 0.1 * s.n)
		"glass_cannon":
			_xmult(ctx, inst, 2.0)
		"the_core":
			if sv.subs_played.size() == 1:
				_xmult(ctx, inst, 3.0)
		"black_hole":
			if RunState.health == 1:
				_xmult(ctx, inst, 4.0)
		"infinity_loop":
			if ctx.flee_first:
				_xmult(ctx, inst, 1.5)
		"quantum_chip":
			_xmult(ctx, inst, [1.0, 1.25, 1.5, 2.0].pick_random())
		"obelisk":
			if s.n > 0.0:
				_xmult(ctx, inst, 1.0 + 0.3 * minf(10.0, s.n))
		"poltergeist":
			_xmult(ctx, inst, 2.0)
		"singularity":
			# The x4 only applies if this Server's start fee was actually paid.
			if bool(s.get("paid_%d" % int(inst.uid), false)):
				_xmult(ctx, inst, 4.0)
		"ransomware":
			_xmult(ctx, inst, 3.0)
		_:
			_score_new(inst, ctx)


## The Daemons added in the 167-card expansion.
static func _score_new(inst: Dictionary, ctx: Dictionary) -> void:
	var s: Dictionary = inst.s
	var nodes: Array = ctx.nodes
	var stats: Dictionary = ctx.stats
	var sv: ServerState = RunState.server
	var pb := int(stats.get("perfect_blocks", 0))
	var ice := (stats.ice_destroyed as Array).size()
	var deck_n := RunState.deck.size()
	var left := RunState.deck.draw_pile.size()
	var below := maxi(0, 52 - deck_n)
	var fd := int(stats.get("face_down_resolved", 0))
	var hp := RunState.health
	match inst.id:
		# ---- Perfect Block ----
		"clean_sweep":
			_chips(ctx, inst, 15.0 * pb)
		"mirror_plating":
			_mult(ctx, inst, float(pb))
		"streak_counter":
			_mult(ctx, inst, minf(3.0, 0.5 * s.n))
		"aegis_protocol":
			if ice >= 2 and pb == ice:
				_xmult(ctx, inst, 2.0)
		"deflector":
			_chips(ctx, inst, float(stats.get("perfect_strength", 0)))
		"iron_ledger":
			_chips(ctx, inst, 2.0 * s.n)
		"spotless_record":
			if ctx.final_turn and sv.damage_taken == 0:
				_xmult(ctx, inst, 2.0)
		# ---- Fewer Tailbytes ----
		"lean_build":
			if deck_n <= 40:
				_mult(ctx, inst, 4.0)
		"dead_drop":
			if left < 20:
				_chips(ctx, inst, 25.0)
		"minimalist":
			_mult(ctx, inst, 0.1 * below)
		"skeleton_crew":
			_chips(ctx, inst, 2.0 * below)
		"razor_deck":
			if deck_n <= 30:
				_xmult(ctx, inst, 1.5)
		"zen_garden":
			if below > 0:
				_xmult(ctx, inst, 1.0 + 0.02 * below)
		"cutting_it_close":
			if left <= 4:
				_xmult(ctx, inst, 3.0)
		# ---- Modified Nodes ----
		"custom_build":
			if nodes.size() >= 3 and nodes.all(func(n): return n.is_modified()):
				_mult(ctx, inst, 3.0)
		"showpiece":
			if ctx.stash_after.any(func(n): return n.is_modified()):
				_chips(ctx, inst, 10.0)
		"collectors_edition":
			var mods := 0
			for n in RunState.deck.all_nodes:
				if n.is_modified():
					mods += 1
			_mult(ctx, inst, minf(5.0, 0.5 * mods))
		# ---- Glue ----
		"duo":
			var best := 0
			for r in 5:
				best = maxi(best, _rarity_count(func(x): return x == r))
			if best >= 2:
				_mult(ctx, inst, 2.0)
		"anchor":
			_chips(ctx, inst, 10.0 * _rarity_count(func(x): return x >= 2))
		"odd_couple":
			if _rarity_count(func(x): return x == 0) > 0 and _rarity_count(func(x): return x == 2) > 0:
				_chips(ctx, inst, 20.0)
		"neighbour_watch":
			var i := _idx(inst)
			var adj := 0
			if i > 0:
				adj += 1
			if i >= 0 and i < RunState.daemons.size() - 1:
				adj += 1
			_mult(ctx, inst, float(adj))
		"chain_link":
			_chips(ctx, inst, 5.0 * maxi(0, _idx(inst)))
		"understudy":
			_understudy(inst, ctx, null)
		"full_house":
			if RunState.daemons.size() >= RunState.MAX_DAEMONS:
				_xmult(ctx, inst, 2.0)
		# ---- Firewall ----
		"rebound":
			_chips(ctx, inst, float(stats.get("rebound_bytes", 0)))
		"overcharge":
			if sv.weapon != null:
				_mult(ctx, inst, float(sv.weapon.strength / 5))
		# ---- Subroutines ----
		"macro":
			_chips(ctx, inst, 10.0 * sv.subs_played.size())
		"habit":
			if sv.last_sub != "" and sv.last_sub == ctx.sub_id:
				_mult(ctx, inst, minf(6.0, 2.0 * (_cnt("habit") + 1)))
		"cycle":
			if int(sv.subs_played.get(ctx.sub_id, 0)) == 1:
				_mult(ctx, inst, 2.0)
		"variety_pack":
			if sv.subs_played.size() >= 3:
				_xmult(ctx, inst, 2.0)
		"overclocked_firmware":
			var lv := 0
			for k in RunState.sub_levels:
				lv += int(RunState.sub_levels[k])
			_mult(ctx, inst, minf(6.0, 0.5 * lv))
		# ---- Executables ----
		"power_user":
			if int(stats.get("exe_used", 0)) > 0:
				_mult(ctx, inst, 3.0)
		"stockpile":
			var held := 0
			for c in RunState.consumables:
				if c.kind == Enums.ItemKind.EXECUTABLE:
					held += 1
			_chips(ctx, inst, 5.0 * held)
		# ---- Stash ----
		"pocket_space":
			if ctx.stash_after.any(func(n): return n.type == Enums.NodeType.ICE):
				_mult(ctx, inst, 2.0)
		"time_capsule":
			var held_turns := 0
			for n in ctx.stash_after:
				held_turns += n.stash_turns + 1
			_chips(ctx, inst, 3.0 * held_turns)
		"mirror_cache":
			var types := {}
			for n in nodes:
				types[n.type] = true
			if ctx.stash_after.any(func(n): return types.has(n.type)):
				_chips(ctx, inst, 10.0)
		"shell_game":
			if ctx.stash_after.any(func(n): return n.stash_turns >= 1):
				_xmult(ctx, inst, 2.0)
		"lockbox":
			if RunState.get_stash_capacity() >= 2:
				_mult(ctx, inst, 4.0)
		# ---- Integrity ----
		"steady_hand":
			_chips(ctx, inst, 2.0 * hp)
		"scar_tissue":
			_mult(ctx, inst, s.n)
		"overheal":
			_chips(ctx, inst, 5.0 * int(stats.get("overheal", 0)))
		"redline":
			if hp <= 4 and hp >= 1:
				_xmult(ctx, inst, minf(4.0, pow(1.5, 5 - hp)))
		# ---- Eject / tempo ----
		"escape_hatch":
			if sv.last_action_flee:
				_chips(ctx, inst, 10.0)
		"panic_button":
			_mult(ctx, inst, minf(4.0, float(_cnt("ejects"))))
		"tempo":
			if not sv.fled_this_turn:
				_xmult(ctx, inst, 1.0 + 0.25 * (_cnt("tempo") + 1))
		# ---- Face-down ----
		"blind_trust":
			if fd > 0:
				_mult(ctx, inst, 3.0)
		"hunch":
			if nodes.size() >= 3 and fd >= nodes.size():
				_xmult(ctx, inst, 2.0)
		# ---- Legendary ----
		"perfect_mirror":
			if pb > 0:
				_xmult(ctx, inst, minf(2.0, pow(1.25, pb)))
		"hollow_crown":
			if deck_n <= 20:
				_xmult(ctx, inst, 3.0)
		"overdrive":
			_xmult(ctx, inst, 2.5)
		"last_stand_protocol":
			if hp <= 3 and left <= 6:
				_xmult(ctx, inst, 4.0)
		"ledger_of_souls":
			_chips(ctx, inst, 3.0 * minf(12.0, s.n))
		"compound_interest":
			_mult(ctx, inst, s.n)


## Understudy: runs the Daemon to its left on a scratch context and keeps only its Base Bytes.
static func _understudy(inst: Dictionary, ctx: Dictionary, node: NodeData) -> void:
	var i := _idx(inst)
	if i <= 0:
		return
	var left: Dictionary = RunState.daemons[i - 1]
	if left.id in ["understudy", "rust", "blueprint"]:
		return
	var t := ctx.duplicate()
	t.chips = 0.0
	t.mult = 1.0
	t.bonus_sum = 0.0
	t.breakdown = []
	t.trig = {}
	t.flat = {}
	if node == null:
		score(left, t)
	else:
		score_node(left, node, t)
	if t.chips > 0.0:
		_chips(ctx, inst, t.chips)


## Daemons that must see what every other Daemon did this turn.
static func score_late(inst: Dictionary, ctx: Dictionary) -> void:
	match inst.id:
		"conductor":
			var n := 0
			for uid in ctx.trig:
				if uid != inst.uid:
					n += 1
			_mult(ctx, inst, minf(5.0, float(n)))
		"hall_of_mirrors":
			var sum := 0.0
			for uid in ctx.flat:
				if uid != inst.uid:
					sum += float(ctx.flat[uid])
			_mult(ctx, inst, float(floori(sum / 2.0)))


## Daemons that react to each individual resolved Node. Called right after the
## Node's own value is added, so the cascade can show them triggering one by one.
static func score_node(inst: Dictionary, node: NodeData, ctx: Dictionary) -> void:
	var v: int = node.eff_value
	match inst.id:
		"floppy_disk":
			_chips(ctx, inst, 4.0)
		"binary_zero":
			if v % 2 == 0:
				_chips(ctx, inst, 10.0)
		"binary_one":
			if v % 2 == 1:
				_chips(ctx, inst, 10.0)
		"low_level_format":
			if v >= 2 and v <= 5:
				_chips(ctx, inst, 8.0)
		"mainframe_access":
			if v >= 11 and v <= 14:
				_chips(ctx, inst, 6.0)
		"prime_directive":
			if PRIMES.has(v):
				_chips(ctx, inst, 8.0)
		"fibonacci":
			if FIBS.has(v):
				_chips(ctx, inst, 10.0)
		"syringe":
			if node.type == Enums.NodeType.COOLANT:
				_chips(ctx, inst, 10.0)
		"neon_sign":
			if node.is_modified():
				_mult(ctx, inst, 2.0)
		"redundant_array":
			for st in ctx.stash_after:
				if st.type == node.type and st.eff_value == v:
					_chips(ctx, inst, 10.0)
					break
		"chrome_plating":
			if node.is_modified():
				_chips(ctx, inst, 8.0)
		"gamblers_eye":
			if node.type == Enums.NodeType.ICE and (ctx.stats.get("raw_glitches", []) as Array).has(node.uid):
				_chips(ctx, inst, 12.0)
				if (ctx.stats.get("face_down_uids", []) as Array).has(node.uid):
					_chips(ctx, inst, 12.0)
		"hard_line":
			if RunState.server != null and RunState.server.weapon != null:
				_chips(ctx, inst, 6.0)
		"understudy":
			_understudy(inst, ctx, node)


# ------------------------------------------------------------------- events
## Fires an event on every Daemon. Returns UI "pop" events.
static func fire(ev: String, p: Dictionary = {}) -> Array:
	var pops: Array = []
	# Iterate a snapshot: a Daemon may remove itself mid-event (Buffer Overflow).
	var snap: Array = RunState.daemons.duplicate()
	for i in snap.size():
		if is_disabled(i) or not RunState.daemons.has(snap[i]):
			continue
		_on_event(snap[i], ev, p, pops, false)
	for d in effective_list():
		if d.get("copy", false):
			_on_event(d, ev, p, pops, true)
	return pops


const MINING_CAP := 6


## Mining Rig income is capped per Server. Pays out and returns the amount.
static func _mining_pay(want: int) -> int:
	var paid := mini(want, MINING_CAP - _cnt("mining"))
	if paid <= 0:
		return 0
	RunState.server.counters["mining"] = _cnt("mining") + paid
	RunState.money += paid
	return paid


const SINGULARITY_FEE := 10


## Singularity: a one-off fee at the start of each Server. Unpaid = no multiplier.
static func _singularity_charge(d: Dictionary, pops: Array) -> void:
	var s: Dictionary = d.s
	var key := "paid_%d" % int(d.uid)
	if RunState.money >= SINGULARITY_FEE:
		RunState.money -= SINGULARITY_FEE
		s[key] = true
		pops.append(_pop(d, "-Ø%d" % SINGULARITY_FEE, -SINGULARITY_FEE))
	else:
		s[key] = false
		pops.append(_pop(d, "CAN'T PAY: x1"))


static func _on_event_new(d: Dictionary, ev: String, p: Dictionary, pops: Array) -> void:
	var s: Dictionary = d.s
	match ev:
		"server_start":
			match d.id:
				"loose_change":
					RunState.money += 1
					pops.append(_pop(d, "+Ø1", 1))
				"triage":
					var healed := RunState.heal(2)
					if healed > 0:
						pops.append(_pop(d, "+%d INT" % healed))
				"scar_tissue":
					s.n = 0.0
		"equip":
			if d.id == "weld":
				var healed := RunState.heal(1)
				if healed > 0:
					pops.append(_pop(d, "+1 INT"))
		"flee":
			if d.id == "clean_exit":
				var healed := RunState.heal(1)
				if healed > 0:
					pops.append(_pop(d, "+1 INT"))
			elif d.id == "peek":
				pops.append(_pop(d, "RETURNED"))
		"damage":
			match d.id:
				"scar_tissue":
					s.n = minf(4.0, s.n + 1.0)
					pops.append(_pop(d, "+1 OC"))
				"streak_counter":
					if s.n > 0.0:
						s.n = 0.0
						pops.append(_pop(d, "STREAK LOST"))
		"pain_tolerance_pop":
			if d.id == "pain_tolerance":
				pops.append(_pop(d, "IGNORED"))
		"node_resolved":
			var node: NodeData = p.node
			match d.id:
				"tip_jar":
					if node.type == Enums.NodeType.COOLANT and _cnt("tip_jar") < 3:
						_bump("tip_jar")
						RunState.money += 1
						pops.append(_pop(d, "+Ø1", 1))
				"burn_in":
					var sid := RunState.server.get_instance_id() if RunState.server != null else 0
					if node.is_modified() and node.type != Enums.NodeType.ICE and node.base_value < 14 and node.burn_mark != sid:
						node.burn_mark = sid
						node.base_value += 1
						node.eff_value = mini(14, node.eff_value + 1)
						pops.append(_pop(d, "+1 value"))
		"perfect_block":
			match d.id:
				"bounce_back":
					if _cnt("bounce_back") < 3:
						_bump("bounce_back")
						RunState.money += 1
						pops.append(_pop(d, "+Ø1", 1))
				"hardened_core":
					var w: WeaponState = p.weapon
					if w.hardened < 3 and w.ceiling < 90:
						w.hardened += 1
						w.ceiling += 1
						pops.append(_pop(d, "+1 CEIL"))
				"reactive_patch":
					var healed := RunState.heal(1)
					if healed > 0:
						pops.append(_pop(d, "+1 INT"))
				"streak_counter":
					var sv: ServerState = RunState.server
					if int(s.get("turn", -1)) != sv.turn_number:
						s["turn"] = sv.turn_number
						s.n = minf(6.0, s.n + 1.0)
						pops.append(_pop(d, "STREAK %d" % int(s.n)))
				"iron_ledger":
					if s.n < 20.0:
						s.n += 1.0
						pops.append(_pop(d, "+2 Base"))
		"weapon_break":
			if d.id == "salvage":
				RunState.money += 2
				pops.append(_pop(d, "+Ø2", 2))
		"node_deleted":
			if d.id == "ledger_of_souls" and s.n < 12.0:
				s.n += 1.0
				pops.append(_pop(d, "+3 Base"))
		"bypass":
			if d.id == "dead_letter" and p.node.type == Enums.NodeType.ICE and not RunState.is_boss("lock") and _cnt("dead_letter") < 2:
				_bump("dead_letter")
				RunState.money += 1
				pops.append(_pop(d, "+Ø1", 1))


static func _on_event(d: Dictionary, ev: String, p: Dictionary, pops: Array, is_copy: bool) -> void:
	var s: Dictionary = d.s
	var sv: ServerState = RunState.server
	# Copies (Blueprint) only duplicate "income" style triggers, never state growth.
	if is_copy:
		match [d.id, ev]:
			["mining_rig", "turn_end"]:
				var paid := _mining_pay(int(p.get("data_count", 0)))
				if paid > 0:
					pops.append(_pop(d, "+Ø%d" % paid, paid))
			["bounty_hunter", "ice_destroyed"]:
				if p.node.eff_value >= 12:
					RunState.money += 1
					pops.append(_pop(d, "+Ø1", 1))
			["singularity", "server_start"]:
				_singularity_charge(d, pops)
		return
	_on_event_new(d, ev, p, pops)
	match ev:
		"server_start":
			match d.id:
				"rust":
					s.n = 5.0
				"singularity":
					_singularity_charge(d, pops)
		"flee":
			if d.id == "trojan":
				s.n += 0.5
				pops.append(_pop(d, "+0.5"))
		"damage":
			if d.id == "masochist" and int(p.amount) >= 4:
				s.n += 1.0
				pops.append(_pop(d, "+1 OC"))
		"node_resolved":
			if d.id == "spyware" and p.node.eff_value == 14:
				s.n += 1.0
				pops.append(_pop(d, "+x0.1"))
		"ice_destroyed":
			if d.id == "bounty_hunter" and p.node.eff_value >= 12:
				RunState.money += 1
				pops.append(_pop(d, "+Ø1", 1))
		"node_deleted":
			if d.id == "overwritten_file":
				s.n += 1.0
				pops.append(_pop(d, "+2 Base"))
		"bypass":
			var node: NodeData = p.node
			if d.id == "smuggler":
				node.base_value += 1
				node.eff_value += 1
				pops.append(_pop(d, "+1 value"))
			elif d.id == "glitch" and node.type == Enums.NodeType.DATA and _cnt("ghost_write") < 2:
				_bump("ghost_write")
				var ghost := NodeData.new(Enums.NodeType.DATA, node.eff_value + 4)
				ghost.temporary = true
				ghost.eff_value = ghost.base_value
				RunState.deck.put_top(ghost)
				pops.append(_pop(d, "GHOST %d" % ghost.base_value))
		"weapon_break":
			if d.id == "recycled_code":
				var healed := RunState.heal(5)
				pops.append(_pop(d, "+%d INT" % healed))
		"turn_end":
			match d.id:
				"mining_rig":
					var n := _mining_pay(int(p.get("data_count", 0)))
					if n > 0:
						pops.append(_pop(d, "+Ø%d" % n, n))
				"crypto_miner":
					d.sell_bonus += 1
					pops.append(_pop(d, "+Ø1 sell"))
				"blood_magic":
					if RunState.lose_health(1):
						p["died"] = true
					pops.append(_pop(d, "-1 INT"))
				"obelisk":
					if p.sub != p.most_used:
						s.n += 1.0
					else:
						s.n = 0.0
		"shop_enter":
			if d.id == "adware" and RunState.has_consumable_space():
				var ids: Array = ItemDB.EXECUTABLES.keys()
				RunState.add_consumable(Enums.ItemKind.EXECUTABLE, ids.pick_random())
				pops.append(_pop(d, "FREE EXE"))
