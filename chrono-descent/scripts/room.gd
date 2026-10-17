extends Node2D
class_name WFCRoom

## Fired once, the first time the player walks into this room.
signal player_entered(room: WFCRoom)

# Order matters: the generator treats 1 (OPEN) as an open door.
enum Socket { CLOSED, OPEN }

@export_group("Sockets")
@export var top_socket: Socket = Socket.CLOSED
@export var bottom_socket: Socket = Socket.CLOSED
@export var left_socket: Socket = Socket.CLOSED
@export var right_socket: Socket = Socket.CLOSED

@export_group("Flags")
@export var is_spawn_room: bool = false
@export var is_extraction_room: bool = false

@export_group("Director")
## How much threat budget this room can absorb at depth 1.
@export var room_threat_cost: int = 10
## Roles the director may give this room: &"empty", &"combat", &"shrine", &"vault", &"arena", &"ambush"...
@export var allowed_roles: Array[StringName] = [&"empty", &"combat"]
## Free labels to filter on: &"closet", &"arena", &"vault", &"vertical", &"large", &"breather"...
@export var tags: Array[StringName] = []
## Physics layer(s) the player is on. Used by the entry trigger.
@export_flags_2d_physics var trigger_mask: int = 1

@export_group("Generator hints (not read by the generator yet)")
## Room only appears at or after this level.
@export var min_level: int = 1
## Relative pick chance, for anti-repetition later.
@export var spawn_weight: float = 1.0

@export_group("Spawning")
## Enemies, traps, chests and items keep at least this far (pixels) from every doorway.
@export var door_clearance: float = 144.0

# Filled in by the director.
var role: StringName = &"empty"
var depth: int = 0
var visited: bool = false
var fade_tween: Tween

var _slots: Array[RoomSlot] = []

@onready var debug_label = get_node_or_null("DebugLabel")
@onready var terrain: TileMapLayer = $Terrain

func _ready() -> void:
	# Hide the room by default for the Fog of War effect
	terrain.modulate.a = 0.0
	
	for n in find_children("*", "Marker2D", true, false):
		if n is RoomSlot:
			_slots.append(n)
			
	if debug_label:
		debug_label.visible = OS.is_debug_build()
		debug_label.text = scene_file_path.get_file().get_basename()
		
	_build_entry_trigger()

# ------------------------------------------------------------ director API ---

func get_slots(kind: RoomSlot.Kind, free_only: bool = true) -> Array[RoomSlot]:
	var result: Array[RoomSlot] = []
	for s in _slots:
		if s.kind == kind and not (free_only and s.used):
			result.append(s)
	return result

func has_slot(kind: RoomSlot.Kind, min_footprint: RoomSlot.Footprint = RoomSlot.Footprint.SMALL) -> bool:
	for s in get_slots(kind):
		if s.footprint >= min_footprint:
			return true
	return false

func can_be(wanted_role: StringName) -> bool:
	return wanted_role in allowed_roles

func has_tag(tag: StringName) -> bool:
	return tag in tags

func get_open_port_names() -> Array[String]:
	var result: Array[String] = []
	if top_socket == Socket.OPEN: result.append("TopPort")
	if right_socket == Socket.OPEN: result.append("RightPort")
	if bottom_socket == Socket.OPEN: result.append("BottomPort")
	if left_socket == Socket.OPEN: result.append("LeftPort")
	return result

# ---------------------------------------------------------------- trigger ---

