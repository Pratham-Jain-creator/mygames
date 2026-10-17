class_name LevelGenerator
extends Node2D

## WFC-style dungeon generator for rooms of DIFFERENT sizes. A reusable component: the Levels
## manager calls generate() whenever a floor is built or rebuilt.
##
## - Every open door (port) with no room behind it yet is a "cell" to collapse.
## - Its possible values are the templates whose matching socket is OPEN, that
##   fit without overlapping any placed room, and whose other doors don't open
##   into a wall.
## - Each step collapses the door with the FEWEST options (lowest entropy), then
##   forward-checks that every other open door still has at least one option
##   (constraint propagation). If a door ends up with zero options, the whole
##   attempt is thrown away and retried.
## - Nothing is instantiated until the layout is finished, so a failed attempt
##   leaves no orphan rooms behind.
##
## What generation starts from: ONE start room, picked from a pool of start rooms. Every floor uses a
## single start room, but the pool has several, so the arrival room changes as you descend.

@export_dir var templates_directory: String = "res://scenes/rooms/templates"
## The pool of possible start rooms. Each floor picks exactly one. Set by the Levels manager.
@export var start_room_scenes: Array[PackedScene] = []
## Higher = rooms with more doors are favoured while under the room budget.
@export_range(0.0, 4.0, 0.1) var branching_bias: float = 1.0
@export var max_attempts: int = 120

const OPEN: int = 1
const PORT_NAMES = ["TopPort", "RightPort", "BottomPort", "LeftPort"]
const SOCKET_VARS = ["top_socket", "right_socket", "bottom_socket", "left_socket"]
const DIRS = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const SNAP: float = 2.0       # two ports closer than this count as the same door
const PROBE: float = 4.0      # how far outside a door we look for a wall
const MAX_STEPS: int = 400

class RoomData:
	var scene: PackedScene
	var sockets := PackedInt32Array([0, 0, 0, 0]) # top, right, bottom, left
	var port_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var open_count: int = 0
	var bounds := Rect2()
	var is_spawn: bool = false
	var is_extraction: bool = false
	var valid: bool = true


class Placed:
	var tile: int
	var origin: Vector2
	var rect: Rect2          # world-space Bounds, shrunk by 1px for overlap tests
	var depth: int = 0
	var entry_dir: int = -1  # which of its own doors it was attached through



class OpenPort:
	var room: Placed
	var dir: int
	var pos: Vector2


var tiles: Array[RoomData] = []        # indices [0, start_count) = the start-room pool
var start_count: int = 0
var pool: Array[int] = []              # tiles used in normal generation
var extraction_tiles: Array[int] = []  # only used in the post-pass
var _loaded: bool = false
var _min_rooms: int = 8
var _max_rooms: int = 15
var _cfg: LevelConfig


# ---------------------------------------------------------------- loading ---

func ensure_templates() -> bool:
	if _loaded:
		return true
	if start_room_scenes.is_empty():
		printerr("CRITICAL ERROR: start_room_scenes is empty.")
		return false
	tiles.clear()
	pool.clear()
	extraction_tiles.clear()
	start_count = start_room_scenes.size()
	for scene in start_room_scenes:
		var data := read_room_data(scene)
		if not data.valid:
			printerr("CRITICAL ERROR: start room %s needs a Bounds node and a port for every OPEN socket." % scene.resource_path)
			return false
		tiles.append(data)

	var dir := DirAccess.open(templates_directory)
	if dir == null:
		printerr("Cannot open templates directory: ", templates_directory)
		return false
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var clean_name := file_name.trim_suffix(".remap") # exported builds
			if clean_name.ends_with(".tscn"):
				var scene := load(templates_directory + "/" + clean_name) as PackedScene
				if scene:
					register_template(scene)
		file_name = dir.get_next()
	dir.list_dir_end()
	_loaded = not pool.is_empty()
	if not _loaded:
		printerr("CRITICAL ERROR: no usable room templates in ", templates_directory)
	return _loaded


func register_template(scene: PackedScene) -> void:
	var data := read_room_data(scene)
	if data.is_spawn or not data.valid:
		return
	tiles.append(data)
	var index := tiles.size() - 1
	if data.is_extraction:
		extraction_tiles.append(index)
	else:
		pool.append(index)


