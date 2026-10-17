class_name MapCatalog
extends RefCounted
## The playable arenas, smallest to largest. Each is a scene in scenes/world/ with
## a MapBuilder root, a Nav/Geo node, and Marker3D spawns in groups spawn_0 / spawn_1.
## To add a map: build the scene, then add a line here - menu and match flow pick it up.

const MAPS := [
	{"name": "SMALL", "size": 120, "scene": "res://scenes/world/map.tscn"},
	{"name": "MEDIUM", "size": 170, "scene": "res://scenes/world/map_medium.tscn"},
	{"name": "LARGE", "size": 240, "scene": "res://scenes/world/map_large.tscn"},
	{"name": "HUGE", "size": 340, "scene": "res://scenes/world/map_huge.tscn"},
	{"name": "VAST", "size": 480, "scene": "res://scenes/world/map_vast.tscn"},
	{"name": "COLOSSAL", "size": 680, "scene": "res://scenes/world/map_colossal.tscn"},
]


static func count() -> int:
	return MAPS.size()


static func clamp_index(i: int) -> int:
	return clampi(i, 0, MAPS.size() - 1)


static func scene_path(i: int) -> String:
	return String(MAPS[clamp_index(i)]["scene"])


static func label(i: int) -> String:
	var m: Dictionary = MAPS[clamp_index(i)]
	return "%s  -  %d x %d m" % [m["name"], m["size"], m["size"]]