func _build_entry_trigger() -> void:
	var bounds = get_node_or_null("Bounds")
	
	if bounds == null:
		print("CRITICAL: Room '", name, "' has no ReferenceRect named 'Bounds' (check spelling and capitalization!). Trigger aborted.")
		return
		
	var shape := RectangleShape2D.new()
	shape.size = bounds.size - Vector2(16, 16) 
	
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = bounds.position + (bounds.size * 0.5)
	
	var area := Area2D.new()
	area.name = "EntryTrigger"
	area.collision_layer = 0
	area.collision_mask = trigger_mask
	area.monitorable = false
	
	area.add_child(col)
	add_child(area)
	
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	
	print("SUCCESS: Built trigger for '", name, "' at position ", col.position, " with size ", shape.size)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# Smoothly fade the room into full visibility
	var tween = create_tween()
	tween.tween_property(terrain, "modulate:a", 1.0, 0.3)
	
	if not visited:
		visited = true
		player_entered.emit(self)
		# Wake up all enemies in the spawned folder
		var spawn_folder = get_node_or_null("Spawned")
		if spawn_folder:
			for child in spawn_folder.get_children():
				if child.has_method("wake_up"):
					child.wake_up()

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# Dim the room to 30% visibility when the player leaves
	var tween = create_tween()
	tween.tween_property(terrain, "modulate:a", 0.3, 0.3)

# ------------------------------------------------------- existing helpers ---

func get_global_bounds() -> Rect2:
	var bounds_node = get_node_or_null("Bounds")
	if bounds_node:
		return bounds_node.get_global_rect()
	printerr("Room is missing a Bounds ReferenceRect!")
	return Rect2()

func block_port(port_name: String) -> void:
	var port_node = get_node_or_null(port_name)
	if not port_node:
		return
	var var_name = port_name.replace("Port", "").to_lower() + "_socket"
	set(var_name, Socket.CLOSED)

	var wall_block = ColorRect.new()
	wall_block.color = Color(1, 0, 0, 0.8)
	wall_block.size = Vector2(64, 64)
	wall_block.position = port_node.position - (wall_block.size / 2.0)
	add_child(wall_block)
	print("Sealed blocked port: ", port_name, " in ", self.name)


# ------------------------------------------------------------ spawn points ---
# Everything that needs a position inside a room (enemies, traps, chests, items) asks the room,
# so the placement rules live in ONE place:
#   - anywhere inside the room's full bounds (not just a few hand-placed markers),
#   - only on free floor, with a margin from walls and collidable props (so nothing spawns stuck),
#   - never close to a doorway.
# Spawn points can also be authored by hand: put a RoomSlot (kind + tags) in the Slots node.

const DOOR_WIDTH_PX: float = 96.0   # 6 tiles, the doorway convention of the room templates
const DOOR_HEIGHT_PX: float = 64.0  # 4 tiles
const TILE_PX: float = 16.0


## World-space centre of every open doorway.
func get_door_centers() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for door in get_door_info():
		result.append(door["center"])
	return result


