class_name LevelConfig
extends RefCounted
## Everything that makes one dungeon floor different from another. There are TEN floors.
##
## LevelConfig.for_depth(n) is the single place that defines how the game scales from the first floor to the
## last (where Count Dracula waits). Tweak the formulas here to rebalance.

const FINAL_DEPTH: int = 10
## Seconds each floor lasts before it shifts (15 minutes).
const DEFAULT_DURATION: float = 900.0
## Floor 1 has this many rooms; every floor after it has ROOMS_PER_FLOOR more.
const FIRST_FLOOR_ROOMS: int = 25
const ROOMS_PER_FLOOR: int = 2

## Everything a boss room needs to know about its boss. `floor_line` is the line under the floor title when
## the floor is entered. Which boss guards which floor: RunData.BOSS_BY_FLOOR.
const BOSS_INFO: Dictionary = {
	&"slime_queen": {
		"key": &"slime_queen", "scene": "res://scenes/enemies/slime_queen.tscn", "title": "SLIME QUEEN", "subtitle": "RULER OF THE MUCK",
		"color": Color(0.78, 0.45, 1.0), "floor_line": "the Slime Queen rules the deepest room",
	},
	&"golem": {
		"key": &"golem", "scene": "res://scenes/enemies/golem_boss.tscn", "title": "ANCIENT GOLEM", "subtitle": "GUARDIAN OF THE DEEP FORGE",
		"color": Color(1.0, 0.55, 0.2), "floor_line": "an Ancient Golem guards the deepest room",
	},
	&"mimic": {
		"key": &"mimic", "scene": "res://scenes/enemies/mimic_boss.tscn", "title": "THE GREAT MIMIC", "subtitle": "HUNGER IN A GILDED SHELL",
		"color": Color(0.95, 0.35, 0.3), "floor_line": "something in the deepest room is far too shiny",
	},
	&"dracula": {
		"key": &"dracula", "scene": "res://scenes/enemies/dracula_boss.tscn", "title": "COUNT DRACULA", "subtitle": "LORD OF THE LAST NIGHT",
		"color": Color(0.9, 0.15, 0.25), "floor_line": "the final floor: Count Dracula waits",
	},
}

## Enemies unlocked as you descend. cost = threat points, weight = spawn chance.
const ENEMIES: Array = [
	{"path": "res://scenes/enemies/slime.tscn", "cost": 10, "weight": 4, "min_depth": 1},
	{"path": "res://scenes/enemies/skeleton_archer.tscn", "cost": 15, "weight": 3, "min_depth": 1},
	{"path": "res://scenes/enemies/skeleton_warrior.tscn", "cost": 20, "weight": 3, "min_depth": 1},
	{"path": "res://scenes/enemies/bat.tscn", "cost": 8, "weight": 3, "min_depth": 2},
	{"path": "res://scenes/enemies/mini_golem.tscn", "cost": 30, "weight": 2, "min_depth": 3},
	{"path": "res://scenes/enemies/dracula.tscn", "cost": 25, "weight": 2, "min_depth": 4},
	{"path": "res://scenes/enemies/skull_spirit.tscn", "cost": 20, "weight": 2, "min_depth": 6},
]

var depth: int = 1
var seed_value: int = 0
## Which start room of the pool this floor uses (-1 = pick one at random).
var start_index: int = -1
var duration: float = DEFAULT_DURATION
## 1.0 on the first floor, grows every floor. Scales threat budgets.
var difficulty: float = 1.0
var min_rooms: int = FIRST_FLOOR_ROOMS
var max_rooms: int = FIRST_FLOOR_ROOMS + 5
## Waves in a dead-end "guard" gauntlet and in an "arena" gauntlet, and their threat budgets.
var guard_waves: int = 2
var guard_budget: int = 50
var arena_waves: int = 3
var arena_budget: int = 45
var arena_chance: float = 0.4
var max_arenas: int = 2
## Multiplier on every normal room's own threat cost.
var normal_budget_mult: float = 1.0
var trap_max_per_room: int = 3
## Enemy stat scaling (applied to every enemy spawned on this floor).
var health_mult: float = 1.0
var damage_mult: float = 1.0
## Chance that the last wave of a guard / arena fight also brings an ELITE enemy.
var elite_chance: float = 0.1
## Enemy table available on this floor (filtered by min_depth).
var enemy_pool: Array = []
var is_boss: bool = false
## Which boss guards the extraction room of this floor.
var boss_kind: StringName = &""
## How many special rooms of each family this floor has. Every one needs a dead end (one opening).
var boon_rooms: int = 3
var curse_rooms: int = 2
var elite_rooms: int = 1
var survival_rooms: int = 1
var hidden_chance: float = 0.7


## Dead ends the generator should try to give the floor: one for every special room, one for the
## extraction (boss) room, and a couple of plain guarded dead ends.
func wanted_dead_ends() -> int:
	return boon_rooms + curse_rooms + elite_rooms + survival_rooms + 2 + 2


static func for_depth(floor_number: int, duration_seconds: float = DEFAULT_DURATION) -> LevelConfig:
	var c := LevelConfig.new()
	var t := float(floor_number - 1)
	c.depth = floor_number
	c.duration = duration_seconds
	c.seed_value = maxi(randi(), 1)
	c.difficulty = 1.0 + 0.12 * t
	c.min_rooms = FIRST_FLOOR_ROOMS + ROOMS_PER_FLOOR * (floor_number - 1)
	c.max_rooms = c.min_rooms + 5
	c.guard_waves = mini(2 + int(t / 4.0), 4)
	c.arena_waves = mini(3 + int(t / 4.0), 5)
	c.guard_budget = int(50.0 * c.difficulty)
	c.arena_budget = int(45.0 * c.difficulty)
	c.max_arenas = 2 + int(t / 4.0)
	c.normal_budget_mult = c.difficulty
	c.trap_max_per_room = mini(3 + int(t / 5.0), 5)
	c.health_mult = 1.0 + 0.12 * t
	c.damage_mult = 1.0 + 0.06 * t
	c.elite_chance = clampf(0.1 + 0.04 * t, 0.1, 0.5)
	c.enemy_pool = ENEMIES.filter(func(e: Dictionary) -> bool: return e["min_depth"] <= floor_number)
	c.is_boss = floor_number >= FINAL_DEPTH
	c.boss_kind = RunData.BOSS_BY_FLOOR[clampi(floor_number, 1, FINAL_DEPTH) - 1]
	# a balance of boons and curses: always more boons than curses, both growing with depth
	c.boon_rooms = 3 + int(t / 3.0)
	c.curse_rooms = 2 + int(t / 4.0)
	c.elite_rooms = 1 + int(t / 3.0)
	c.survival_rooms = 1 + int(t / 5.0)
	c.hidden_chance = 0.7
	return c
