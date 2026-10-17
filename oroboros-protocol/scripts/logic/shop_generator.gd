class_name ShopGenerator
extends RefCounted
## Builds the Black Market stock. Listing: {kind, id, base_cost, sold}.

const RARITY_WEIGHTS := [52, 28, 13, 5, 2]
const DAEMON_SLOTS := 2


static func generate(keep_voucher: Dictionary = {}) -> Array:
	var out: Array = []
	var taken: Array = []
	for i in DAEMON_SLOTS:
		var id := _roll_daemon(taken)
		if id != "":
			taken.append(id)
			out.append(_listing(Enums.ItemKind.DAEMON, id))
	var item_slots := 2 + (1 if RunState.has_voucher("backdoor") else 0)
	for i in item_slots:
		out.append(_roll_item())
	if not keep_voucher.is_empty():
		out.append(keep_voucher)
	else:
		var v := _roll_voucher()
		if not v.is_empty():
			out.append(v)
	return out


static func reroll(current: Array) -> Array:
	var voucher: Dictionary = {}
	for l in current:
		if l.kind == Enums.ItemKind.ROOT_ACCESS and not l.sold:
			voucher = l
	return generate(voucher)


static func _listing(kind: int, id: String) -> Dictionary:
	return {"kind": kind, "id": id, "base_cost": int(ItemDB.get_item(kind, id).cost), "sold": false}


static func cost_of(listing: Dictionary) -> int:
	return RunState.price(int(listing.base_cost), int(listing.kind))


static func _roll_daemon(exclude: Array) -> String:
	var rarity := _weighted(RARITY_WEIGHTS)
	for attempt in 4:
		var pool: Array = DaemonDB.ids_with_rarity(rarity, rarity).filter(
			func(i): return not RunState.has_daemon(i) and not exclude.has(i))
		if not pool.is_empty():
			return pool.pick_random()
		rarity = maxi(0, rarity - 1)
	var any: Array = DaemonDB.all_ids().filter(func(i): return not RunState.has_daemon(i) and not exclude.has(i))
	return any.pick_random() if not any.is_empty() else ""


static func _roll_item() -> Dictionary:
	var r := randi() % 100
	if r < 45:
		return _listing(Enums.ItemKind.EXECUTABLE, ItemDB.EXECUTABLES.keys().pick_random())
	if r < 75:
		return _listing(Enums.ItemKind.FIRMWARE, SubroutineDB.ORDER.pick_random())
	return _listing(Enums.ItemKind.CORRUPTION, ItemDB.CORRUPTIONS.keys().pick_random())


## The Root Access offer is fixed for a whole Network (every shop visit and reroll)
## and re-rolled when a new Network begins, so the player can plan around it.
static func _roll_voucher() -> Dictionary:
	if RunState.network_voucher_network != RunState.network or RunState.network_voucher_id == "":
		var pool: Array = ItemDB.ROOT_ACCESS.keys().filter(func(i): return not RunState.has_voucher(i))
		RunState.network_voucher_network = RunState.network
		RunState.network_voucher_id = pool.pick_random() if not pool.is_empty() else "-"
	var id: String = RunState.network_voucher_id
	if id == "-" or RunState.has_voucher(id):
		return {}
	return _listing(Enums.ItemKind.ROOT_ACCESS, id)


static func _weighted(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += int(w)
	var roll := randi() % total
	for i in weights.size():
		roll -= int(weights[i])
		if roll < 0:
			return i
	return 0
