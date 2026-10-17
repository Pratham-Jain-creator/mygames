class_name HiddenRoom
extends Node
## The four hidden rooms. A hidden room is a dead end whose only doorway is covered by an ILLUSORY WALL: it looks like
## solid brick, a trickle of dust is sucked into it, and the minimap does not show the doorway. Walking into the wall
## makes it dissolve. Inside:
##   chrono_sanctuary    the floor timer stops while you are inside; a bench lets you swap armor and charms
##   deserters_chute     a hole: drop to the next floor and skip this floor's boss (and its loot)
##   smugglers_exchange  a dealer who trades in time and blood
##   predecessors_cache  an armoury of materials from deeper floors

const WALL_COLOR := Color(0.28, 0.22, 0.3)

var room: WFCRoom
var kind: StringName
var cfg: LevelConfig
var generator: Node
var depth: int = 1
var revealed: bool = false

var _wall: IllusoryWall
var _paused_timer: bool = false


func setup_special(p_room: WFCRoom, p_kind: StringName, p_cfg: LevelConfig, p_generator: Node) -> void:
	room = p_room
	kind = p_kind
	cfg = p_cfg
	generator = p_generator
	depth = cfg.depth
	room.set_meta("hidden", true)
	call("_build_" + String(kind))
	var doors := room.get_door_info()
	if not doors.is_empty():
		_wall = IllusoryWall.new()
		_wall.setup(room, doors[0])
		_wall.revealed.connect(_on_revealed)
		room.add_child(_wall)


func _on_revealed() -> void:
	revealed = true
	var game := RoomKit.game()
	if game != null and game.hud != null:
		game.hud.show_title("A HIDDEN ROOM", SpecialRooms.display_name(kind).to_upper(), 2.8)
	Audio.play(preload("res://assets/sounds/power_up.wav"), -4.0, 0.5)
	GameManager.shake_camera(3.0, 0.4)


func _process(_delta: float) -> void:
	if kind != &"chrono_sanctuary":
		return
	var player := RoomKit.player()
	var inside := is_instance_valid(player) and room.get_global_bounds().has_point(player.global_position) and revealed
	if inside and not _paused_timer:
		_paused_timer = true
		GameManager.timer_paused = true
		GameManager.room_banner.emit("TIME STANDS STILL", Color(0.6, 0.85, 1.0))
	elif not inside and _paused_timer:
		_paused_timer = false
		GameManager.timer_paused = false
		GameManager.room_banner.emit("", Color.WHITE)


func _exit_tree() -> void:
	if _paused_timer:
		GameManager.timer_paused = false
		GameManager.room_banner.emit("", Color.WHITE)


# ------------------------------------------------------------------ the rooms

func _build_chrono_sanctuary() -> void:
	RoomKit.altar(room, &"shrine", "THE TIMER HAS STOPPED", SpecialRooms.HIDDEN_COLOR, _sanctuary_note, Vector2(0, -30))
	RoomKit.altar(room, &"workbench", "LOADOUT BENCH: SWAP ARMOR AND CHARMS", Color(0.45, 0.95, 0.85), _open_bench, Vector2(0, 30))


func _sanctuary_note(_by: Node) -> void:
	RoomKit.toast("BREATHE. THE CLOCK WAITS.", Color(0.6, 0.85, 1.0))


func _open_bench(_by: Node) -> void:
	var g := RoomKit.game()
	if g != null:
		g.workbench.open(true)


func _build_deserters_chute() -> void:
	var hole := RoomKit.altar(room, &"hole", "JUMP: SKIP THIS FLOOR'S BOSS", Color(0.6, 0.5, 0.9), func(_by: Node) -> void: pass)
	hole.callback = func(_by: Node) -> void:
		if depth >= LevelConfig.FINAL_DEPTH:
			RoomKit.toast("THERE IS NOWHERE LEFT TO FALL", Color(0.8, 0.8, 0.8))
			return
		RoomKit.menu().open("THE DESERTER'S CHUTE", "You land on floor %d and the boss of this floor never knows you were here: no boss, no boss loot, no blueprint." % (depth + 1), [
			{"name": "Jump", "desc": "Drop to floor %d." % (depth + 1), "color": Color(0.7, 0.6, 1.0)},
		], func(index: int) -> void:
			if index == 0:
				GameManager.travel_requested.emit(depth + 1))


