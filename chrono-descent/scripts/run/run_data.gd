class_name RunData
extends RefCounted
## Every fixed fact of the run economy, in one place (nothing here changes while playing):
## materials, armor sets, forged charms, parasitic grafts, weapon forms, tactical override modules,
## blueprints and the workbench recipes. The live state (what you carry, wear and have banked) is in Run.
##
## STATS. Armor, charms, grafts, modules, forms and buffs all speak the same language: a dictionary of
## stat -> number. Run.stat(&"damage") adds up every active source. Meaning of each stat:
##   max_hp        flat extra health               damage      +% sword damage        attack_speed  +% swing speed
##   move          +% walking / running speed      taken       +% damage taken (negative = armor)
##   ash           +% ash gained                   heal        +% canteen healing     lifesteal     % of damage dealt healed
##   kill_heal     % of max health healed per kill iframes     +% dash invulnerability  dash_cd     +% dash cooldown
##   time_rate     +% faster floor timer           canteen_max flat extra flask charges  enemy_hp    +% enemy health
##   elite_dmg     +% damage to elites and bosses  regen       health per second (negative drains)
##   reach         +% sword reach                  drop_mats   flat extra materials from elites / bosses

const FLOORS: int = 10

# ------------------------------------------------------------------ materials
## id -> {name, tier, color, desc}. Tier decides which floors drop it (1: floors 1-3, 2: 4-6, 3: 7-10).
const MATERIALS: Dictionary = {
	&"slime_core": {"name": "Slime Core", "tier": 1, "color": Color(0.75, 0.45, 1.0), "desc": "A pulsing core ripped from a slime."},
	&"bone_dust": {"name": "Bone Dust", "tier": 1, "color": Color(0.88, 0.85, 0.72), "desc": "Fine powder of ground skeleton."},
	&"weaver_ash": {"name": "Weaver Ash", "tier": 1, "color": Color(0.6, 0.62, 0.7), "desc": "Grey ash that still remembers thread."},
	&"golem_heart": {"name": "Golem Heart", "tier": 2, "color": Color(1.0, 0.55, 0.2), "desc": "A cooling ember of living stone."},
	&"mimic_fang": {"name": "Mimic Fang", "tier": 2, "color": Color(0.9, 0.3, 0.3), "desc": "A tooth from something pretending to be a chest."},
	&"phantom_thread": {"name": "Phantom Thread", "tier": 2, "color": Color(0.5, 0.85, 0.95), "desc": "Cold thread spun from a curse."},
	&"chrono_sand": {"name": "Chrono Sand", "tier": 3, "color": Color(1.0, 0.85, 0.4), "desc": "Sand that falls upward."},
	&"void_marrow": {"name": "Void Marrow", "tier": 3, "color": Color(0.45, 0.35, 0.8), "desc": "The hollow centre of deep bone."},
	&"predecessor_alloy": {"name": "Predecessor Alloy", "tier": 3, "color": Color(0.4, 0.95, 0.75), "desc": "Metal nobody alive knows how to make."},
}

# ------------------------------------------------------------------ armor
## id -> {name, desc, stats, color, blueprint}. Every armor has THREE charm slots.
const ARMOR: Dictionary = {
	&"prisoner_rags": {"name": "Prisoner's Rags", "desc": "Scraps of cloth. Better than nothing.", "stats": {}, "color": Color(0.6, 0.55, 0.5), "blueprint": &""},
	&"scrap_plate": {"name": "Scrap Plate", "desc": "Riveted jailer plates.", "stats": {"max_hp": 10, "taken": -0.10}, "color": Color(0.7, 0.72, 0.78), "blueprint": &"bp_scrap_plate"},
	&"weaver_vestments": {"name": "Weaver Vestments", "desc": "Light and quick.", "stats": {"max_hp": 6, "taken": -0.06, "move": 0.12}, "color": Color(0.55, 0.6, 0.85), "blueprint": &"bp_weaver_vestments"},
	&"golem_carapace": {"name": "Golem Carapace", "desc": "Heavy stone, warm to the touch.", "stats": {"max_hp": 24, "taken": -0.18, "move": -0.05}, "color": Color(1.0, 0.55, 0.2), "blueprint": &"bp_golem_carapace"},
	&"mimic_hide": {"name": "Mimic Hide", "desc": "It still bites back.", "stats": {"max_hp": 12, "taken": -0.12, "damage": 0.10}, "color": Color(0.85, 0.35, 0.3), "blueprint": &"bp_mimic_hide"},
	&"chrono_regalia": {"name": "Chrono Regalia", "desc": "Worn by a prisoner who outlived time.", "stats": {"max_hp": 30, "taken": -0.25, "damage": 0.10, "move": 0.06}, "color": Color(1.0, 0.85, 0.4), "blueprint": &"bp_chrono_regalia"},
}

