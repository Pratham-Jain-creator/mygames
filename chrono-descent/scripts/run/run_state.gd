extends Node
## Autoload "Run": the live state of the extraction loop.
##
## TWO kinds of belongings:
##   RUN (volatile)   ash, materials and blueprints you CARRY, the canteen's charges, grafts, buffs. Lost on death.
##   PROFILE (saved)  the stash (materials and ash banked by EXTRACTING), blueprints, armor sets, forged charms.
##                    Saved to user://profile.json.
## Extracting (the terminal in a floor's safe room, or just returning to the base alive) moves what you carry
## into the stash. Dying loses everything you carry, removes every graft and temporary charm, and FRACTURES the
## forged charms you wore until they are repaired at the workbench.
##
## Every bonus in the game (armor, charms, grafts, modules, buffs) is a stat dictionary; stat() adds them up.

signal changed
signal ash_changed(amount: int)
signal canteen_changed

const DEFAULT_SAVE_PATH: String = "user://profile.json"
const SLOT_COUNT: int = 3
const STARTING_ASH: int = 40

# ------------------------------------------------------------------ profile (saved)
var stash: Dictionary = {}
var stash_ash: int = STARTING_ASH
var blueprints: Dictionary = {}
var owned_armor: Array = [&"prisoner_rags"]
var armor: StringName = &"prisoner_rags"
## Owned forged charms: [{id, fractured}]. Entries are never removed, so an index stays valid.
var forged: Array = []
## Three slots. null, or {kind: "forged", ref: index in forged} / {kind: "graft"|"temp", id}.
var slots: Array = [null, null, null]
var echoes: int = 0
var bosses_beaten: Dictionary = {}
var best_floor: int = 0
var base_canteen: int = 2

# ------------------------------------------------------------------ run (volatile)
var ash: int = 0
var carried: Dictionary = {}
var carried_blueprints: Array = []
var canteen: int = 2
var form: StringName = &"sweep"
var module: StringName = &""
var shield: bool = false
var blood_debt: int = 0
## [{name, stats, floor}] gone when the floor changes or is rebuilt.
var floor_buffs: Array = []
## [{name, stats, left}] seconds of play left.
var timed_buffs: Array = []
var next_refresh_room: StringName = &""
## Glass Blower: the canteen heals instantly (and has one charge fewer).
var instant_canteen: bool = false
var canteen_penalty: int = 0
## Where the profile is stored. Tests point this somewhere else so they can never touch the real save.
var save_path: String = DEFAULT_SAVE_PATH
var in_run: bool = false


func _ready() -> void:
	load_profile()
	canteen = canteen_max()


func _process(delta: float) -> void:
	if timed_buffs.is_empty():
		return
	for buff in timed_buffs:
		buff["left"] -= delta
	var before := timed_buffs.size()
	timed_buffs = timed_buffs.filter(func(b: Dictionary) -> bool: return b["left"] > 0.0)
	if timed_buffs.size() != before:
		changed.emit()


# ------------------------------------------------------------------ stats

## Sum of one stat over everything that is active right now.
func stat(name: StringName) -> float:
	var total := 0.0
	var key := String(name)
	total += float(((RunData.ARMOR.get(armor, {}) as Dictionary).get("stats", {}) as Dictionary).get(key, 0.0))
	for i in SLOT_COUNT:
		var info := slot_info(i)
		if not info.is_empty() and not info["fractured"]:
			total += float((info["def"]["stats"] as Dictionary).get(key, 0.0))
	if module != &"":
		total += float(((RunData.MODULES.get(module, {}) as Dictionary).get("stats", {}) as Dictionary).get(key, 0.0))
	for buff: Dictionary in floor_buffs:
		total += float((buff["stats"] as Dictionary).get(key, 0.0))
	for buff: Dictionary in timed_buffs:
		total += float((buff["stats"] as Dictionary).get(key, 0.0))
	return total


func max_health() -> int:
	var flat := float(RunData.BASE_MAX_HEALTH) + stat(&"max_hp")
	return maxi(10, int(round(flat * (1.0 + stat(&"max_hp_pct")))))