func _build_smugglers_exchange() -> void:
	var dealer := RoomKit.altar(room, &"reaper", "TRADE WITH THE SMUGGLER", Color(0.9, 0.7, 0.3), func(_by: Node) -> void: pass)
	dealer.callback = func(_by: Node) -> void:
		var fractured := Run.fractured_indices()
		var options: Array = [
			{"name": "Mend a fractured charm", "desc": "Costs 3:00 off this floor's timer, no materials.", "color": Color(0.6, 0.9, 1.0), "enabled": not fractured.is_empty()},
			{"name": "Buy a Memory Echo", "desc": "Costs 2:00 off this floor's timer.", "color": Color(0.6, 0.85, 1.0)},
			{"name": "Sell some blood", "desc": "Lose 15% of your health (not lethal): receive 3 rare materials.", "color": Color(0.95, 0.4, 0.4)},
		]
		RoomKit.menu().open("THE SMUGGLER'S EXCHANGE", "\"Ash is for amateurs. I take TIME, and I take BLOOD.\"", options, func(index: int) -> void: _exchange_pick(index, fractured, dealer))


func _exchange_pick(index: int, fractured: Array[int], dealer: Altar) -> void:
	match index:
		0:
			_mend_charm(fractured)
		1:
			if RoomKit.spend_time(room, 120.0):
				Run.echoes += 1
				Run.save_profile()
				RoomKit.toast("2:00 SPENT: YOU HAVE A MEMORY ECHO", Color(0.6, 0.85, 1.0))
			else:
				RoomKit.toast("THE FLOOR HAS TOO LITTLE TIME LEFT TO SPARE", Color(1.0, 0.5, 0.4))
		2:
			if RoomKit.pay_health(int(round(float(Run.max_health()) * 0.15))):
				Loot.drop_materials(RoomKit.spawned(room), dealer.global_position + Vector2(0, 14), 3, depth, RoomKit.tier(depth, 1))
				RoomKit.toast("A DEAL IS A DEAL", Color(0.9, 0.7, 0.3))


func _mend_charm(fractured: Array[int]) -> void:
	var options: Array = []
	for i in fractured:
		var def: Dictionary = RunData.CHARMS[Run.forged[i]["id"]]
		options.append({"name": def["name"], "desc": "Repair it for 3:00 of this floor's time.", "color": def["color"]})
	RoomKit.menu().open("WHICH CHARM?", "", options, func(index: int) -> void:
		if index < 0:
			return
		if not RoomKit.spend_time(room, 180.0):
			RoomKit.toast("THE FLOOR HAS TOO LITTLE TIME LEFT TO SPARE", Color(1.0, 0.5, 0.4))
			return
		Run.repair_free(fractured[index])
		RoomKit.toast("MENDED FOR 3:00", Color(0.6, 0.9, 1.0)))


func _build_predecessors_cache() -> void:
	var cache := RoomKit.altar(room, &"chest", "OPEN THE PREDECESSOR'S ARMOURY", Color(0.4, 0.95, 0.75), func(_by: Node) -> void: pass)
	cache.callback = func(_by: Node) -> void:
		RoomKit.use_up(cache, "EMPTY")
		var at := cache.global_position + Vector2(0, 8)
		Loot.drop_materials(RoomKit.spawned(room), at, 5, depth, 3)
		Pickup.spawn(RoomKit.spawned(room), at, Pickup.Kind.MATERIAL, 2, &"predecessor_alloy")
		var unknown: Array = RunData.BLUEPRINTS.keys().filter(func(id: StringName) -> bool: return not Run.blueprints.has(id) and not Run.carried_blueprints.has(id))
		if not unknown.is_empty() and randf() < 0.4:
			Pickup.spawn(RoomKit.spawned(room), at + Vector2(0, 6), Pickup.Kind.BLUEPRINT, 1, unknown[randi() % unknown.size()])
		Loot.drop_ash(RoomKit.spawned(room), at, int(round(80.0 * Loot.floor_scale(depth))))
		RoomKit.toast("MATERIALS FROM FLOORS YOU HAVE NOT REACHED", Color(0.4, 0.95, 0.75))
		GameManager.shake_camera(3.0, 0.3)


# ------------------------------------------------------------------ the illusory wall