## Measures the scene ONCE while it is inside the tree (so global transforms,
## scale and anchors are valid), using the room's own get_global_bounds() and
## its Marker2D ports. Everything is stored as plain offsets from the room's
## origin, so all later placement is simple vector math with no engine updates.
func read_room_data(scene: PackedScene) -> RoomData:
	var data := RoomData.new()
	data.scene = scene
	var inst: Node2D = scene.instantiate() as Node2D
	if inst == null:
		data.valid = false
		push_warning("%s: root node must be a Node2D. Skipped." % scene.resource_path)
		return data

	inst.process_mode = Node.PROCESS_MODE_DISABLED
	inst.visible = false
	add_child(inst)
	inst.position = Vector2.ZERO

	for d in 4:
		var value = inst.get(SOCKET_VARS[d])
		data.sockets[d] = 1 if value == OPEN else 0
		if data.sockets[d] == OPEN:
			var port = inst.get_node_or_null(PORT_NAMES[d])
			if port == null:
				data.valid = false
				push_warning("%s: %s is OPEN but there is no %s node. Skipped." \
						% [scene.resource_path, SOCKET_VARS[d], PORT_NAMES[d]])
			else:
				data.port_pos[d] = to_local(port.global_position)
				data.open_count += 1

	var g_rect := Rect2()
	if inst.has_method("get_global_bounds"):
		g_rect = inst.call("get_global_bounds")
	else:
		var bounds = inst.get_node_or_null("Bounds")
		if bounds:
			g_rect = bounds.get_global_rect()
	if g_rect.size == Vector2.ZERO:
		data.valid = false
		push_warning("%s has no usable Bounds. Skipped." % scene.resource_path)
	else:
		var top_left := to_local(g_rect.position)
		data.bounds = Rect2(top_left, to_local(g_rect.end) - top_left)

	data.is_spawn = inst.get("is_spawn_room") == true
	data.is_extraction = inst.get("is_extraction_room") == true
	remove_child(inst)
	inst.free()
	return data


# ------------------------------------------------------------- generation ---

## Builds a floor. Rooms are instantiated as children of `parent`.
## Returns {rooms, new_rooms, start_rooms, extraction_room}, or {} when generation failed.
func generate(config: LevelConfig, parent: Node2D) -> Dictionary:
	if not ensure_templates():
		return {}
	_cfg = config
	_min_rooms = config.min_rooms
	_max_rooms = config.max_rooms
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed_value
	var seeds: Array = _start_room_seeds(config, rng)
	if seeds.is_empty():
		return {}

	var best: Array = []
	var best_miss: int = 1 << 30
	var wanted_dead_ends := config.wanted_dead_ends()
	for attempt in max_attempts:
		var result := try_generate(rng, seeds)
		if result.is_empty():
			continue # contradiction, retry
		var n := result.size()
		var miss := maxi(maxi(_min_rooms - n, n - _max_rooms), 0)
		# special rooms (and the boss room) each need a dead end: a layout with too few is a worse layout
		var dead_ends := 0
		for p in result:
			if p.tile >= start_count and tiles[p.tile].open_count == 1:
				dead_ends += 1
		miss += maxi(wanted_dead_ends - dead_ends, 0)
		if miss < best_miss:
			best = result
			best_miss = miss
		if miss == 0:
			break

	if best.is_empty():
		printerr("Floor %d: generation failed (%d attempts)." % [config.depth, max_attempts])
		return {}

	var has_extraction := false
	for p in best:
		if tiles[p.tile].is_extraction:
			has_extraction = true
	if not has_extraction:
		place_extraction(best)

	var out := spawn_rooms(best, parent)
	print("Floor %d: %d rooms (wanted %d-%d), seed %d" % [config.depth, best.size(), _min_rooms, _max_rooms, config.seed_value])
	populate_dungeon(out["new_rooms"])
	return out


## Seeds for a brand-new floor: ONE start room from the pool. The Levels manager sets
## config.start_index so consecutive floors start in different rooms; if it is not set, a
## random one is used.
func _start_room_seeds(config: LevelConfig, rng: RandomNumberGenerator) -> Array:
	var index := config.start_index
	if index < 0 or index >= start_count:
		index = rng.randi() % start_count
	config.start_index = index
	return [{"tile": index, "origin": Vector2.ZERO, "depth": 0}]


