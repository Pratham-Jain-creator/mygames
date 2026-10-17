extends Node
## Autoload: owns all persistent data of the current run (the "Rig").
## Per-server data lives in `server` (ServerState).

const BASE_MAX_HEALTH := 10
const START_MONEY := 4
const MAX_DAEMONS := 5
const MAX_CONSUMABLES := 3
const TURNS_PER_SERVER := 4
const BASE_FLEES := 2
const RESOLVE_COUNT := 3
const MIN_DECK_SIZE := 12
const FINAL_NETWORK := 8

var active := false
var tutorial := false             # guided tutorial run (fixed deck order, scripted bot)
var deck: Deck = Deck.new()
var money := 0:
	set(v):
		money = maxi(0, v)
		EventBus.money_changed.emit(money)
var health := 10:
	set(v):
		var old := health
		health = mini(v, get_max_health())
		EventBus.health_changed.emit(old, health, get_max_health())
var perm_health_bonus := 0
var daemons: Array = []          # Array[Dictionary]: {id, uid, sell_bonus, s}
var consumables: Array = []      # Array[Dictionary]: {kind, id}
var vouchers: Array = []         # Array[String]
var sub_levels: Dictionary = {}
var sub_play_counts: Dictionary = {}
var network := 1
var server_index := 0
var boss_order: Array = []
var boss_seen: Array = []        # endless: Sentinels shown in the current cycle
var server: ServerState = null
var shop_listings: Array = []
var network_voucher_network := 0   # Network the fixed Root Access offer belongs to
var network_voucher_id := ""
var shop_rerolls := 0
var shop_free_reroll_used := false
var shop_first_purge_used := false   # Coupon Book / Pruning Shears: first Purge per visit
var shop_hotfix_used := false        # Hotfix: first Firmware Update per visit
var purge_count := 0
var stats: Dictionary = {}
var result := ""                 # "win" | "lose" | ""
var result_reason := ""
var death_report := {}           # snapshot for the game-over screen
var _next_daemon_uid := 1


# ---------------------------------------------------------------- run flow
func start_new_run(tutorial_mode := false) -> void:
	tutorial = tutorial_mode
	deck = Deck.new()
	deck.build_standard()
	daemons.clear()
	consumables.clear()
	vouchers.clear()
	sub_levels.clear()
	sub_play_counts.clear()
	perm_health_bonus = 0
	network = 1
	server_index = 0
	boss_order = BossDB.build_order()
	boss_seen = boss_order.duplicate()
	server = null
	shop_listings = []
	network_voucher_network = 0
	network_voucher_id = ""
	purge_count = 0
	result = ""
	result_reason = ""
	stats = {"servers_cleared": 0, "best_turn": 0, "damage_taken": 0, "daemons_bought": 0}
	active = true
	money = START_MONEY + (0 if tutorial_mode else MetaSave.consume_start_bonus())
	health = get_max_health()
	if tutorial_mode:
		add_daemon("floppy_disk")


func advance_server() -> bool:
	## Moves to the next server. Returns true when the whole run is complete.
	stats["servers_cleared"] += 1
	server_index += 1
	if server_index >= 3:
		server_index = 0
		network += 1
	return network > FINAL_NETWORK


func end_run(won: bool, reason: String) -> void:
	result = "win" if won else "lose"
	result_reason = reason
	death_report = {}
	if not won and server != null:
		death_report = {
			"network": network, "kind": server.kind, "boss": server.boss_id,
			"score": server.score, "quota": server.quota, "turns": server.turn_number - 1,
			"flees_left": server.flees_left, "hit": server.last_hit.duplicate(),
			"health_max": get_max_health(), "exhausted": reason.begins_with("TAILBYTES"),
		}
	active = false
	if has_daemon("seed_capital"):
		MetaSave.set_value("run", "start_bonus", 10)
	MetaSave.record_run(mini(network, FINAL_NETWORK), won)


