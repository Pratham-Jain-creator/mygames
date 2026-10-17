extends Control
## HUD minimap. Starts completely black and reveals a room the first time the player enters it.
##
## What it shows
##  - Discovered rooms only (floor + outline), with a short fade-in when a room is revealed.
##  - Every open door ("gate") of a discovered room: amber + pulsing arrow = leads somewhere
##    unexplored, green = leads to a room you have already seen. So you always know which
##    exits are still worth trying.
##  - The start room (gold outline), the extraction room once found (cyan + diamond), and you.
##
## Controls: the "toggle_map" action switches between LOCAL (follows the player) and OVERVIEW
## (fits everything found).
##
## Setup: the HUD calls setup() with the generated rooms and the node to track.
## Drawing happens in "map units" scaled by PX, which gives the chunky pixel-art look.

signal discovery_changed(discovered: int, total: int)

enum ZoomMode { LOCAL, OVERVIEW }

## Screen pixels per map unit.
const PX: int = 3
const MAP_UNITS: Vector2 = Vector2(72, 54)
## Map units per world pixel while following the player.
const LOCAL_SCALE: float = 0.06
const MAX_OVERVIEW_SCALE: float = 0.06
const OVERVIEW_MARGIN_UNITS: float = 5.0
const REVEAL_TIME: float = 0.6
## Door gap sizes in world pixels (6 / 4 tiles of 16px, the room-template convention).
const DOOR_W_PX: float = 96.0
const DOOR_H_PX: float = 64.0
const DIRS: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const PORT_NAMES: Array[String] = ["TopPort", "RightPort", "BottomPort", "LeftPort"]

const COL_BG := Color(0.0, 0.0, 0.0, 0.95)
const COL_FRAME := Color(0.45, 0.32, 0.38)
const COL_FLOOR := Color(0.17, 0.11, 0.22)
const COL_WALL := Color(0.60, 0.43, 0.37)
const COL_START := Color(0.96, 0.78, 0.35)
const COL_EXIT := Color(0.35, 0.85, 1.0)
const COL_DOOR_SEEN := Color(0.40, 0.90, 0.50)
const COL_DOOR_NEW := Color(1.0, 0.72, 0.18)
const COL_PLAYER := Color(1.0, 1.0, 1.0)
const COL_GAUNTLET := Color(0.95, 0.25, 0.25)

var _rooms: Array[Dictionary] = []
## Signal connections made to rooms, so a new setup() (new floor / rebuild) can cleanly drop them.
var _connections: Array[Dictionary] = []
var _tracked: Node2D
var _zoom_mode: ZoomMode = ZoomMode.LOCAL
var _center: Vector2 = Vector2.ZERO
var _scale: float = LOCAL_SCALE
var _clock: float = 0.0


func _ready() -> void:
	custom_minimum_size = MAP_UNITS * PX
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## rooms: every WFCRoom of the dungeon. tracked: the node whose position is the "you are here" dot.
func setup(rooms: Array, tracked: Node2D) -> void:
	clear()
	_tracked = tracked
	for node in rooms:
		var room := node as WFCRoom
		if room:
			_rooms.append(_make_entry(room))
	_link_neighbours()
	for i in _rooms.size():
		var room: WFCRoom = _rooms[i]["room"]
		var callable := _on_room_entered.bind(i)
		room.player_entered.connect(callable)
		_connections.append({"room": room, "callable": callable})
		if room.visited:
			_discover(i)
	discovery_changed.emit(discovered_count(), total_count())


## Scroll of Mapping: every room of the floor shows up.
func reveal_all() -> void:
	for i in _rooms.size():
		# a hidden room stays hidden even from the memory echo: it must be found
		if not _rooms[i]["hidden"]:
			_discover(i)


## Forgets the current floor (called before its rooms are freed, and by setup()).
func clear() -> void:
	for connection in _connections:
		var old_room = connection["room"]
		if is_instance_valid(old_room) and old_room.player_entered.is_connected(connection["callable"]):
			old_room.player_entered.disconnect(connection["callable"])
	_connections.clear()
	_rooms.clear()
	discovery_changed.emit(0, 0)


