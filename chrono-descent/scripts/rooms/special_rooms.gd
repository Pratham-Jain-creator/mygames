class_name SpecialRooms
extends RefCounted
## The registry of every special room, and what a floor gets of them.
##
## FAMILIES
##   boon     15 rooms that give something (a graft, a heal, a shortcut...), most at a price or a risk
##   curse    6 opt-in challenges: you pay health at the altar, a rule of the game changes, the reward is high
##   hidden   4 secret rooms behind an illusory wall
##   elite    a single elite enemy and its escort guarding a chest
##   survival the time-survivors room: waves that keep coming for one minute
## Boon, curse, hidden and elite rooms are always DEAD ENDS (one opening), so they connect to the dungeon from any
## side. Time-survivor rooms prefer a big room.

## The room scripts are loaded when needed (not preloaded): they refer back to this class, and two scripts that
## preload each other cannot compile.
const BOON_SCRIPT: String = "res://scripts/rooms/boon_room.gd"
const CURSE_SCRIPT: String = "res://scripts/rooms/curse_room.gd"
const HIDDEN_SCRIPT: String = "res://scripts/rooms/hidden_room.gd"
const ELITE_SCRIPT: String = "res://scripts/rooms/elite_room.gd"
const SURVIVAL_SCRIPT: String = "res://scripts/rooms/survival_room.gd"

const BOON_COLOR := Color(0.55, 0.95, 0.65)
const CURSE_COLOR := Color(0.95, 0.3, 0.3)
const HIDDEN_COLOR := Color(0.55, 0.85, 1.0)

## kind -> {family, name, tagline, min_depth}
const KINDS: Dictionary = {
	&"grafting_table": {"family": "boon", "name": "The Grafting Table", "tagline": "draft a parasite: it will not come off", "min_depth": 1},
	&"alchemist_remains": {"family": "boon", "name": "The Alchemist's Remains", "tagline": "a canteen refill and a deep breath", "min_depth": 1},
	&"weapon_mold": {"family": "boon", "name": "The Weapon Mold", "tagline": "recast your sword into another form", "min_depth": 1},
	&"memory_echo": {"family": "boon", "name": "The Memory Echo", "tagline": "a map you can read later", "min_depth": 1},
	&"smugglers_cache": {"family": "boon", "name": "The Smuggler's Cache", "tagline": "a fortune in ash... and company", "min_depth": 2},
	&"time_locked_chest": {"family": "boon", "name": "The Time-Locked Chest", "tagline": "it seals itself after five minutes", "min_depth": 1},
	&"cleansing_pool": {"family": "boon", "name": "The Cleansing Pool", "tagline": "wash a parasite away", "min_depth": 2},
	&"anvil_predecessor": {"family": "boon", "name": "The Anvil of the Predecessor", "tagline": "temper your blade", "min_depth": 1},
	&"cartographers_corpse": {"family": "boon", "name": "The Cartographer's Corpse", "tagline": "choose a room of the next shift", "min_depth": 1},
	&"bestiary_scholar": {"family": "boon", "name": "The Bestiary Scholar", "tagline": "a friend among the monsters", "min_depth": 1},
	&"blood_font": {"family": "boon", "name": "The Blood Font", "tagline": "a debt of blood buys a weapon module", "min_depth": 2},
	&"shortcut_shaft": {"family": "boon", "name": "The Shortcut Shaft", "tagline": "a drop to anywhere you have been", "min_depth": 2},
	&"forlorn_shrine": {"family": "boon", "name": "The Forlorn Shrine", "tagline": "it will take one deadly blow for you", "min_depth": 1},
	&"glass_blower": {"family": "boon", "name": "The Glass Blower", "tagline": "a canteen that heals at once", "min_depth": 2},
	&"silent_monolith": {"family": "boon", "name": "The Silent Monolith", "tagline": "three charms, one for this run", "min_depth": 2},
	&"shackled_arena": {"family": "curse", "name": "The Shackled Arena", "tagline": "no dash: only footwork", "min_depth": 1},
	&"suffocating_fog": {"family": "curse", "name": "The Suffocating Fog", "tagline": "the gas drains you; blows heal you", "min_depth": 1},
	&"cursed_hoard": {"family": "curse", "name": "The Cursed Hoard", "tagline": "five chests, one of them is real", "min_depth": 1},
	&"gauntlet_attrition": {"family": "curse", "name": "The Gauntlet of Attrition", "tagline": "survive two minutes of endless enemies", "min_depth": 2},
	&"blind_pits": {"family": "curse", "name": "The Blind Pits", "tagline": "fight by sound and glowing eyes", "min_depth": 2},
	&"phantoms_arena": {"family": "curse", "name": "The Phantom's Arena", "tagline": "it cannot be killed: solve the runes", "min_depth": 3},
	&"chrono_sanctuary": {"family": "hidden", "name": "The Chrono-Sanctuary", "tagline": "the timer stands still in here", "min_depth": 1},
	&"deserters_chute": {"family": "hidden", "name": "The Deserter's Chute", "tagline": "a drop past the boss", "min_depth": 2},
	&"smugglers_exchange": {"family": "hidden", "name": "The Smuggler's Exchange", "tagline": "he trades in time and blood", "min_depth": 2},
	&"predecessors_cache": {"family": "hidden", "name": "The Predecessor's Cache", "tagline": "an armoury from deeper floors", "min_depth": 3},
	&"elite_room": {"family": "elite", "name": "The Champion's Cell", "tagline": "an elite guards the chest", "min_depth": 1},
	&"time_survivors": {"family": "survival", "name": "The Endurance Hall", "tagline": "survive one minute", "min_depth": 1},
}