# ------------------------------------------------------------------ forged charms (safe, permanent)
## id -> {name, desc, stats, color}
const CHARMS: Dictionary = {
	&"vigor": {"name": "Charm of Vigor", "desc": "+15 maximum health.", "stats": {"max_hp": 15}, "color": Color(0.9, 0.3, 0.35)},
	&"edge": {"name": "Sharpened Edge", "desc": "+12% sword damage.", "stats": {"damage": 0.12}, "color": Color(0.95, 0.8, 0.4)},
	&"fleet": {"name": "Fleet Foot", "desc": "+10% movement speed.", "stats": {"move": 0.10}, "color": Color(0.5, 0.9, 0.7)},
	&"ironskin": {"name": "Iron Skin", "desc": "8% less damage taken.", "stats": {"taken": -0.08}, "color": Color(0.7, 0.75, 0.85)},
	&"leech": {"name": "Leech Fang", "desc": "Heal 4% of the damage you deal.", "stats": {"lifesteal": 0.04}, "color": Color(0.8, 0.25, 0.45)},
	&"magnet": {"name": "Ash Magnet", "desc": "+25% ash from everything.", "stats": {"ash": 0.25}, "color": Color(0.65, 0.6, 0.55)},
	&"draught": {"name": "Quick Draught", "desc": "The canteen heals 30% more.", "stats": {"heal": 0.30}, "color": Color(0.4, 0.8, 0.95)},
	&"phase": {"name": "Phase Step", "desc": "Dash invulnerability lasts 30% longer.", "stats": {"iframes": 0.30}, "color": Color(0.6, 0.5, 1.0)},
	&"second_wind": {"name": "Second Wind", "desc": "+1 canteen charge.", "stats": {"canteen_max": 1}, "color": Color(0.5, 0.95, 0.5)},
	&"executioner": {"name": "Executioner's Mark", "desc": "+25% damage to elites and bosses.", "stats": {"elite_dmg": 0.25}, "color": Color(0.9, 0.45, 0.2)},
	&"swiftblade": {"name": "Swiftblade", "desc": "+12% swing speed.", "stats": {"attack_speed": 0.12}, "color": Color(0.9, 0.9, 0.55)},
	&"reaper": {"name": "Reaper's Toll", "desc": "Heal 2% of your health per kill.", "stats": {"kill_heal": 0.02}, "color": Color(0.7, 0.4, 0.9)},
}

# ------------------------------------------------------------------ parasitic grafts (found mid-run)
## Same shape as charms, but every graft has a CURSE (its negative stats) and locks its slot until you die
## or use a Cleansing Pool.
const GRAFTS: Dictionary = {
	&"hungry_maw": {"name": "Hungry Maw", "desc": "+30% sword damage.", "curse": "-20% maximum health.", "stats": {"damage": 0.30, "max_hp_pct": -0.20}, "color": Color(0.85, 0.25, 0.3)},
	&"glass_heart": {"name": "Glass Heart", "desc": "+60% sword damage.", "curse": "You take 40% more damage.", "stats": {"damage": 0.60, "taken": 0.40}, "color": Color(0.7, 0.9, 1.0)},
	&"time_leech": {"name": "Time Leech", "desc": "Every kill heals 3% of your health.", "curse": "The floor timer runs 25% faster.", "stats": {"kill_heal": 0.03, "time_rate": 0.25}, "color": Color(0.95, 0.8, 0.3)},
	&"ash_siphon": {"name": "Ash Siphon", "desc": "+100% ash from everything.", "curse": "-1 canteen charge.", "stats": {"ash": 1.0, "canteen_max": -1}, "color": Color(0.6, 0.55, 0.5)},
	&"bloodlust": {"name": "Bloodlust", "desc": "Heal 6% of your health per kill.", "curse": "The canteen heals 50% less.", "stats": {"kill_heal": 0.06, "heal": -0.50}, "color": Color(0.9, 0.2, 0.2)},
	&"quickblood": {"name": "Quickblood", "desc": "+25% movement and +20% swing speed.", "curse": "You bleed: lose 1 health every 4 seconds.", "stats": {"move": 0.25, "attack_speed": 0.20, "regen": -0.25}, "color": Color(0.95, 0.4, 0.5)},
	&"marrow_plating": {"name": "Marrow Plating", "desc": "25% less damage taken.", "curse": "-15% movement speed.", "stats": {"taken": -0.25, "move": -0.15}, "color": Color(0.9, 0.88, 0.75)},
	&"rotting_crown": {"name": "Rotting Crown", "desc": "Elites and bosses drop 2 extra materials.", "curse": "Enemies have 25% more health.", "stats": {"drop_mats": 2, "enemy_hp": 0.25}, "color": Color(0.5, 0.75, 0.35)},
}