func discovered_count() -> int:
	var n := 0
	for e in _rooms:
		if e["seen"]:
			n += 1
	return n


func total_count() -> int:
	# hidden rooms are not counted until they have been found
	var n := 0
	for e in _rooms:
		if not e["hidden"] or e["seen"]:
			n += 1
	return n


# ------------------------------------------------------------------ data

func _make_entry(room: WFCRoom) -> Dictionary:
	var doors: Array[Dictionary] = []
	for port_name in room.get_open_port_names():
		var port := room.get_node_or_null(port_name) as Node2D
		if port:
			doors.append({"pos": port.global_position, "dir": PORT_NAMES.find(port_name), "to": -1})
	return {
		"room": room,
		"rect": room.get_global_bounds(),
		"doors": doors,
		"seen": false,
		"t": 0.0,
		"exit": room.is_extraction_room,
		"start": room.is_spawn_room,
		"hidden": room.has_meta("hidden"),
	}


## Works out which room each door leads to (probe a point just outside the gap).
func _link_neighbours() -> void:
	for i in _rooms.size():
		for door in _rooms[i]["doors"]:
			var probe: Vector2 = _door_center(door["pos"], door["dir"]) + DIRS[door["dir"]] * 8.0
			for j in _rooms.size():
				if j != i and (_rooms[j]["rect"] as Rect2).has_point(probe):
					door["to"] = j
					break


func _on_room_entered(_room: WFCRoom, index: int) -> void:
	_discover(index)


func _discover(index: int) -> void:
	if _rooms[index]["seen"]:
		return
	_rooms[index]["seen"] = true
	_rooms[index]["t"] = 0.0
	discovery_changed.emit(discovered_count(), total_count())


static func _door_center(pos: Vector2, dir: int) -> Vector2:
	# Top/bottom ports sit at the right end of the gap, side ports at the bottom end.
	if dir == 0 or dir == 2:
		return pos - Vector2(DOOR_W_PX * 0.5, 0.0)
	return pos - Vector2(0.0, DOOR_H_PX * 0.5)


# ------------------------------------------------------------------ input / update

## Bound to the "toggle_map" action (M on keyboard, Share on a Sony controller).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_map"):
		_zoom_mode = ZoomMode.OVERVIEW if _zoom_mode == ZoomMode.LOCAL else ZoomMode.LOCAL
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_clock += delta
	for e in _rooms:
		if e["seen"] and e["t"] < REVEAL_TIME:
			e["t"] += delta
	_update_view(delta)
	queue_redraw()


func _update_view(delta: float) -> void:
	var target_scale := LOCAL_SCALE
	var target_center := _tracked.global_position if is_instance_valid(_tracked) else _center
	if _zoom_mode == ZoomMode.OVERVIEW:
		var bounds := _discovered_bounds()
		if bounds.has_area():
			target_center = bounds.get_center()
			var fit := minf((MAP_UNITS.x - OVERVIEW_MARGIN_UNITS * 2.0) / bounds.size.x, (MAP_UNITS.y - OVERVIEW_MARGIN_UNITS * 2.0) / bounds.size.y)
			target_scale = minf(fit, MAX_OVERVIEW_SCALE)
	var k := minf(1.0, delta * 8.0)
	_scale = lerpf(_scale, target_scale, k)
	_center = target_center if _zoom_mode == ZoomMode.LOCAL else _center.lerp(target_center, k)


func _discovered_bounds() -> Rect2:
	var bounds := Rect2()
	var first := true
	for e in _rooms:
		if not e["seen"]:
			continue
		bounds = (e["rect"] as Rect2) if first else bounds.merge(e["rect"])
		first = false
	return bounds


# ------------------------------------------------------------------ drawing

func _to_map(world: Vector2) -> Vector2:
	return ((world - _center) * _scale + MAP_UNITS * 0.5).round()


