extends Node
## Balance probe. Reads tools/probe/power_cfg.txt (one word) and runs one experiment:
##   boss   - win rate of a heuristic player against each Sentinel (+ Cipher information variants)
##   daemon - paired strength of every single Daemon against the same seeded Servers
##   climb  - hill-climb for the strongest 5-Daemon build, and check for NaN / INF / overflow
## Results go to tools/probe/power_<experiment>.log

var _lines: Array = []
var _out := ""
var _last_dmg := 0.0
var _dmg_weight := 28.0
var _eject_at := 99.0


func _log(msg: String) -> void:
	_lines.append(msg)
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))


# ------------------------------------------------------------------ player AI
## mode 0 = sees every value, 1 = sees types and estimates values from the Tailbytes, 2 = totally blind
func _est(n: NodeData, mode: int, unseen: Array) -> float:
	if not n.face_down or mode == 0:
		return float(n.eff_value)
	var tot := 0.0
	var cnt := 0
	for u: NodeData in unseen:
		if u.type == n.type:
			tot += float(u.base_value)
			cnt += 1
	return tot / cnt if cnt > 0 else 8.0


func _rate(sel: Array, mode: int, unseen: Array) -> float:
	var sv: ServerState = RunState.server
	var hp := float(RunState.health)
	var maxhp := float(RunState.get_max_health())
	var ceiling := 99.0
	var strength := 0.0
	var have_w := sv.weapon != null and sv.weapon_enabled
	if have_w:
		ceiling = float(sv.weapon.ceiling)
		strength = float(sv.weapon.strength)
	var order: Array = []
	for t in [Enums.NodeType.BREACH, Enums.NodeType.ICE, Enums.NodeType.COOLANT, Enums.NodeType.DATA]:
		var grp: Array = sel.filter(func(x): return x.type == t)
		if t == Enums.NodeType.ICE:
			grp.sort_custom(func(a, b): return _est(a, mode, unseen) < _est(b, mode, unseen))
		order.append_array(grp)
	var dmg_total := 0.0
	var chips := 0.0
	var worst := 0.0
	for n: NodeData in order:
		var v := _est(n, mode, unseen)
		match n.type:
			Enums.NodeType.BREACH:
				strength = v
				ceiling = 99.0
				have_w = true
			Enums.NodeType.ICE:
				var d := v
				if have_w and v <= ceiling:
					d = maxf(0.0, v - strength)
					ceiling = v - 1.0
				dmg_total += d
				hp -= d
				worst = minf(worst, hp)
			Enums.NodeType.COOLANT:
				hp = minf(maxhp, hp + v)
			Enums.NodeType.DATA:
				chips += v * 2.0
	var sub: String = SubroutineDB.identify(order)
	var lvl := int(RunState.sub_levels.get(sub, 0))
	var base := float(SubroutineDB.base_for(sub, lvl)) + chips
	var val := base * (1.0 + float(sv.bandwidth_bonus) + float(SubroutineDB.mult_for(sub, lvl)))
	_last_dmg = dmg_total
	var penalty := dmg_total * (_dmg_weight * 2.0 if hp < 5.0 else _dmg_weight)
	if worst + float(RunState.health) <= 0.0 or hp <= 0.0:
		penalty += 1.0e6
	return val - penalty


func _combos(room: Array, k: int) -> Array:
	var out: Array = []
	var n := room.size()
	if k == 3:
		for a in n:
			for b in range(a + 1, n):
				for c in range(b + 1, n):
					out.append([room[a], room[b], room[c]])
	return out


func _unseen(sv: ServerState) -> Array:
	var u: Array = RunState.deck.draw_pile.duplicate()
	for n: NodeData in sv.room:
		if n.face_down:
			u.append(n)
	return u