# ----------------------------------------------------------------- health
## Hierarchy: every additive modifier is summed first, then Glass Cannon applies as a
## hard clamp that overrides all of them (Failsafe, Cooling System...).
func get_max_health() -> int:
	var m := BASE_MAX_HEALTH + perm_health_bonus
	if has_voucher("cooling_system"):
		m += 5
	if has_daemon("failsafe"):
		m += 5
	if has_daemon("thick_skin"):
		m += 2
	if has_daemon("ironclad"):
		m -= 3
	if has_daemon("glass_cannon"):
		m = mini(m, 5)
	return maxi(m, 1)


func refresh_health() -> void:
	health = health  # re-runs the setter to clamp against the new maximum


## Returns true if the Rig died. Handles Buffer Overflow.
func lose_health(amount: int) -> bool:
	health -= amount
	if health <= 0:
		var bo := find_daemon("buffer_overflow")
		if not bo.is_empty():
			remove_daemon(bo)
			health = 1
			EventBus.toast_requested.emit("BUFFER OVERFLOW: Server held at 1 INT", Enums.COL_DAEMON)
			return false
		return true
	return false


func heal(amount: int) -> int:
	if is_boss("reaper"):
		return 0
	var before := health
	var cap := get_max_health()
	health += amount
	# Overheal: whatever would have been healed above Max is remembered for scoring.
	if server != null and not server.turn_stats.is_empty():
		var over := maxi(0, before + amount - cap)
		if over > 0:
			server.turn_stats["overheal"] = int(server.turn_stats.get("overheal", 0)) + over
	return health - before


# --------------------------------------------------------- derived limits
func get_stash_capacity() -> int:
	if has_daemon("bloatware"):
		return 0
	return 1 + (1 if has_voucher("ram_expansion") else 0)


func get_room_size() -> int:
	return RESOLVE_COUNT + get_stash_capacity()


func get_flee_limit() -> int:
	return BASE_FLEES + (1 if has_daemon("packet_sniffer") else 0)


func is_boss(id: String) -> bool:
	return server != null and server.boss_id == id


## The Sentinel of a Network. Past the last Network (endless) new ones are drawn at random
## from the whole pool without repeating until every Sentinel has appeared.
func boss_for(net: int) -> String:
	if boss_order.is_empty():
		boss_order = BossDB.build_order()
		boss_seen = boss_order.duplicate()
	while boss_order.size() < net:
		if boss_seen.size() >= BossDB.BOSSES.size():
			boss_seen = [boss_order[boss_order.size() - 1]]
		var id := BossDB.next_endless(boss_seen)
		boss_seen.append(id)
		boss_order.append(id)
	return boss_order[net - 1]


## How much of a Patch's value is restored under the current Sentinel (1.0 = all).
func patch_factor() -> float:
	if server == null:
		return 1.0
	if server.boss_id == "leech" or server.boss_id == "reaper":
		return 0.0
	if server.boss_id == "drought" or server.boss_id == "hemorrhage":
		return 0.5
	return 1.0


# ---------------------------------------------------------------- daemons
func has_daemon(id: String) -> bool:
	for d in daemons:
		if d.id == id:
			return true
	return false


func find_daemon(id: String) -> Dictionary:
	for d in daemons:
		if d.id == id:
			return d
	return {}


## Pain Tolerance: hits up to this size are ignored (1, +1 per boss defeated, max 3).
func pain_tolerance_limit() -> int:
	if not has_daemon("pain_tolerance"):
		return 0
	return clampi(network, 1, 3)


func get_max_daemons() -> int:
	return MAX_DAEMONS - (1 if has_daemon("hall_of_mirrors") else 0)


func can_add_daemon() -> bool:
	return daemons.size() < get_max_daemons()


func add_daemon(id: String) -> Dictionary:
	var inst := {"id": id, "uid": _next_daemon_uid, "sell_bonus": 0, "s": {"n": 0.0}}
	_next_daemon_uid += 1
	daemons.append(inst)
	refresh_health()
	EventBus.daemons_changed.emit()
	return inst


func remove_daemon(inst: Dictionary) -> void:
	daemons.erase(inst)
	refresh_health()
	EventBus.daemons_changed.emit()