## One WFC run. Returns the list of Placed rooms, or [] on contradiction.
func try_generate(rng: RandomNumberGenerator, seeds: Array) -> Array:
	var placed: Array = []
	var open_ports: Array = []
	for s in seeds:
		var p := Placed.new()
		p.tile = s["tile"]
		p.origin = s["origin"]
		p.depth = s["depth"]
		p.rect = Rect2(p.origin + tiles[p.tile].bounds.position, tiles[p.tile].bounds.size).grow(-1.0)
		placed.append(p)
		add_open_ports(p, open_ports, [])

	var steps: int = 0
	while not open_ports.is_empty():
		steps += 1
		if steps > MAX_STEPS:
			return []

		# OBSERVE: pick the open door with the fewest options (lowest entropy).
		var chosen: OpenPort = null
		var chosen_cands: Array = []
		var lowest: int = 1 << 30
		var ties: int = 0
		for p in open_ports:
			var cands := get_candidates(p, placed, open_ports)
			if cands.is_empty():
				return [] # contradiction
			if cands.size() < lowest:
				lowest = cands.size()
				ties = 1
				chosen = p
				chosen_cands = cands
			elif cands.size() == lowest:
				ties += 1
				if rng.randi() % ties == 0:
					chosen = p
					chosen_cands = cands

		# Near the room budget, prefer dead ends so the dungeon closes off.
		var over_budget := (placed.size() + open_ports.size()) >= _max_rooms
		if over_budget:
			var dead: Array = chosen_cands.filter(func(c): return tiles[c["tile"]].open_count == 1)
			if not dead.is_empty():
				chosen_cands = dead

		# COLLAPSE: weighted random order, take the first that survives propagation.
		for c in chosen_cands:
			var w: float = 1.0 + branching_bias * c["growth"]
			if over_budget:
				w = 1.0 / (1.0 + c["growth"])
			c["key"] = pow(rng.randf(), 1.0 / w)
		chosen_cands.sort_custom(func(a, b): return a["key"] > b["key"])

		var accepted := false
		for c in chosen_cands:
			var saved_ports := open_ports.duplicate()
			commit(c, chosen, placed, open_ports)
			# PROPAGATE: every remaining open door must still be fillable.
			if forward_check(placed, open_ports):
				accepted = true
				break
			placed.pop_back() # undo
			open_ports = saved_ports
		if not accepted:
			return []

	return placed


## All templates that can legally fill this door right now.
func get_candidates(port: OpenPort, placed: Array, open_ports: Array, first_only: bool = false) -> Array:
	var result: Array = []
	var in_dir: int = (port.dir + 2) % 4
	for t in pool:
		var data: RoomData = tiles[t]
		if data.sockets[in_dir] != OPEN:
			continue
		# Snap this room's matching door onto the open door.
		var origin: Vector2 = port.pos - data.port_pos[in_dir]
		var rect := Rect2(origin + data.bounds.position, data.bounds.size).grow(-1.0)
		if overlaps_any(rect, placed):
			continue

		# Its other doors must either meet an existing open door or face free space.
		var links := {}
		var ok := true
		for d in 4:
			if d == in_dir or data.sockets[d] != OPEN:
				continue
			var pos: Vector2 = origin + data.port_pos[d]
			var partner := find_open_port(open_ports, pos, (d + 2) % 4, port)
			if partner:
				links[d] = partner
			elif point_in_any(pos + DIRS[d] * PROBE, placed):
				ok = false # door would open into a wall
				break
		if not ok:
			continue

		result.append({
			"tile": t,
			"origin": origin,
			"rect": rect,
			"links": links,
			"growth": data.open_count - 1 - links.size(),
		})
		if first_only:
			break
	return result


func commit(c: Dictionary, port: OpenPort, placed: Array, open_ports: Array) -> void:
	var room := Placed.new()
	room.tile = c["tile"]
	room.origin = c["origin"]
	room.rect = c["rect"]
	room.depth = port.room.depth + 1
	room.entry_dir = (port.dir + 2) % 4
	placed.append(room)

	open_ports.erase(port)
	var links: Dictionary = c["links"]
	var skip: Array = links.keys()
	skip.append(room.entry_dir)
	for d in links:
		open_ports.erase(links[d]) # two doors meet: both are now satisfied
	add_open_ports(room, open_ports, skip)