## Plays one Server exactly like the game: no turn limit, it ends when the Threshold is met,
## you die, or the Tailbytes run out. Returns {score, quota, died, best_turn, turns, won}.
func _play_server(mode: int, stop_on_win: bool) -> Dictionary:
	var sv: ServerState = ServerLogic.begin_server()
	var guard := 0
	var died := false
	var turns := 0
	while guard < 60:
		guard += 1
		if RunState.deck.draw_pile.size() + sv.stash.size() < 3:
			break
		var d: Dictionary = ServerLogic.deal_room()
		var room: Array = d.room.duplicate()
		if room.size() < 3:
			break
		var best: Array = []
		var best_v := -INF
		var un := _unseen(sv)
		if mode == 2:
			room.shuffle()
			best = room.slice(0, 3)
			best_v = _rate(best, 0, un)
		else:
			for c in _combos(room, 3):
				var v := _rate(c, mode, un)
				if v > best_v:
					best_v = v
					best = c
		_rate(best, 0 if mode == 2 else mode, un)
		if (best_v < -5.0e5 or _last_dmg >= _eject_at) and ServerLogic.can_flee() == "":
			var fr: Dictionary = ServerLogic.flee()
			if fr.died:
				died = true
				break
			continue
		var rest: Array = room.filter(func(x): return not best.has(x))
		var res: Dictionary = TurnResolver.resolve(best, rest)
		turns += 1
		if res.died or RunState.health <= 0:
			died = true
			break
		if stop_on_win and sv.score >= sv.quota:
			break
	return {"score": sv.score, "quota": sv.quota, "died": died, "best_turn": sv.best_turn, "turns": turns, "won": (not died) and sv.score >= sv.quota}


func _setup(seed_i: int, net: int, kind: int, boss: String, daemons: Array, lvl: int) -> void:
	seed(seed_i)
	RunState.start_new_run()
	RunState.network = net
	RunState.server_index = kind
	RunState.boss_order = []
	for i in 40:
		RunState.boss_order.append(boss)
	RunState.boss_seen = []
	for sid in SubroutineDB.ORDER:
		RunState.sub_levels[sid] = lvl
	RunState.money = 30
	for id in daemons:
		RunState.add_daemon(id)
	RunState.health = RunState.get_max_health()


# ------------------------------------------------------------------ experiments
func _random_build(rng: RandomNumberGenerator, n: int) -> Array:
	var ids := DaemonDB.all_ids()
	var out: Array = []
	while out.size() < n:
		var id: String = ids[rng.randi() % ids.size()]
		if not out.has(id):
			out.append(id)
	return out


func _top_builds(rng: RandomNumberGenerator, net: int, lvl: int, pool_n: int, keep: int) -> Array:
	var scored: Array = []
	for i in pool_n:
		var b: Array = _random_build(rng, 5)
		var tot := 0.0
		for t in 4:
			_setup(300 + t, net, 2, "none", b, lvl)
			var r: Dictionary = _play_server(0, false)
			tot += float(r.score)
		scored.append([tot, b])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for k in keep:
		out.append(scored[k][1])
	return out


func _exp_boss() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for tier in [0, 1, 2]:
		var net: int = [2, 5, 8][tier]
		var lvl: int = [1, 3, 5][tier]
		var builds: Array = _top_builds(rng, net, lvl, 260, 8)
		_log("=== tier %s: Network %d Sentinel (quota %d), Firmware lvl %d, best 8 of 260 random 5-Daemon builds, 25 seeds each" % [BossDB.TIER_NAMES[tier], net, Progression.quota_for(net, 2), lvl])
		var list: Array = ["none"]
		list.append_array(BossDB.ids_in_tier(tier))
		var base_ratio := 1.0
		for bid in list:
			var wins := 0
			var deaths := 0
			var ratio := 0.0
			var n := 0
			for b in builds:
				for t in 25:
					_setup(1000 + t, net, 2, bid, b, lvl)
					var r: Dictionary = _play_server(0, true)
					if int(r.score) >= int(r.quota) and not r.died:
						wins += 1
					if r.died:
						deaths += 1
					ratio += float(r.score) / float(r.quota)
					n += 1
			if bid == "none":
				base_ratio = ratio / n
			_log("%-11s win %3d%%  death %3d%%  score/quota %.2f  (%.0f%% of no-boss)" % [bid, 100 * wins / n, 100 * deaths / n, ratio / n, 100.0 * (ratio / n) / maxf(0.0001, base_ratio)])
	_log("=== Cipher information test (Network 5, same kind of builds)")
	var cb: Array = _top_builds(rng, 5, 3, 200, 8)
	for mode in [0, 1, 2]:
		var wins := 0
		var n := 0
		var ratio := 0.0
		for b in cb:
			for t in 25:
				_setup(5000 + t, 5, 2, "cipher", b, 3)
				var r: Dictionary = _play_server(mode, true)
				if int(r.score) >= int(r.quota) and not r.died:
					wins += 1
				ratio += float(r.score) / float(r.quota)
				n += 1
		_log("cipher mode %d (%s): win %d%%  score/quota %.2f" % [mode, ["sees every value", "sees types + tracks Tailbytes", "blind / random pick"][mode], 100 * wins / n, ratio / n])


