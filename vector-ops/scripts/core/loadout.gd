class_name Loadout
extends RefCounted
## Module database + loadout weight maths.
## Two hands, four slots each. A loadout is [[right x4], [left x4]].
## Max Flux = 100 - (Total Weight of everything carried x 7) + 3 per empty slot.
## Every module's numbers, colour and text live in res://data/modules/<id>.tres
## (see ModuleData); this class only loads them and does the loadout maths.

const BASE_MAX_FLUX := 100.0
const WEIGHT_PENALTY := 7.0
const EMPTY_SLOT_BONUS := 3.0
const HANDS := 2
const SLOTS_PER_HAND := 4
const MIN_MAX_FLUX := 30.0
const DATA_DIR := "res://data/modules/"
const EMPTY_COLOR := Color(0.2, 0.3, 0.35)

## Order modules are listed in (menu picker, guide). Each id needs a .tres in DATA_DIR.
const ORDER: Array[String] = ["kinetic", "blast", "seeker", "bolt", "edge", "aegis", "bunker", "heal", "boost", "shift", "ghost", "mirage"]

static var _db: Dictionary = {}


static func _ensure() -> void:
	if not _db.is_empty():
		return
	for id in ORDER:
		var d := load("%s%s.tres" % [DATA_DIR, id]) as ModuleData
		if d == null or d.id != id:
			push_error("Loadout: missing or mismatched module data for '%s'" % id)
			continue
		_db[id] = d


static func ids() -> Array:
	_ensure()
	return ORDER


static func get_data(id: String) -> ModuleData:
	_ensure()
	return _db.get(id)


static func color_of(id: String) -> Color:
	var d := get_data(id)
	return d.color if d != null else EMPTY_COLOR


static func category_of(id: String) -> String:
	var d := get_data(id)
	return d.category if d != null else ""


static func hud_meta_of(id: String) -> String:
	var d := get_data(id)
	return d.hud_meta if d != null else ""


static func is_valid(id: String) -> bool:
	_ensure()
	return _db.has(id)


## Always returns [[4 strings], [4 strings]].
static func sanitize(l: Array) -> Array:
	var out: Array = []
	for h in HANDS:
		var src: Array = []
		if h < l.size() and l[h] is Array:
			src = l[h]
		var hand: Array = []
		for i in SLOTS_PER_HAND:
			var id: String = ""
			if i < src.size():
				id = String(src[i])
			if not is_valid(id):
				id = ""
			hand.append(id)
		out.append(hand)
	return out


static func default_loadout() -> Array:
	return [["kinetic", "edge", "", ""], ["aegis", "boost", "", ""]]


## Index of the first non-empty slot in one hand (0 if the hand is empty).
static func first_slot(hand: Array) -> int:
	for i in hand.size():
		if String(hand[i]) != "":
			return i
	return 0


static func total_weight(l: Array) -> float:
	_ensure()
	var w := 0.0
	for hand in sanitize(l):
		for id in hand:
			if id != "":
				w += (_db[id] as ModuleData).weight
	return w


static func empty_slots(l: Array) -> int:
	var n := 0
	for hand in sanitize(l):
		for id in hand:
			if id == "":
				n += 1
	return n


static func max_flux(l: Array) -> float:
	var v := BASE_MAX_FLUX - total_weight(l) * WEIGHT_PENALTY + float(empty_slots(l)) * EMPTY_SLOT_BONUS
	return maxf(MIN_MAX_FLUX, v)


static func create_module(id: String) -> Module:
	var d := get_data(id)
	var m: Module = load(d.script_path).new()
	m.data = d
	return m