func add_open_ports(room: Placed, open_ports: Array, skip: Array) -> void:
	var data: RoomData = tiles[room.tile]
	for d in 4:
		if d in skip or data.sockets[d] != OPEN:
			continue
		var op := OpenPort.new()
		op.room = room
		op.dir = d
		op.pos = room.origin + data.port_pos[d]
		open_ports.append(op)


func forward_check(placed: Array, open_ports: Array) -> bool:
	for p in open_ports:
		if get_candidates(p, placed, open_ports, true).is_empty():
			return false
	return true


func find_open_port(open_ports: Array, pos: Vector2, dir: int, exclude: OpenPort) -> OpenPort:
	for p in open_ports:
		if p != exclude and p.dir == dir and p.pos.distance_to(pos) < SNAP:
			return p
	return null


func overlaps_any(rect: Rect2, placed: Array) -> bool:
	for r in placed:
		if rect.intersects(r.rect):
			return true
	return false


func point_in_any(point: Vector2, placed: Array) -> bool:
	for r in placed:
		if r.rect.has_point(point):
			return true
	return false


## Swaps the dead end farthest from the start for an extraction room with the
## same socket layout, if one fits there without overlapping anything.
func place_extraction(placed: Array) -> void:
	if extraction_tiles.is_empty():
		return
	var order := placed.duplicate()
	order.sort_custom(func(a, b): return a.depth > b.depth)
	for room in order:
		var data: RoomData = tiles[room.tile]
		# Never replace a start room.
		if room.tile < start_count or data.open_count != 1:
			continue
		var d: int = room.entry_dir
		var entry_pos: Vector2 = room.origin + data.port_pos[d]
		for t in extraction_tiles:
			var ex: RoomData = tiles[t]
			if ex.sockets != data.sockets:
				continue
			var origin: Vector2 = entry_pos - ex.port_pos[d]
			var rect := Rect2(origin + ex.bounds.position, ex.bounds.size).grow(-1.0)
			var clear := true
			for other in placed:
				if other != room and rect.intersects(other.rect):
					clear = false
					break
			if clear:
				room.tile = t
				room.origin = origin
				room.rect = rect
				return
	push_warning("No extraction room fits any dead end in this layout.")


# ----------------------------------------------------------------- output ---

func spawn_rooms(placed: Array, parent: Node2D) -> Dictionary:
	var all_rooms: Array[WFCRoom] = []
	var new_rooms: Array[WFCRoom] = []
	var start_rooms: Array[WFCRoom] = []
	var extraction_room: WFCRoom = null
	for p in placed:
		var data: RoomData = tiles[p.tile]
		var room := data.scene.instantiate() as WFCRoom
		parent.add_child(room)
		room.position = p.origin
		new_rooms.append(room)
		all_rooms.append(room)
		if p.tile < start_count:
			start_rooms.append(room)
		if data.is_extraction:
			extraction_room = room
	return {"rooms": all_rooms, "new_rooms": new_rooms, "start_rooms": start_rooms, "extraction_room": extraction_room}


# --- spawning (positions come from WFCRoom's spawn-point rules: full bounds, free floor, away from doors)
const ENEMY_MIN_SPACING: float = 80.0
const TRAP_MIN_SPACING: float = 96.0
const CHEST_SCENE: String = "res://scenes/props/chest.tscn"
const GAUNTLET_SCRIPT: Script = preload("res://scripts/gauntlet_controller.gd")

## Trap shapes. Each is a scene in scenes/props/traps/; add a new one here to put it in rotation.
const TRAP_PATTERNS: Array = [
	{"path": "res://scenes/props/traps/pattern_single.tscn", "weight": 3.0},
	{"path": "res://scenes/props/traps/pattern_line_h.tscn", "weight": 2.0},
	{"path": "res://scenes/props/traps/pattern_line_v.tscn", "weight": 2.0},
	{"path": "res://scenes/props/traps/pattern_block.tscn", "weight": 2.0},
	{"path": "res://scenes/props/traps/pattern_cross.tscn", "weight": 1.5},
	{"path": "res://scenes/props/traps/pattern_diagonal.tscn", "weight": 1.5},
	{"path": "res://scenes/props/traps/pattern_lane.tscn", "weight": 1.5},
	{"path": "res://scenes/props/traps/pattern_checker.tscn", "weight": 1.0},
	{"path": "res://scenes/props/traps/pattern_ring.tscn", "weight": 1.0},
]
const ARENA_MIN_TILES: float = 700.0