func _exp_daemon() -> void:
	var trials := 14
	var base_total := 0.0
	var base_scores: Array = []
	for t in trials:
		_setup(2000 + t, 3, 1, "none", [], 2)
		var r: Dictionary = _play_server(0, false)
		base_scores.append(float(r.score))
		base_total += float(r.score)
	_log("baseline (no daemons) mean score %.0f   (quota of this Server %d)" % [base_total / trials, Progression.quota_for(3, 1)])
	var rows: Array = []
	for id in DaemonDB.all_ids():
		var tot := 0.0
		var deaths := 0
		for t in trials:
			_setup(2000 + t, 3, 1, "none", [id], 2)
			var r: Dictionary = _play_server(0, false)
			tot += float(r.score)
			if r.died:
				deaths += 1
		var def: Dictionary = DaemonDB.get_def(id)
		rows.append([tot / maxf(1.0, base_total), id, def.name, def.rarity, deaths])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		_log("x%.2f  %-22s %-24s %s  deaths %d" % [r[0], r[1], r[2], Enums.RARITY_NAMES[r[3]], r[4]])


func _eval_build(build: Array, net: int, trials: int, seed_base: int) -> Dictionary:
	var tot := 0.0
	var best_turn := 0.0
	var bad := 0
	var deaths := 0
	for t in trials:
		_setup(seed_base + t, net, 1, "none", build, 4)
		var r: Dictionary = _play_server(0, false)
		var s := float(r.score)
		if is_nan(s) or is_inf(s) or s < 0.0:
			bad += 1
		if r.died:
			deaths += 1
			s *= 0.25
		tot += s
		best_turn = maxf(best_turn, float(r.best_turn))
	return {"mean": tot / trials, "best_turn": best_turn, "bad": bad, "deaths": deaths}


func _exp_climb() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var net := 8
	_log("Hill climb at Network %d Mainframe (quota %d), Firmware lvl 4, 12 paired Servers per evaluation" % [net, Progression.quota_for(net, 1)])
	var all := DaemonDB.all_ids()
	var results: Array = []
	for restart in 10:
		var build: Array = _random_build(rng, 5)
		var cur: Dictionary = _eval_build(build, net, 12, 3000)
		for it in 70:
			var cand := build.duplicate()
			var m := rng.randi() % 4
			if m == 0:
				var a := rng.randi() % 5
				var b := rng.randi() % 5
				var tmp = cand[a]
				cand[a] = cand[b]
				cand[b] = tmp
			else:
				var id: String = all[rng.randi() % all.size()]
				if cand.has(id):
					continue
				cand[rng.randi() % 5] = id
			var ev: Dictionary = _eval_build(cand, net, 12, 3000)
			if float(ev.mean) > float(cur.mean):
				cur = ev
				build = cand
		var fin: Dictionary = _eval_build(build, net, 40, 9000)
		results.append([fin.mean, build, fin])
		_log("restart %d: mean %.0f  best turn %.0f  deaths %d/40  bad %d  %s" % [restart, fin.mean, fin.best_turn, fin.deaths, fin.bad, str(build)])
	results.sort_custom(func(a, b): return a[0] > b[0])
	_log("BEST: %s" % str(results[0][1]))
	_log("max safe turn score constant = %s" % str(TurnResolver.MAX_SCORE))


func _exp_theory() -> void:
	var builds: Array = [
		["overdrive", "steady_hand", "ransomware", "blueprint", "singularity"],
		["black_hole", "redline", "last_stand_protocol", "singularity", "ransomware"],
		["glass_cannon", "overdrive", "singularity", "ransomware", "the_core"],
		["blueprint", "singularity", "ransomware", "overdrive", "glass_cannon"],
		["floppy_disk", "hard_line", "clean_sweep", "iron_ledger", "deflector"],
		["tempo", "razor_deck", "zen_garden", "minimalist", "lean_build"],
		["hollow_crown", "razor_deck", "overdrive", "singularity", "lean_build"],
		["poltergeist", "hunch", "blind_trust", "gamblers_eye", "singularity"],
		["spyware", "trojan", "masochist", "panic_button", "overdrive"],
		["compound_interest", "overdrive", "singularity", "glass_cannon", "ransomware"],
	]
	_log("Hand-built 'theory' builds at Network 8 Mainframe, quota %d, Firmware lvl 4, 40 Servers each" % Progression.quota_for(8, 1))
	for b in builds:
		var ev: Dictionary = _eval_build(b, 8, 40, 7000)
		_log("mean %9.0f  best turn %10.0f  deaths %2d/40  bad %d  %s" % [ev.mean, ev.best_turn, ev.deaths, ev.bad, str(b)])