## Every open doorway as {center: world position of the gap's middle, dir: 0 top / 1 right /
## 2 bottom / 3 left, inward: unit vector pointing from the doorway into the room}.
func get_door_info() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var names: Array[String] = ["TopPort", "RightPort", "BottomPort", "LeftPort"]
	var inward: Array[Vector2] = [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	for port_name in get_open_port_names():
		var port := get_node_or_null(port_name) as Node2D
		var dir := names.find(port_name)
		if port == null or dir < 0:
			continue
		# Top/bottom ports sit at the right end of the gap, side ports at its bottom end.
		var offset := Vector2(-DOOR_WIDTH_PX * 0.5, 0.0) if dir == 0 or dir == 2 else Vector2(0.0, -DOOR_HEIGHT_PX * 0.5)
		result.append({"center": port.global_position + offset, "dir": dir, "inward": inward[dir]})
	return result


func get_area_in_tiles() -> float:
	var size := get_global_bounds().size
	return (size.x * size.y) / (TILE_PX * TILE_PX)


func is_dead_end() -> bool:
	return get_open_port_names().size() == 1


## How many enemies this room can hold comfortably (about one per 90 floor tiles).
func get_enemy_capacity() -> int:
	return clampi(int(get_area_in_tiles() / 90.0), 2, 8)


## True when the tile is floor and has no collidable prop on it.
func is_walkable_cell(cell: Vector2i) -> bool:
	var data := terrain.get_cell_tile_data(cell)
	if data == null or data.get_collision_polygons_count(0) > 0:
		return false
	var props := get_node_or_null("Terrain/Props") as TileMapLayer
	if props:
		var prop_data := props.get_cell_tile_data(cell)
		if prop_data and prop_data.get_collision_polygons_count(0) > 0:
			return false
	return true


## A point is valid when it and its surrounding cells (margin_cells) are free floor and it is at
## least clearance pixels from every doorway (negative clearance = use door_clearance).
func is_valid_spawn_point(world_pos: Vector2, margin_cells: int = 1, clearance: float = -1.0) -> bool:
	if clearance < 0.0:
		clearance = door_clearance
	var cell := terrain.local_to_map(terrain.to_local(world_pos))
	for dx in range(-margin_cells, margin_cells + 1):
		for dy in range(-margin_cells, margin_cells + 1):
			if not is_walkable_cell(cell + Vector2i(dx, dy)):
				return false
	for door in get_door_centers():
		if world_pos.distance_to(door) < clearance:
			return false
	return true


## Picks up to `count` random valid points over the room's FULL bounds, snapped to tile centres,
## at least min_spacing apart from each other and from every point in `avoid`.
func find_spawn_points(count: int, min_spacing: float, avoid: Array = [], margin_cells: int = 1, clearance: float = -1.0) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var area := get_global_bounds().grow(-TILE_PX)
	if count <= 0 or area.size.x <= 0.0 or area.size.y <= 0.0:
		return result
	var tries := 0
	while result.size() < count and tries < count * 120:
		tries += 1
		var raw := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		var p := terrain.to_global(terrain.map_to_local(terrain.local_to_map(terrain.to_local(raw))))
		if not is_valid_spawn_point(p, margin_cells, clearance):
			continue
		if _is_too_close(p, result, min_spacing) or _is_too_close(p, avoid, min_spacing):
			continue
		result.append(p)
	return result


## A free floor spot in the room as close as possible to `wanted` (props and walls are avoided). Used to put things
## back where they belong when the room is a different variant than before.
func nearest_free_point(wanted: Vector2, margin_cells: int = 1) -> Vector2:
	if is_valid_spawn_point(wanted, margin_cells, 0.0):
		return wanted
	for radius in range(16, 240, 16):
		for i in 12:
			var candidate := wanted + Vector2.RIGHT.rotated(TAU * float(i) / 12.0) * float(radius)
			if is_valid_spawn_point(candidate, margin_cells, 0.0):
				return candidate
	return get_global_bounds().get_center()


## Creates RoomSlot markers (spawn points) on valid floor, so other systems can find them with
## get_slots(kind) / get_slots_tagged(tag). Typical use: kind HAZARD + tag "trap",
## kind LOOT + tag "chest" or "item".
func generate_slots(kind: RoomSlot.Kind, count: int, slot_tags: Array, min_spacing: float = 96.0, margin_cells: int = 1) -> Array[RoomSlot]:
	var created: Array[RoomSlot] = []
	var slots_root := get_node_or_null("Slots")
	if slots_root == null:
		return created
	for p in find_spawn_points(count, min_spacing, get_reserved_points(), margin_cells):
		var slot := RoomSlot.new()
		slot.kind = kind
		slot.tags.assign(slot_tags)
		slots_root.add_child(slot)
		slot.global_position = p
		_slots.append(slot)
		created.append(slot)
	return created


func get_slots_tagged(tag: StringName, free_only: bool = true) -> Array[RoomSlot]:
	var result: Array[RoomSlot] = []
	for s in _slots:
		if s.tags.has(tag) and not (free_only and s.used):
			result.append(s)
	return result


## Positions of every non-enemy spawn point (so new spawns keep away from them).
func get_reserved_points() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for s in _slots:
		if s.kind != RoomSlot.Kind.ENEMY:
			result.append(s.global_position)
	return result


func _is_too_close(p: Vector2, list: Array, distance: float) -> bool:
	for other in list:
		if p.distance_to(other) < distance:
			return true
	return false