func damage_taken_mult() -> float:
	return maxf(0.15, 1.0 + stat(&"taken"))


func canteen_max() -> int:
	return maxi(1, base_canteen + int(stat(&"canteen_max")) - canteen_penalty)


# ------------------------------------------------------------------ slots

## {id, kind, fractured, def} for a charm slot, or {} when it is empty.
func slot_info(index: int) -> Dictionary:
	var slot = slots[index]
	if slot == null:
		return {}
	var kind: String = slot["kind"]
	if kind == "forged":
		var entry: Dictionary = forged[int(slot["ref"])]
		return {"id": entry["id"], "kind": kind, "fractured": bool(entry["fractured"]), "def": RunData.CHARMS[entry["id"]]}
	var table: Dictionary = RunData.GRAFTS if kind == "graft" else RunData.CHARMS
	return {"id": StringName(slot["id"]), "kind": kind, "fractured": false, "def": table[StringName(slot["id"])]}


func free_slot() -> int:
	for i in SLOT_COUNT:
		if slots[i] == null:
			return i
	return -1


func graft_count() -> int:
	var n := 0
	for i in SLOT_COUNT:
		if not slot_info(i).is_empty() and slot_info(i)["kind"] == "graft":
			n += 1
	return n


## A forged charm is in a slot when a slot refers to it.
func is_slotted(forged_index: int) -> bool:
	for slot in slots:
		if slot != null and slot["kind"] == "forged" and int(slot["ref"]) == forged_index:
			return true
	return false