func _shop_bot() -> void:
	RunState.begin_shop_visit()
	RunState.shop_listings = ShopGenerator.generate()
	var lst: Array = RunState.shop_listings.duplicate()
	lst.sort_custom(func(a, b): return int(ItemDB.get_item(a.kind, a.id).get("rarity", -1)) > int(ItemDB.get_item(b.kind, b.id).get("rarity", -1)))
	for l in lst:
		if l.kind == Enums.ItemKind.DAEMON and RunState.can_add_daemon() and RunState.money >= ShopGenerator.cost_of(l):
			RunState.money -= ShopGenerator.cost_of(l)
			RunState.add_daemon(l.id)
			l.sold = true
	for l in lst:
		if l.kind == Enums.ItemKind.FIRMWARE and not l.sold and RunState.money >= ShopGenerator.cost_of(l) + 3:
			RunState.money -= ShopGenerator.cost_of(l)
			RunState.level_up_sub(l.id, 1)
			l.sold = true
	RunState.leave_shop()


## Whole runs with a simple shopping bot. Shows how far an average player gets.
func _exp_run() -> void:
	for mode in [0, 2]:
		_dmg_weight = 60.0 if mode == 0 else 28.0
		_eject_at = 4.0 if mode == 0 else 99.0
		var n_runs := 150
		var reach := {}
		var wins := 0
		var turns_by_net := {}
		var owned_rar := [0, 0, 0, 0, 0]
		var reasons := {}
		var ratio_sum := 0.0
		var nfail := 0
		for r in n_runs:
			seed(60000 + r)
			RunState.start_new_run()
			var fail_net := 99
			for net in range(1, 9):
				if fail_net != 99:
					break
				for k in 3:
					RunState.network = net
					RunState.server_index = k
					var res: Dictionary = _play_server(mode, true)
					if not turns_by_net.has(net):
						turns_by_net[net] = []
					turns_by_net[net].append(int(res.turns))
					if not res.won:
						fail_net = net * 10 + k
						var why := "died" if res.died else "ran out of Tailbytes"
						reasons[why] = int(reasons.get(why, 0)) + 1
						ratio_sum += float(res.score) / float(res.quota)
						nfail += 1
						break
					ServerLogic.payout()
					_shop_bot()
			reach[fail_net] = int(reach.get(fail_net, 0)) + 1
			if fail_net == 99:
				wins += 1
			for dd in RunState.daemons:
				owned_rar[int(DaemonDB.get_def(dd.id).rarity)] += 1
		_log("=== run bot, %s, %d runs: full wins %d%%" % [["smart picks", "", "random picks"][mode], n_runs, 100 * wins / n_runs])
		var keys: Array = reach.keys()
		keys.sort()
		for key in keys:
			_log("  died/failed at %s: %d%%" % ["(none - won)" if key == 99 else "network %d server %d" % [key / 10, key % 10 + 1], 100 * int(reach[key]) / n_runs])
		for net in turns_by_net:
			var arr: Array = turns_by_net[net]
			var tot := 0
			for t in arr:
				tot += int(t)
			_log("  network %d: avg turns per Server played %.1f" % [net, float(tot) / arr.size()])
		_log("  failures: %s, avg score reached when failing = %.0f%% of the Threshold" % [str(reasons), 100.0 * ratio_sum / maxf(1.0, nfail)])
		_log("  daemons owned at the end (rarity C/U/R/E/L): %s" % str(owned_rar))


func _ready() -> void:
	var cfg := FileAccess.open("res://tools/probe/power_cfg.txt", FileAccess.READ)
	var which := cfg.get_as_text().strip_edges() if cfg else "boss"
	_out = "res://tools/probe/power_%s.log" % which
	_log("start " + which)
	match which:
		"boss":
			_exp_boss()
		"daemon":
			_exp_daemon()
		"climb":
			_exp_climb()
		"theory":
			_exp_theory()
		"run":
			_exp_run()
	_log("DONE")
	get_tree().quit()