func _to_map_rect(world_rect: Rect2) -> Rect2:
	var a := _to_map(world_rect.position)
	var b := _to_map(world_rect.end)
	return Rect2(a, b - a).abs()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(PX, PX))
	var full := Rect2(Vector2.ZERO, MAP_UNITS)
	draw_rect(full, COL_BG)
	for e in _rooms:
		if e["seen"]:
			_draw_room(e)
	for e in _rooms:
		if e["seen"]:
			_draw_doors(e)
	_draw_player()
	draw_rect(full.grow(-0.5), COL_FRAME, false, 1.0)


func _alpha(e: Dictionary) -> float:
	return clampf(e["t"] / REVEAL_TIME, 0.0, 1.0)


func _draw_room(e: Dictionary) -> void:
	var a := _alpha(e)
	var r := _to_map_rect(e["rect"])
	var fill := COL_EXIT.darkened(0.7) if e["exit"] else COL_FLOOR
	var edge := COL_EXIT if e["exit"] else (COL_START if e["start"] else COL_WALL)
	# Gauntlet rooms are outlined in red (with an X) until they are cleared.
	var room_node = e["room"]
	var danger: bool = is_instance_valid(room_node) and room_node.has_meta("gauntlet") and not room_node.has_meta("gauntlet_cleared")
	if danger:
		edge = COL_GAUNTLET
	fill.a = a
	edge.a = a
	draw_rect(r, fill)
	draw_rect(r.grow(-0.5), edge, false, 1.0)
	var c := r.get_center().round()
	if e["exit"]:
		var d := Color(COL_EXIT.r, COL_EXIT.g, COL_EXIT.b, a)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), d)
	elif e["start"]:
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(3, 3)), Color(COL_START.r, COL_START.g, COL_START.b, a))
	elif danger:
		var x_col := Color(COL_GAUNTLET.r, COL_GAUNTLET.g, COL_GAUNTLET.b, a)
		draw_line(c + Vector2(-3, -3), c + Vector2(3, 3), x_col, 1.0)
		draw_line(c + Vector2(-3, 3), c + Vector2(3, -3), x_col, 1.0)
	elif is_instance_valid(room_node) and room_node.has_meta("special_family"):
		# a boon room (green) or a hidden room you found (blue) shows as a dot
		var family: String = room_node.get_meta("special_family")
		if family == "boon" or family == "hidden":
			var dot := SpecialRooms.family_color(family)
			draw_rect(Rect2(c - Vector2(1, 1), Vector2(3, 3)), Color(dot.r, dot.g, dot.b, a))


func _draw_doors(e: Dictionary) -> void:
	var a := _alpha(e)
	for door in e["doors"]:
		var dir: int = door["dir"]
		var leads_to_seen: bool = door["to"] >= 0 and _rooms[door["to"]]["seen"]
		# the doorway of an undiscovered hidden room is a plain wall as far as the map knows
		if door["to"] >= 0 and _rooms[door["to"]]["hidden"] and not leads_to_seen:
			continue
		var col := COL_DOOR_SEEN if leads_to_seen else COL_DOOR_NEW
		if not leads_to_seen:
			col = col.lerp(Color.WHITE, 0.35 + 0.35 * sin(_clock * 5.0)) # pulse = "go here"
		col.a = a
		var m := _to_map(_door_center(door["pos"], dir))
		var horizontal := dir == 0 or dir == 2
		var half := maxf(roundf((DOOR_W_PX if horizontal else DOOR_H_PX) * _scale * 0.5), 1.0)
		if horizontal:
			draw_rect(Rect2(m.x - half, m.y - 1.0, half * 2.0, 2.0), col)
		else:
			draw_rect(Rect2(m.x - 1.0, m.y - half, 2.0, half * 2.0), col)
		if not leads_to_seen:
			var out: Vector2 = DIRS[dir]
			var side := out.orthogonal()
			draw_colored_polygon(PackedVector2Array([m + out * 5.0, m + out * 2.0 + side * 2.0, m + out * 2.0 - side * 2.0]), col)


func _draw_player() -> void:
	if not is_instance_valid(_tracked):
		return
	var p := _to_map(_tracked.global_position).clamp(Vector2(2, 2), MAP_UNITS - Vector2(3, 3))
	var bright := fmod(_clock, 0.8) < 0.5
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), Color.BLACK)
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), COL_PLAYER if bright else COL_PLAYER.darkened(0.4))