## Puts a forged charm (by index into `forged`) into a slot. A graft in that slot cannot be replaced.
func slot_forged(forged_index: int, slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT or is_slotted(forged_index):
		return false
	var current = slots[slot_index]
	if current != null and current["kind"] == "graft":
		return false
	slots[slot_index] = {"kind": "forged", "ref": forged_index}
	_loadout_changed()
	return true


func clear_slot(slot_index: int) -> bool:
	var current = slots[slot_index]
	if current == null or current["kind"] == "graft":
		return false # a parasitic graft cannot be taken off
	slots[slot_index] = null
	_loadout_changed()
	return true


## A graft or a run-only charm goes into a free slot. Returns false when none is free.
func add_slotted(id: StringName, kind: String) -> bool:
	var index := free_slot()
	if index < 0:
		return false
	slots[index] = {"kind": kind, "id": String(id)}
	_loadout_changed()
	return true


## Cleansing Pool: removes one graft.
func remove_graft(slot_index: int) -> bool:
	var current = slots[slot_index]
	if current == null or current["kind"] != "graft":
		return false
	slots[slot_index] = null
	_loadout_changed()
	return true


func equip_armor(id: StringName) -> bool:
	if not owned_armor.has(id):
		return false
	armor = id
	_loadout_changed()
	return true


func _loadout_changed() -> void:
	changed.emit()
	save_profile()


# ------------------------------------------------------------------ ash, materials, blueprints

## Ash picked up (scaled by the ash bonus). Returns how much was gained.
func add_ash(amount: int) -> int:
	var gained := maxi(0, int(round(float(amount) * (1.0 + stat(&"ash")))))
	ash += gained
	ash_changed.emit(ash)
	changed.emit()
	return gained


func spend_ash(amount: int) -> bool:
	if ash < amount:
		return false
	ash -= amount
	ash_changed.emit(ash)
	changed.emit()
	return true


func add_material(id: StringName, amount: int = 1) -> void:
	carried[id] = int(carried.get(id, 0)) + amount
	changed.emit()


func add_blueprint(id: StringName) -> void:
	if not carried_blueprints.has(id) and not blueprints.has(id):
		carried_blueprints.append(id)
		changed.emit()


func carried_total() -> int:
	var total := 0
	for id in carried:
		total += int(carried[id])
	return total


## Banks everything carried: materials and ash go to the stash, blueprints are learned. Returns a summary.
func extract() -> Dictionary:
	var summary := {"ash": ash, "materials": carried.duplicate(), "blueprints": carried_blueprints.duplicate()}
	for id in carried:
		stash[id] = int(stash.get(id, 0)) + int(carried[id])
	stash_ash += ash
	for bp in carried_blueprints:
		blueprints[bp] = true
	carried.clear()
	carried_blueprints.clear()
	ash = 0
	ash_changed.emit(ash)
	changed.emit()
	save_profile()
	return summary


func has_anything_to_extract() -> bool:
	return ash > 0 or not carried.is_empty() or not carried_blueprints.is_empty()


# ------------------------------------------------------------------ canteen

func refill_canteen() -> void:
	canteen = canteen_max()
	canteen_changed.emit()
	changed.emit()


## Healing from the canteen or kills first repays the blood debt (see the Blood Font).
func absorb_heal(amount: int) -> int:
	if blood_debt <= 0:
		return amount
	var paid := mini(blood_debt, amount)
	blood_debt -= paid
	changed.emit()
	return amount - paid


# ------------------------------------------------------------------ buffs

func add_floor_buff(buff_name: String, stats: Dictionary) -> void:
	floor_buffs.append({"name": buff_name, "stats": stats})
	changed.emit()


func add_timed_buff(buff_name: String, stats: Dictionary, seconds: float) -> void:
	timed_buffs.append({"name": buff_name, "stats": stats, "left": seconds})
	changed.emit()


## A floor was left, rebuilt or the run ended: floor-wise effects go away.
func clear_floor_effects() -> void:
	floor_buffs.clear()
	shield = false
	changed.emit()


# ------------------------------------------------------------------ crafting (at the workbench; uses the stash)

func can_afford(recipe: Dictionary) -> bool:
	if stash_ash < int(recipe["ash"]):
		return false
	for id: StringName in recipe["cost"]:
		if int(stash.get(id, 0)) < int(recipe["cost"][id]):
			return false
	return true


## "" when the recipe can be crafted, otherwise the reason it cannot.
func why_not(recipe: Dictionary) -> String:
	if recipe["type"] == "armor":
		var bp: StringName = RunData.ARMOR[recipe["id"]]["blueprint"]
		if owned_armor.has(recipe["id"]):
			return "ALREADY OWNED"
		if not blueprints.has(bp):
			return "NEEDS BLUEPRINT"
	if not can_afford(recipe):
		return "MISSING MATERIALS"
	return ""


func craft(recipe_id: StringName) -> bool:
	var recipe := RunData.recipe_for(recipe_id)
	if recipe.is_empty() or why_not(recipe) != "":
		return false
	for id: StringName in recipe["cost"]:
		stash[id] = int(stash.get(id, 0)) - int(recipe["cost"][id])
	stash_ash -= int(recipe["ash"])
	match String(recipe["type"]):
		"armor":
			owned_armor.append(recipe_id)
		"echo":
			echoes += 1
		_:
			forged.append({"id": recipe_id, "fractured": false})
	changed.emit()
	save_profile()
	return true


## The cheapest material of the charm's recipe is what repairing it costs.
func repair_cost(forged_index: int) -> Dictionary:
	var recipe := RunData.recipe_for(forged[forged_index]["id"])
	var material: StringName = (recipe["cost"] as Dictionary).keys()[0]
	return {"material": material, "ash": RunData.REPAIR_ASH}


func repair(forged_index: int) -> bool:
	if not bool(forged[forged_index]["fractured"]):
		return false
	var cost := repair_cost(forged_index)
	if stash_ash < int(cost["ash"]) or int(stash.get(cost["material"], 0)) < 1:
		return false
	stash[cost["material"]] = int(stash[cost["material"]]) - 1
	stash_ash -= int(cost["ash"])
	forged[forged_index]["fractured"] = false
	changed.emit()
	save_profile()
	return true


## Smuggler's Exchange: repairs one fractured charm for time instead of materials.
func repair_free(forged_index: int) -> bool:
	if not bool(forged[forged_index]["fractured"]):
		return false
	forged[forged_index]["fractured"] = false
	changed.emit()
	save_profile()
	return true


func fractured_indices() -> Array[int]:
	var result: Array[int] = []
	for i in forged.size():
		if bool(forged[i]["fractured"]):
			result.append(i)
	return result


# ------------------------------------------------------------------ run lifecycle

## Called when the player steps out of the base into floor 1 (a fresh run).
func begin_run() -> void:
	in_run = true
	canteen = canteen_max()
	canteen_changed.emit()
	changed.emit()


## Death: everything carried is lost, grafts and temporary charms vanish, worn forged charms fracture.
func die() -> void:
	carried.clear()
	carried_blueprints.clear()
	ash = 0
	for i in SLOT_COUNT:
		var slot = slots[i]
		if slot == null:
			continue
		if slot["kind"] == "forged":
			forged[int(slot["ref"])]["fractured"] = true
		else:
			slots[i] = null
	form = &"sweep"
	module = &""
	shield = false
	blood_debt = 0
	floor_buffs.clear()
	timed_buffs.clear()
	next_refresh_room = &""
	instant_canteen = false
	canteen_penalty = 0
	in_run = false
	canteen = canteen_max()
	ash_changed.emit(ash)
	canteen_changed.emit()
	changed.emit()
	save_profile()


## Safely back in the base: what you carry is banked, the run ends (the loadout stays).
func end_run_alive() -> void:
	extract()
	for i in SLOT_COUNT:
		var slot = slots[i]
		if slot != null and slot["kind"] != "forged":
			slots[i] = null # grafts and run-only charms do not outlive the run
	form = &"sweep"
	module = &""
	shield = false
	blood_debt = 0
	floor_buffs.clear()
	next_refresh_room = &""
	instant_canteen = false
	canteen_penalty = 0
	in_run = false
	canteen = canteen_max()
	canteen_changed.emit()
	changed.emit()
	save_profile()


# ------------------------------------------------------------------ persistence

func save_profile() -> void:
	var data := {
		"stash": _strings(stash), "stash_ash": stash_ash, "blueprints": _strings(blueprints),
		"owned_armor": owned_armor.map(func(a: Variant) -> String: return String(a)), "armor": String(armor),
		"forged": forged.map(func(f: Dictionary) -> Dictionary: return {"id": String(f["id"]), "fractured": f["fractured"]}),
		"slots": slots, "echoes": echoes, "bosses_beaten": _strings(bosses_beaten), "best_floor": best_floor,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))


func load_profile() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	stash = _names(data.get("stash", {}))
	stash_ash = int(data.get("stash_ash", STARTING_ASH))
	blueprints = _names(data.get("blueprints", {}))
	owned_armor = (data.get("owned_armor", ["prisoner_rags"]) as Array).map(func(a: Variant) -> StringName: return StringName(a))
	armor = StringName(data.get("armor", "prisoner_rags"))
	forged = (data.get("forged", []) as Array).map(func(f: Dictionary) -> Dictionary: return {"id": StringName(f["id"]), "fractured": bool(f["fractured"])})
	var saved_slots: Array = data.get("slots", [null, null, null])
	slots = [null, null, null]
	for i in mini(saved_slots.size(), SLOT_COUNT):
		var slot = saved_slots[i]
		if slot is Dictionary and slot["kind"] == "forged" and int(slot["ref"]) < forged.size():
			slots[i] = {"kind": "forged", "ref": int(slot["ref"])}
	echoes = int(data.get("echoes", 0))
	bosses_beaten = _names(data.get("bosses_beaten", {}))
	best_floor = int(data.get("best_floor", 0))


## For tests: forget the saved profile and use another file.
func reset_for_test() -> void:
	stash.clear()
	stash_ash = STARTING_ASH
	blueprints.clear()
	owned_armor = [&"prisoner_rags"]
	armor = &"prisoner_rags"
	forged.clear()
	slots = [null, null, null]
	echoes = 0
	bosses_beaten.clear()
	carried.clear()
	carried_blueprints.clear()
	ash = 0
	form = &"sweep"
	module = &""
	shield = false
	blood_debt = 0
	floor_buffs.clear()
	timed_buffs.clear()
	canteen_penalty = 0
	instant_canteen = false
	canteen = canteen_max()
	changed.emit()


func _strings(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		result[String(key)] = source[key]
	return result


func _names(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		result[StringName(key)] = source[key]
	return result
