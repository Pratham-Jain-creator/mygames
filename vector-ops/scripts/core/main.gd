extends Node3D
## Root scene: loads the map scene, then adds spawner, HUD and spectator.

var players_root: Node3D
var spawner: MultiplayerSpawner
var map: Node3D
var _map_loaded: int = -1


func _ready() -> void:
	GameState.world = self
	_build_environment()
	_load_map(GameState.map_index)

	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	spawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	add_child(spawner)
	spawner.spawn_path = spawner.get_path_to(players_root)
	spawner.spawn_function = _spawn_player

	add_child(Hud.new())
	add_child(Spectator.new())

	# dev shortcut: a file res://debug_autostart.txt containing "1" skips the menu
	if FileAccess.file_exists("res://debug_autostart.txt") and FileAccess.get_file_as_string("res://debug_autostart.txt").strip_edges() == "1":
		GameState.solo_game()
		GameState.request_start()


## Swaps in the arena chosen in GameState.map_index (no-op if it is already loaded).
func ensure_map() -> void:
	if GameState.map_index != _map_loaded:
		_load_map(GameState.map_index)


func _load_map(i: int) -> void:
	i = MapCatalog.clamp_index(i)
	if map != null:
		remove_child(map)
		map.queue_free()
	var packed := load(MapCatalog.scene_path(i)) as PackedScene
	map = packed.instantiate()
	map.name = "Map"
	add_child(map)
	move_child(map, 0)
	_map_loaded = i
	# CSG meshes build on the first frames; bake bot navigation afterwards (on a thread: big maps take a while)
	await get_tree().process_frame
	await get_tree().process_frame
	if map != null and _map_loaded == i:
		MapBuilder.bake_nav(map)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _spawn_player(data: Variant) -> Node:
	var p := Player.new()
	p.setup(data)
	return p


## Server: replace all players with a fresh roster at team spawn points.
func spawn_round(roster: Array) -> void:
	ensure_map()
	clear_players()
	var idx := [0, 0]
	for e in roster:
		var t: int = e["team"]
		var pts: Array = get_tree().get_nodes_in_group("spawn_%d" % t)
		pts.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
		var m: Marker3D = pts[idx[t] % pts.size()]
		idx[t] += 1
		e["pos"] = m.global_position
		e["yaw"] = PI if t == 0 else 0.0
		spawner.spawn(e)


func clear_players() -> void:
	for c in players_root.get_children():
		players_root.remove_child(c)
		c.queue_free()


func remove_peer(id: int) -> void:
	for c in players_root.get_children():
		if not c.is_bot and c.peer_id == id:
			players_root.remove_child(c)
			c.queue_free()


func _process(_delta: float) -> void:
	# clients follow the host's arena choice
	if GameState.map_index != _map_loaded:
		ensure_map()
	# the pause menu (ESC) frees the mouse; closing it captures it again
	var want: bool = GameState.phase != GameState.Phase.LOBBY and GameState.in_session and not GameState.paused_ui
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE
