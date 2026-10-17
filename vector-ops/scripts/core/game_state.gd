extends Node
## Autoload. Networking bootstrap, lobby, round/match flow (Milestone 5).
## Match state is replicated with a MultiplayerSynchronizer; only the server
## advances it.

signal phase_changed(new_phase: int)
signal report_received(text: String)
signal player_ejected(p: Node)
signal local_hurt(from_pos: Vector3, blocked: bool)
signal local_hit(killed: bool, blocked: bool, zone: String)
signal connection_status(msg: String)
signal local_killed(killer: String, src: String, dist: float)

enum Phase { LOBBY, COUNTDOWN, LIVE, ROUND_END, MATCH_END }

const TEAM_SIZE := 3
const WIN_ROUNDS := 3 # best of 5
const COUNTDOWN_TIME := 3.5 # pre-round wait (module swaps are free during it)
var sens_mult: float = 1.0 # Settings: mouse sensitivity multiplier
var fov_setting: float = 85.0 # Settings: field of view (degrees)
var master_volume: float = 1.0 # Settings: master volume (0..1)
var saved_builds: Array = [] # [{name: String, sel: [[4 ids], [4 ids]]}] - the player's custom builds
const ROUND_TIME := 300.0 # 5 minutes
const ROUND_END_TIME := 4.5 # result + report screen between rounds
const MATCH_END_TIME := 4.5 # on top of the round-end wait that comes before it
const PORT := 24565
const TEAM_NAMES := ["ALPHA", "BRAVO"]
# Bot builds, one per role: [right hand slots, left hand slots]. Bots rotate between the slots of a hand
# (BotBrain scores every module for the current situation). A team gets distinct roles, drawn without repeats.
const BOT_PRESETS := [
	[["kinetic", "edge"], ["aegis", "boost"]], # assault
	[["bolt", "kinetic"], ["ghost", "heal"]], # sniper
	[["blast", "kinetic"], ["bunker", "heal"]], # demolition
	[["kinetic", "seeker"], ["shift", "boost"]], # skirmisher
	[["kinetic", "heal"], ["bunker", "aegis"]], # support
	[["edge", "kinetic"], ["mirage", "shift"]], # assassin
]

# replicated
var phase: int = Phase.LOBBY
var round_number: int = 0
var time_left: float = 0.0
var countdown_left: float = 0.0
var score_a: int = 0
var score_b: int = 0
var announce: String = ""
var lobby_text: String = ""
var map_index: int = 0 # which arena (MapCatalog); chosen by the host, replicated

# local
var world: Node = null
var in_session: bool = false
var local_name: String = "Operator"
var local_loadout: Array = [["kinetic", "edge", "", ""], ["aegis", "boost", "", ""]]
var local_team: int = 0
var last_report: String = ""
var using_pad: bool = false # last input came from a gamepad (enables aim assist + menu focus)
var local_map: int = 0 # arena picked in the menu (used when this peer hosts / plays solo)
var paused_ui: bool = false # pause menu is open: the mouse is free and game input is ignored

# server only
var lobby: Dictionary = {}
var _phase_timer: float = 0.0
var _last_phase: int = -1
var _next_id: int = 1
var match_kills: Dictionary = {} # display_name -> {weapon: count}