static func family(kind: StringName) -> String:
	return String((KINDS.get(kind, {}) as Dictionary).get("family", ""))


static func display_name(kind: StringName) -> String:
	return String((KINDS.get(kind, {}) as Dictionary).get("name", str(kind)))


static func kinds_of(family_name: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for kind: StringName in KINDS:
		if KINDS[kind]["family"] == family_name:
			result.append(kind)
	return result


static func family_color(family_name: String) -> Color:
	match family_name:
		"boon":
			return BOON_COLOR
		"curse":
			return CURSE_COLOR
		"hidden":
			return HIDDEN_COLOR
	return Color(1.0, 0.8, 0.4)


## Time-survivor rooms want space for waves of enemies.
static func prefers_big_room(kind: StringName) -> bool:
	return kind == &"time_survivors"


## The special rooms of a floor, MOST IMPORTANT FIRST (the generator drops from the end when it runs out of dead ends):
## a room the Cartographer's Corpse chose, the boons, the curses (fewer than the boons: always a balance), elite rooms,
## time-survivor rooms and maybe one hidden room.
static func plan_kinds(cfg: LevelConfig) -> Array[StringName]:
	var plan: Array[StringName] = []
	var forced := Run.next_refresh_room
	if forced != &"" and KINDS.has(forced):
		plan.append(forced)
	Run.next_refresh_room = &""
	plan.append_array(_pick(kinds_of("boon"), cfg.boon_rooms, cfg.depth, plan))
	plan.append_array(_pick(kinds_of("curse"), mini(cfg.curse_rooms, cfg.boon_rooms - 1), cfg.depth, plan))
	for i in cfg.elite_rooms:
		plan.append(&"elite_room")
	for i in cfg.survival_rooms:
		plan.append(&"time_survivors")
	if randf() < cfg.hidden_chance:
		plan.append_array(_pick(kinds_of("hidden"), 1, cfg.depth, plan))
	return plan


static func _pick(pool: Array[StringName], count: int, depth: int, already: Array[StringName]) -> Array[StringName]:
	var options: Array = pool.filter(func(k: StringName) -> bool: return int(KINDS[k]["min_depth"]) <= depth and not already.has(k))
	options.shuffle()
	var result: Array[StringName] = []
	for i in mini(count, options.size()):
		result.append(options[i])
	return result


## Gives a room its special behaviour. Called by the level generator for every planned room.
static func attach(room: WFCRoom, kind: StringName, cfg: LevelConfig, generator: Node) -> void:
	var info: Dictionary = KINDS[kind]
	var script_path: String
	match String(info["family"]):
		"boon":
			script_path = BOON_SCRIPT
		"curse":
			script_path = CURSE_SCRIPT
		"hidden":
			script_path = HIDDEN_SCRIPT
		"elite":
			script_path = ELITE_SCRIPT
		_:
			script_path = SURVIVAL_SCRIPT
	var controller := (load(script_path) as Script).new() as Node
	controller.name = "Special_%s" % kind
	room.add_child(controller)
	room.set_meta("special_kind", kind)
	room.set_meta("special_family", info["family"])
	controller.call("setup_special", room, kind, cfg, generator)
	if info["family"] != "hidden":
		room.player_entered.connect(func(_r: WFCRoom) -> void:
			var g := RoomKit.game()
			if g != null and g.hud != null:
				g.hud.show_title(String(info["name"]).to_upper(), String(info["tagline"]), 2.2))
