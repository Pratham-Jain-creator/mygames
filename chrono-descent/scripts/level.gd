class_name Level
extends Node2D
## One generated dungeon floor: its config, its rooms and its own collapse timer.
##
## A floor stays alive (asleep and hidden) while the player is elsewhere, so the stairs up and
## down lead back to the SAME layout until this floor's timer runs out. Each floor sits at its
## own spot in the world (see Levels.LEVEL_SPACING) so several floors can exist at once.
##
## Safe rooms are the start room (the one you arrive in, with the stairs up) and the extraction
## room (the one with the stairs down). When this floor's timer runs out, a player standing in a
## safe room survives and the floor is rebuilt around them; anywhere else the dungeon swallows
## them.

## Distance below a staircase where the player appears (outside the 30 px interact range, so
## arriving never shows a prompt).
const ARRIVAL_OFFSET: Vector2 = Vector2(0, 44)

var config: LevelConfig
var depth: int = 1
## Seconds until this floor shifts. Each floor has its own timer, started when it was built.
var time_left: float = 0.0
## Which world slot this floor occupies (its position is slot * Levels.LEVEL_SPACING).
var slot: int = 0
var rooms: Array[WFCRoom] = []
var start_rooms: Array[WFCRoom] = []
var extraction_room: WFCRoom
## The staircase up (in the start room) and the staircase down (in the extraction room).
var up_stairs: Node2D
var down_stairs: Node2D


func setup(level_config: LevelConfig) -> void:
	config = level_config
	depth = level_config.depth
	time_left = level_config.duration
	name = "Floor%d" % depth


func apply_result(result: Dictionary) -> void:
	rooms.assign(result["rooms"])
	start_rooms.assign(result["start_rooms"])
	extraction_room = result["extraction_room"]


## Where the player appears when coming DOWN into this floor: next to the stairs up.
func get_player_spawn() -> Vector2:
	if is_instance_valid(up_stairs):
		return up_stairs.global_position + ARRIVAL_OFFSET
	if not start_rooms.is_empty():
		var marker := start_rooms[0].get_node_or_null("PlayerSpawn") as Node2D
		return marker.global_position if marker else start_rooms[0].global_position
	return get_arrival_from_below()


## Where the player appears when coming UP into this floor: next to the stairs down.
func get_arrival_from_below() -> Vector2:
	if is_instance_valid(down_stairs):
		return down_stairs.global_position + ARRIVAL_OFFSET
	if extraction_room:
		return extraction_room.get_global_bounds().get_center()
	return global_position


func get_room_at(world_pos: Vector2) -> WFCRoom:
	for room in rooms:
		if is_instance_valid(room) and room.get_global_bounds().has_point(world_pos):
			return room
	return null


func is_safe_room(room: WFCRoom) -> bool:
	return room != null and (start_rooms.has(room) or room == extraction_room)


## The rooms that survive a collapse for a player standing at world_pos. Empty = not safe.
func get_anchor_rooms_for(world_pos: Vector2) -> Array[WFCRoom]:
	var anchors: Array[WFCRoom] = []
	var room := get_room_at(world_pos)
	if not is_safe_room(room):
		return anchors
	if start_rooms.has(room):
		anchors.assign(start_rooms)
	else:
		anchors.append(extraction_room)
	return anchors