# ------------------------------------------------------------------ sword forms (Weapon Mold) and modules
## The sword has three forms, one per attack animation of the prisoner. arc = width of the swing in degrees,
## reach = px from the body, dmg = damage multiplier, cooldown = seconds between swings, knock = knockback.
const FORMS: Dictionary = {
	&"sweep": {"name": "Sweep", "desc": "A wide, balanced arc.", "arc": 150.0, "reach": 40.0, "dmg": 1.0, "cooldown": 0.40, "knock": 150.0, "anim": "sweep", "frames": 8, "active": [3, 5]},
	&"jab": {"name": "Jab", "desc": "A fast, narrow thrust that reaches far.", "arc": 46.0, "reach": 50.0, "dmg": 0.8, "cooldown": 0.30, "knock": 100.0, "anim": "jab", "frames": 6, "active": [3, 3]},
	&"slam": {"name": "Slam", "desc": "A slow overhead smash that hits all around the point of impact.", "arc": 200.0, "reach": 38.0, "dmg": 1.7, "cooldown": 0.85, "knock": 260.0, "anim": "slam", "frames": 8, "active": [4, 5]},
	&"bow": {"name": "Bow", "desc": "Loose arrows from a distance: slower, a little weaker, never touches the foe.", "arc": 0.0, "reach": 0.0, "dmg": 0.9, "cooldown": 0.65, "knock": 90.0, "anim": "bow", "frames": 8, "active": [5, 5], "ranged": true},
}
const BASE_SWORD_DAMAGE: int = 12
const BASE_MAX_HEALTH: int = 50

## Tactical Override modules (weapon upgrades from the Blood Font).
const MODULES: Dictionary = {
	&"serrated": {"name": "Serrated Override", "desc": "+20% sword damage.", "stats": {"damage": 0.20}},
	&"siphon": {"name": "Siphon Override", "desc": "Heal 5% of the damage you deal.", "stats": {"lifesteal": 0.05}},
	&"overclock": {"name": "Overclock Override", "desc": "+25% swing speed.", "stats": {"attack_speed": 0.25}},
	&"longedge": {"name": "Long-Edge Override", "desc": "+25% sword reach.", "stats": {"reach": 0.25}},
	&"reaver": {"name": "Reaver Override", "desc": "+30% damage to elites and bosses.", "stats": {"elite_dmg": 0.30}},
}

# ------------------------------------------------------------------ blueprints
## Blueprints unlock armor sets. (Weapon archetype blueprints will unlock new swords later.)
const BLUEPRINTS: Dictionary = {
	&"bp_scrap_plate": {"name": "Scrap Plate Blueprint", "unlocks": &"scrap_plate"},
	&"bp_weaver_vestments": {"name": "Weaver Vestments Blueprint", "unlocks": &"weaver_vestments"},
	&"bp_golem_carapace": {"name": "Golem Carapace Blueprint", "unlocks": &"golem_carapace"},
	&"bp_mimic_hide": {"name": "Mimic Hide Blueprint", "unlocks": &"mimic_hide"},
	&"bp_chrono_regalia": {"name": "Chrono Regalia Blueprint", "unlocks": &"chrono_regalia"},
}

# ------------------------------------------------------------------ workbench recipes
## type: "armor" | "charm". cost = materials, ash = ash used as FUEL. Armor also needs its blueprint.
const RECIPES: Array = [
	{"id": &"vigor", "type": "charm", "cost": {&"slime_core": 2}, "ash": 20},
	{"id": &"edge", "type": "charm", "cost": {&"bone_dust": 2}, "ash": 20},
	{"id": &"fleet", "type": "charm", "cost": {&"weaver_ash": 2}, "ash": 20},
	{"id": &"ironskin", "type": "charm", "cost": {&"bone_dust": 3, &"slime_core": 1}, "ash": 30},
	{"id": &"magnet", "type": "charm", "cost": {&"weaver_ash": 2, &"bone_dust": 1}, "ash": 25},
	{"id": &"draught", "type": "charm", "cost": {&"slime_core": 3}, "ash": 30},
	{"id": &"swiftblade", "type": "charm", "cost": {&"weaver_ash": 3}, "ash": 35},
	{"id": &"leech", "type": "charm", "cost": {&"slime_core": 3, &"bone_dust": 3}, "ash": 50},
	{"id": &"phase", "type": "charm", "cost": {&"phantom_thread": 3}, "ash": 60},
	{"id": &"executioner", "type": "charm", "cost": {&"golem_heart": 2, &"bone_dust": 4}, "ash": 70},
	{"id": &"reaper", "type": "charm", "cost": {&"mimic_fang": 3, &"weaver_ash": 3}, "ash": 80},
	{"id": &"second_wind", "type": "charm", "cost": {&"golem_heart": 3, &"phantom_thread": 2}, "ash": 100},
	{"id": &"scrap_plate", "type": "armor", "cost": {&"slime_core": 5, &"bone_dust": 5}, "ash": 50},
	{"id": &"weaver_vestments", "type": "armor", "cost": {&"weaver_ash": 8, &"slime_core": 4}, "ash": 70},
	{"id": &"golem_carapace", "type": "armor", "cost": {&"golem_heart": 6, &"bone_dust": 8}, "ash": 130},
	{"id": &"mimic_hide", "type": "armor", "cost": {&"mimic_fang": 6, &"weaver_ash": 6}, "ash": 150},
	{"id": &"chrono_regalia", "type": "armor", "cost": {&"chrono_sand": 6, &"void_marrow": 4, &"predecessor_alloy": 3}, "ash": 300},
	{"id": &"memory_echo", "type": "echo", "cost": {&"phantom_thread": 2}, "ash": 40},
]
## Repairing a fractured forged charm: one material of its tier and a little ash.
const REPAIR_ASH: int = 15

# ------------------------------------------------------------------ the floor bosses
## Which boss guards the extraction room of each floor (1..10). Floor 10 is the final one.
const BOSS_BY_FLOOR: Array = [&"slime_queen", &"golem", &"mimic", &"slime_queen", &"golem", &"mimic", &"slime_queen", &"golem", &"mimic", &"dracula"]
## Blueprint a boss drops the FIRST time it is beaten.
const BOSS_BLUEPRINT: Dictionary = {&"slime_queen": &"bp_scrap_plate", &"golem": &"bp_golem_carapace", &"mimic": &"bp_mimic_hide", &"dracula": &"bp_chrono_regalia"}


# ------------------------------------------------------------------ helpers

static func material_name(id: StringName) -> String:
	return String((MATERIALS.get(id, {}) as Dictionary).get("name", str(id)))


static func material_color(id: StringName) -> Color:
	return (MATERIALS.get(id, {}) as Dictionary).get("color", Color.WHITE)


## A random material of a tier (1..3), or of the tier for a given floor.
static func tier_for_floor(floor_number: int) -> int:
	if floor_number <= 3:
		return 1
	if floor_number <= 6:
		return 2
	return 3


static func materials_of_tier(tier: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in MATERIALS:
		if int((MATERIALS[id] as Dictionary)["tier"]) == tier:
			result.append(id)
	return result


## Charm or graft or armor or module definition by id (any kind), or {}.
static func definition(id: StringName) -> Dictionary:
	for table: Dictionary in [CHARMS, GRAFTS, ARMOR, MODULES]:
		if table.has(id):
			return table[id]
	return {}


static func recipe_for(id: StringName) -> Dictionary:
	for r: Dictionary in RECIPES:
		if r["id"] == id:
			return r
	return {}


## {name, desc, color, stats} to show for a recipe (armor, charm or the echo).
static func recipe_info(recipe: Dictionary) -> Dictionary:
	var id: StringName = recipe["id"]
	match String(recipe["type"]):
		"armor":
			return ARMOR[id]
		"charm":
			return CHARMS[id]
	return {"name": "Memory Echo", "desc": "Reveals the whole map of a floor when used. Keep it for a later run.", "color": Color(0.6, 0.85, 1.0), "stats": {}}