## Drag-and-drop reordering: Daemons score left to right, so order matters.
func move_daemon(from: int, to: int) -> bool:
	to = clampi(to, 0, daemons.size() - 1)
	if from < 0 or from >= daemons.size() or from == to:
		return false
	var d: Dictionary = daemons[from]
	daemons.remove_at(from)
	daemons.insert(to, d)
	EventBus.daemons_changed.emit()
	return true


func sell_value(inst: Dictionary) -> int:
	var cost: int = DaemonDB.get_def(inst.id).cost
	return maxi(1, cost / 2) + int(inst.sell_bonus) + (2 if has_daemon("pawn_shop") else 0)


## Selling a Daemon in the middle of a Server run pays half of the Black Market price.
func field_sell_value(inst: Dictionary) -> int:
	return maxi(1, sell_value(inst) / 2)


func sell_daemon_in_run(inst: Dictionary) -> int:
	var v := field_sell_value(inst)
	remove_daemon(inst)
	money += v
	return v


func sell_daemon(inst: Dictionary) -> int:
	var v := sell_value(inst)
	remove_daemon(inst)
	money += v
	return v


# ------------------------------------------------------------ consumables
func get_max_consumables() -> int:
	if has_daemon("double_dose"):
		return 1
	return MAX_CONSUMABLES + (1 if has_daemon("spare_slot") else 0)


func has_consumable_space() -> bool:
	return consumables.size() < get_max_consumables()


func add_consumable(kind: int, id: String) -> bool:
	if not has_consumable_space():
		return false
	consumables.append({"kind": kind, "id": id})
	EventBus.consumables_changed.emit()
	return true


func remove_consumable(item: Dictionary) -> void:
	consumables.erase(item)
	EventBus.consumables_changed.emit()


# ------------------------------------------------------------ deck / subs
func delete_node(node: NodeData) -> bool:
	if deck.size() <= MIN_DECK_SIZE:
		return false
	deck.remove_node(node)
	DaemonLogic.fire("node_deleted", {"node": node})
	EventBus.deck_changed.emit()
	return true


func level_up_sub(id: String, times := 1) -> void:
	sub_levels[id] = int(sub_levels.get(id, 0)) + times


# ---------------------------------------------------------------- vouchers
func has_voucher(id: String) -> bool:
	return vouchers.has(id)


func add_voucher(id: String) -> void:
	vouchers.append(id)
	if id == "cooling_system":
		health += 5
	refresh_health()


# ---------------------------------------------------------------- economy
func price(base: int, kind: int) -> int:
	var p := float(base)
	if kind == Enums.ItemKind.FIRMWARE and has_daemon("firmware_discount"):
		p = maxf(1.0, p - 2.0)
	if kind == Enums.ItemKind.EXECUTABLE and has_daemon("hot_patch"):
		p = maxf(1.0, p - 2.0)
	if kind == Enums.ItemKind.FIRMWARE and has_daemon("scalper"):
		p *= 2.0
	if kind == Enums.ItemKind.DAEMON and has_daemon("black_market"):
		p *= 0.5
	if has_daemon("vip_pass"):
		p *= 0.75
	return maxi(1, ceili(p))


func reroll_cost() -> int:
	if has_daemon("spoofed_ip") and not shop_free_reroll_used:
		return 0
	var c := 5 + shop_rerolls
	if has_voucher("admin_privileges"):
		c = ceili(c / 2.0)
	if has_daemon("haggler"):
		c = maxi(1, c - 1)
	return c


func purge_cost() -> int:
	var c := 3 if has_daemon("delete_key") else 3 + purge_count
	if has_daemon("ledger_of_souls"):
		c *= 2
	if not shop_first_purge_used:
		if has_daemon("pruning_shears"):
			return 0
		if has_daemon("coupon_book"):
			c = maxi(0, c - 1)
	return c


## Shop visit bookkeeping (first-Purge / Hotfix flags, Layaway payout).
func begin_shop_visit() -> void:
	shop_first_purge_used = false
	shop_hotfix_used = false


func on_purged() -> void:
	shop_first_purge_used = true


func leave_shop() -> int:
	var bonus := 0
	if has_daemon("layaway"):
		bonus = mini(4, money / 4)
		money += bonus
	return bonus