## Picks an enemy that fits the budget from this floor's unlocked enemy pool.
func pick_enemy(budget: int) -> Dictionary:
	var options: Array = _cfg.enemy_pool.filter(func(e): return e["cost"] <= budget)
	if options.is_empty():
		return {}
	var total := 0.0
	for e in options:
		total += e["weight"]
	var roll := randf() * total
	for e in options:
		roll -= e["weight"]
		if roll <= 0.0:
			return e
	return options[0]


## Fills freshly generated rooms (anchors are skipped: they are safe rooms / the boss room, set up by Levels).
## 1. every special room (boon, curse, hidden, elite, time survivors) is planned onto a dead end (one opening) or a big room,
## 2. the remaining dead ends and a few big rooms become wave gauntlets with a reward chest,
## 3. everything else gets traps and a few enemies.
func populate_dungeon(rooms: Array) -> void:
	for node in rooms:
		if node is WFCRoom:
			_remove_barrel_tiles(node)
	var plan := _plan_special_rooms(rooms)
	var gauntlets := _choose_gauntlet_rooms(rooms, plan)
	for node in rooms:
		var room := node as WFCRoom
		if room == null or room.is_spawn_room or room.is_extraction_room:
			continue
		if plan.has(room):
			SpecialRooms.attach(room, plan[room], _cfg, self)
		elif gauntlets.has(room):
			_setup_gauntlet(room, gauntlets[room])
		else:
			# Static content first, so enemies are then placed around it (they keep away from it).
			_place_traps(room)
			_place_enemies(room)


## The barrel tile of the dungeon tileset. Barrels painted into the rooms are not part of this game: they are erased.
const BARREL_TILE: Vector2i = Vector2i(8, 3)


func _remove_barrel_tiles(room: WFCRoom) -> void:
	for layer: TileMapLayer in room.find_children("*", "TileMapLayer", true, false):
		for cell in layer.get_used_cells():
			if layer.get_cell_atlas_coords(cell) == BARREL_TILE:
				layer.erase_cell(cell)


## Decides which room becomes which special room. Returns {WFCRoom: kind}. Dead ends are the only rooms with ONE
## opening, which is what boon / curse / hidden rooms need; the kinds come from SpecialRooms.plan_kinds in priority
## order, so when a layout has too few dead ends the least important ones are dropped.
func _plan_special_rooms(rooms: Array) -> Dictionary:
	var plan := {}
	var dead_ends: Array[WFCRoom] = []
	var big_rooms: Array[WFCRoom] = []
	for node in rooms:
		var room := node as WFCRoom
		if room == null or room.is_spawn_room or room.is_extraction_room:
			continue
		if room.is_dead_end():
			dead_ends.append(room)
		elif room.get_area_in_tiles() >= ARENA_MIN_TILES:
			big_rooms.append(room)
	dead_ends.shuffle()
	big_rooms.shuffle()
	for kind in SpecialRooms.plan_kinds(_cfg):
		var room: WFCRoom = null
		if SpecialRooms.prefers_big_room(kind) and not big_rooms.is_empty():
			room = big_rooms.pop_back()
		elif not dead_ends.is_empty():
			# keep one dead end for a plain guarded gauntlet when we can
			room = dead_ends.pop_back()
		if room != null:
			plan[room] = kind
	return plan


## Decides which rooms become gauntlets: every dead end that is not a special room ("guard") plus a few big rooms
## ("arena").
func _choose_gauntlet_rooms(rooms: Array, plan: Dictionary) -> Dictionary:
	var result := {}
	var arena_candidates: Array[WFCRoom] = []
	for node in rooms:
		var room := node as WFCRoom
		if room == null or room.is_spawn_room or room.is_extraction_room or plan.has(room):
			continue
		if room.is_dead_end():
			result[room] = "guard"
		elif room.get_area_in_tiles() >= ARENA_MIN_TILES:
			if room.allowed_roles.has(&"arena") or randf() < _cfg.arena_chance:
				arena_candidates.append(room)
	arena_candidates.shuffle()
	for i in mini(arena_candidates.size(), _cfg.max_arenas):
		result[arena_candidates[i]] = "arena"
	return result