func _ready() -> void:
	SaveData.load_all()
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":phase", ":round_number", ":time_left", ":countdown_left", ":score_a", ":score_b", ":announce", ":lobby_text", ":map_index"]:
		var np := NodePath(prop)
		cfg.add_property(np)
		cfg.property_set_replication_mode(np, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = cfg
	sync.replication_interval = 0.1
	add_child(sync)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveData.save_all()


# --- session setup -----------------------------------------------------------

func solo_game() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	in_session = true
	map_index = MapCatalog.clamp_index(local_map)
	_register(1, local_name, local_loadout)


## Leave the current match and return to the start screen (host or client).
func leave_match() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	in_session = false
	paused_ui = false
	phase = Phase.LOBBY
	announce = ""
	lobby.clear()
	get_tree().paused = false
	if world != null:
		world.clear_players()


func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 8)
	if err != OK:
		connection_status.emit("Could not host on port %d (error %d)." % [PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	in_session = true
	map_index = MapCatalog.clamp_index(local_map)
	_register(1, local_name, local_loadout)
	connection_status.emit("Hosting on port %d." % PORT)


func join_game(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		connection_status.emit("Could not connect (error %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	connection_status.emit("Connecting to %s ..." % ip)


func _on_connected_ok() -> void:
	in_session = true
	srv_register.rpc_id(1, local_name, local_loadout)
	connection_status.emit("Connected.")


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_status.emit("Connection failed.")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	in_session = false
	phase = Phase.LOBBY
	if world != null:
		world.clear_players()
	connection_status.emit("Disconnected from host.")


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	lobby.erase(id)
	if world != null:
		world.remove_peer(id)
	_refresh_lobby_text()


@rpc("any_peer", "call_remote", "reliable")
func srv_register(pname: String, loadout: Array) -> void:
	if not multiplayer.is_server():
		return
	_register(multiplayer.get_remote_sender_id(), pname, loadout)


func _register(id: int, pname: String, loadout: Array) -> void:
	var counts := [0, 0]
	for k in lobby:
		var t: int = lobby[k]["team"]
		if t >= 0:
			counts[t] += 1
	var team := -1
	if counts[0] <= counts[1] and counts[0] < TEAM_SIZE:
		team = 0
	elif counts[1] < TEAM_SIZE:
		team = 1
	lobby[id] = {"name": pname.substr(0, 16), "loadout": Loadout.sanitize(loadout), "team": team}
	_refresh_lobby_text()


func _refresh_lobby_text() -> void:
	var lines: PackedStringArray = []
	for t in 2:
		var names: PackedStringArray = []
		for k in lobby:
			if lobby[k]["team"] == t:
				names.append(lobby[k]["name"])
		lines.append("%s: %s" % [TEAM_NAMES[t], ", ".join(names) if not names.is_empty() else "(bots)"])
	var spec: PackedStringArray = []
	for k in lobby:
		if lobby[k]["team"] < 0:
			spec.append(lobby[k]["name"])
	if not spec.is_empty():
		lines.append("Spectating: " + ", ".join(spec))
	lines.append("Arena: " + MapCatalog.label(map_index))
	lines.append("Empty seats are filled with bots (3v3).")
	lobby_text = "\n".join(lines)


func get_local_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_local:
			return p
	return null


# --- match flow (server) -------------------------------------------------------

func request_start() -> void:
	if not multiplayer.is_server() or phase != Phase.LOBBY:
		return
	if world != null:
		world.ensure_map() # the arena must exist before anyone spawns
	score_a = 0
	score_b = 0
	round_number = 0
	match_kills.clear()
	_next_round()


func _build_roster() -> Array:
	var roster: Array = []
	var counts := [0, 0]
	for k in lobby:
		var info: Dictionary = lobby[k]
		var t: int = info["team"]
		if t < 0:
			continue
		roster.append({"id": _next_id, "peer": k, "team": t, "bot": false, "name": info["name"], "loadout": info["loadout"]})
		_next_id += 1
		counts[t] += 1
	var bot_n := 1
	for t in 2:
		var pool: Array = range(BOT_PRESETS.size())
		pool.shuffle()
		while counts[t] < TEAM_SIZE:
			var preset: Array = BOT_PRESETS[pool.pop_back()]
			roster.append({"id": _next_id, "peer": 1, "team": t, "bot": true, "name": "Bot-%d" % bot_n, "loadout": Loadout.sanitize(preset)})
			_next_id += 1
			bot_n += 1
			counts[t] += 1
	return roster


func _next_round() -> void:
	round_number += 1
	world.spawn_round(_build_roster())
	phase = Phase.COUNTDOWN
	_phase_timer = COUNTDOWN_TIME
	countdown_left = COUNTDOWN_TIME
	time_left = ROUND_TIME
	announce = "ROUND %d" % round_number


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	match phase:
		Phase.COUNTDOWN:
			_phase_timer -= delta
			countdown_left = maxf(0.0, _phase_timer)
			if _phase_timer <= 0.0:
				phase = Phase.LIVE
				announce = "FIGHT"
		Phase.LIVE:
			time_left = maxf(0.0, time_left - delta)
			if _phase_timer < -2.0 or announce == "FIGHT":
				if time_left < ROUND_TIME - 1.5:
					announce = ""
			_check_round_end()
		Phase.ROUND_END:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				if score_a >= WIN_ROUNDS or score_b >= WIN_ROUNDS:
					phase = Phase.MATCH_END
					var w := 0 if score_a > score_b else 1
					announce = "%s WINS THE MATCH  %d - %d" % [TEAM_NAMES[w], score_a, score_b]
					_phase_timer = MATCH_END_TIME
				else:
					_next_round()
		Phase.MATCH_END:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				world.clear_players()
				phase = Phase.LOBBY
				announce = ""


func _process(_delta: float) -> void:
	if phase != _last_phase:
		_last_phase = phase
		phase_changed.emit(phase)


func record_kill(attacker: Node, src: String) -> void:
	var nm: String = attacker.display_name
	var d: Dictionary = match_kills.get(nm, {})
	d[src] = int(d.get(src, 0)) + 1
	match_kills[nm] = d


func kills_text(d: Dictionary) -> String:
	if d.is_empty():
		return "none"
	var total := 0
	var parts: PackedStringArray = []
	for k in d:
		total += int(d[k])
		parts.append("%s x%d" % [k, int(d[k])])
	return "%d (%s)" % [total, ", ".join(parts)]


func _check_round_end() -> void:
	var alive := [0, 0]
	var flux_sum := [0.0, 0.0]
	for p in get_tree().get_nodes_in_group("players"):
		if not p.flux.ejected:
			alive[p.team] += 1
			flux_sum[p.team] += p.flux.total_flux()
	if alive[0] > 0 and alive[1] > 0 and time_left > 0.0:
		return
	var winner := -1
	if alive[0] == 0 and alive[1] > 0:
		winner = 1
	elif alive[1] == 0 and alive[0] > 0:
		winner = 0
	elif alive[0] > 0 and alive[1] > 0:
		# timeout: more total Flux left wins
		if absf(flux_sum[0] - flux_sum[1]) > 0.5:
			winner = 0 if flux_sum[0] > flux_sum[1] else 1
	_end_round(winner, alive[0] > 0 and alive[1] > 0)


func _end_round(winner: int, timeout: bool) -> void:
	phase = Phase.ROUND_END
	_phase_timer = ROUND_END_TIME
	if winner == 0:
		score_a += 1
	elif winner == 1:
		score_b += 1
	var head := "DRAW"
	if winner >= 0:
		head = "%s WINS THE ROUND" % TEAM_NAMES[winner]
	if timeout:
		head += " (time up - most Flux remaining)"
	announce = head
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot:
			continue
		var text: String = "ROUND %d - %s\n\n%s" % [round_number, head, p.flux.build_report()]
		text += "\n\nMATCH KILLS so far: " + kills_text(match_kills.get(p.display_name, {}))
		if p.peer_id == 1:
			last_report = text
			report_received.emit(text)
		else:
			cl_report.rpc_id(p.peer_id, text)


@rpc("authority", "call_remote", "reliable")
func cl_report(text: String) -> void:
	last_report = text
	report_received.emit(text)