class IllusoryWall extends Node2D:
	## Looks like a stretch of the room's wall. A collision body keeps the player out (like a real wall) until
	## he touches it: then it dissolves.
	signal revealed

	const WALL_COLOR := Color(0.28, 0.22, 0.3)

	var _rect: Rect2
	var _inward: Vector2
	var _trigger: Area2D
	var _body: StaticBody2D
	var _dust: CPUParticles2D
	var _fade: float = 1.0
	var _dissolving: bool = false
	var _seed: int = 0

	func setup(room: WFCRoom, door: Dictionary) -> void:
		var center: Vector2 = door["center"]
		_inward = door["inward"]
		var dir: int = door["dir"]
		var local_center := room.to_local(center)
		if dir == 0 or dir == 2:
			_rect = Rect2(local_center + Vector2(-48, -16), Vector2(96, 32))
		else:
			_rect = Rect2(local_center + Vector2(-16, -32), Vector2(32, 64))
		z_index = 3
		_seed = hash(center)
		_body = StaticBody2D.new()
		_body.collision_layer = 1
		_body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = _rect.size
		shape.shape = box
		shape.position = _rect.get_center()
		_body.add_child(shape)
		add_child(_body)
		_trigger = Area2D.new()
		_trigger.collision_layer = 0
		_trigger.collision_mask = 2
		var trigger_shape := CollisionShape2D.new()
		var trigger_box := RectangleShape2D.new()
		trigger_box.size = _rect.size + Vector2(10, 10)
		trigger_shape.shape = trigger_box
		trigger_shape.position = _rect.get_center()
		_trigger.add_child(trigger_shape)
		_trigger.body_entered.connect(_on_touched)
		add_child(_trigger)
		# the cue: dust drifting INTO the wall from the corridor side
		_dust = CPUParticles2D.new()
		_dust.amount = 14
		_dust.lifetime = 2.2
		_dust.position = _rect.get_center() - _inward * 30.0
		_dust.direction = _inward
		_dust.spread = 14.0
		_dust.initial_velocity_min = 10.0
		_dust.initial_velocity_max = 16.0
		_dust.gravity = Vector2.ZERO
		_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_dust.emission_sphere_radius = 10.0
		_dust.scale_amount_min = 0.8
		_dust.scale_amount_max = 1.6
		_dust.color = Color(0.7, 0.65, 0.6, 0.55)
		_dust.z_index = 4
		add_child(_dust)

	func _on_touched(body: Node) -> void:
		if _dissolving or not body.is_in_group("player"):
			return
		_dissolving = true
		_body.set_deferred("collision_layer", 0)
		_dust.emitting = false
		revealed.emit()
		var burst := CPUParticles2D.new()
		burst.amount = 24
		burst.one_shot = true
		burst.explosiveness = 1.0
		burst.lifetime = 0.8
		burst.position = _rect.get_center()
		burst.spread = 180.0
		burst.initial_velocity_min = 25.0
		burst.initial_velocity_max = 60.0
		burst.gravity = Vector2.ZERO
		burst.color = Color(0.6, 0.55, 0.5, 0.8)
		burst.emitting = true
		add_child(burst)
		create_tween().tween_property(self, "_fade", 0.0, 0.7)
		get_tree().create_timer(1.6).timeout.connect(queue_free)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if _fade <= 0.01:
			return
		# plain brick, a shade off from the real wall, with a few cracks: the clue for a sharp eye
		draw_rect(_rect, Color(WALL_COLOR.r, WALL_COLOR.g, WALL_COLOR.b, _fade))
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed
		var row_h := 8.0
		var rows := int(_rect.size.y / row_h)
		for r in rows:
			var y := _rect.position.y + float(r) * row_h
			draw_line(Vector2(_rect.position.x, y), Vector2(_rect.end.x, y), Color(0.12, 0.09, 0.14, _fade), 1.0)
			var x := _rect.position.x + (6.0 if r % 2 == 0 else 14.0)
			while x < _rect.end.x:
				draw_line(Vector2(x, y), Vector2(x, y + row_h), Color(0.12, 0.09, 0.14, _fade), 1.0)
				x += 16.0
		for i in 3:
			var start := _rect.position + Vector2(rng.randf() * _rect.size.x, rng.randf() * _rect.size.y)
			draw_polyline(PackedVector2Array([start, start + Vector2(rng.randf_range(-6, 6), rng.randf_range(3, 9)), start + Vector2(rng.randf_range(-9, 9), rng.randf_range(9, 16))]), Color(0.05, 0.03, 0.07, _fade), 1.5)