## Locks the reward chest, then lets a GauntletController run the fight when the player enters.
func _setup_gauntlet(room: WFCRoom, kind: String) -> void:
	var chest_pos := Vector2.ZERO
	var found := false
	# Dead ends have an authored reward spot at the far end; arenas use a clear spot in the open.
	for slot in room.get_slots(RoomSlot.Kind.LOOT, true):
		if not slot.tags.has(&"item") and room.is_valid_spawn_point(slot.global_position, 2):
			chest_pos = slot.global_position
			slot.used = true
			found = true
			break
	if not found:
		var points := room.find_spawn_points(1, 0.0, room.get_reserved_points(), 2, 200.0)
		if not points.is_empty():
			chest_pos = points[0]
			found = true
	var chests: Array = []
	if found:
		var chest := _spawn_into(room, CHEST_SCENE, chest_pos, {"locked": true})
		if chest:
			chests.append(chest)
	var waves := _cfg.guard_waves if kind == "guard" else _cfg.arena_waves
	var budget := _cfg.guard_budget if kind == "guard" else _cfg.arena_budget
	var controller := GAUNTLET_SCRIPT.new() as Node
	controller.name = "Gauntlet"
	room.add_child(controller)
	controller.setup(room, waves, budget, Callable(self, "pick_enemy"), Callable(self, "_spawn_enemy"), chests)
	controller.elite_chance = _cfg.elite_chance


## Spends the room's threat budget on enemies and places them anywhere inside the room's full
## bounds, on free floor (not in walls/props), away from doorways and from traps/items.
func _place_enemies(room: WFCRoom) -> void:
	var budget: int = int(room.room_threat_cost * _cfg.normal_budget_mult)
	var plan: Array[Dictionary] = []
	while plan.size() < room.get_enemy_capacity():
		var choice := pick_enemy(budget)
		if choice.is_empty():
			break
		plan.append(choice)
		budget -= choice["cost"]
	var points := room.find_spawn_points(plan.size(), ENEMY_MIN_SPACING, room.get_reserved_points())
	if points.size() < plan.size():
		push_warning("%s: only %d of %d enemies found a valid spawn point." % [room.name, points.size(), plan.size()])
	for i in mini(plan.size(), points.size()):
		_spawn_enemy(room, plan[i]["path"], points[i])


## Spawns an enemy scaled to this floor's difficulty (health and damage multipliers).
func _spawn_enemy(room: WFCRoom, scene_path: String, world_pos: Vector2, properties: Dictionary = {}) -> Node2D:
	var props := properties.duplicate()
	props["health_multiplier"] = _cfg.health_mult
	props["damage_multiplier"] = _cfg.damage_mult
	return _spawn_into(room, scene_path, world_pos, props)


## Traps are HAZARD spawn points; each one gets a randomly chosen pattern that fits on free floor.
func _place_traps(room: WFCRoom) -> void:
	var trap_max := clampi(int(room.get_area_in_tiles() / 250.0), 0, _cfg.trap_max_per_room)
	for slot in room.generate_slots(RoomSlot.Kind.HAZARD, randi_range(0, trap_max), [&"trap"], TRAP_MIN_SPACING + 16.0, 2):
		_spawn_trap_pattern(room, slot.global_position)
		slot.used = true


func _spawn_trap_pattern(room: WFCRoom, origin: Vector2) -> void:
	var scored: Array = []
	for entry in TRAP_PATTERNS:
		scored.append({"entry": entry, "key": pow(randf(), 1.0 / entry["weight"])})
	scored.sort_custom(func(a, b): return a["key"] > b["key"])
	for item in scored:
		var scene := load(item["entry"]["path"]) as PackedScene
		var pattern := scene.instantiate() as Node2D
		var fits := true
		for p in pattern.get_tile_positions(origin):
			if not room.is_valid_spawn_point(p, 0):
				fits = false
				break
		if fits:
			room.get_node("Spawned").add_child(pattern)
			pattern.global_position = origin
			return
		pattern.free()


## Instantiates a scene inside the room's "Spawned" folder at a world position.
## properties are applied before the node enters the tree, so _ready() already sees them.
func _spawn_into(room: WFCRoom, scene_path: String, world_pos: Vector2, properties: Dictionary = {}) -> Node2D:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_warning("Cannot spawn missing scene: " + scene_path)
		return null
	var node := scene.instantiate() as Node2D
	for key in properties:
		node.set(key, properties[key])
	room.get_node("Spawned").add_child(node)
	node.global_position = world_pos
	return node
