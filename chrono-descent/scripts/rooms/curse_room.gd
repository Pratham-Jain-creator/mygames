class_name CurseRoom
extends GauntletController
## The six cursed rooms. You OPT IN at the altar by paying health (20% of your maximum, never lethal); then the doors
## seal and a rule of the game bends until you win:
##   shackled_arena       no dash. Slow, heavy golems.            suffocating_fog   gas drains you; every sword blow heals
##   blind_pits           near-total darkness, glowing eyes       gauntlet_attrition  two minutes of endless enemies
##   phantoms_arena       an unkillable shadow hunts you while you solve a rune puzzle
##   cursed_hoard         five chests: one holds a blueprint, four are elite mimics
## The reward is a golden chest and materials (more than any normal room gives).

const MIMIC_PATH: String = "res://scenes/enemies/mimic_chest.tscn"
const GOLEM_PATH: String = "res://scenes/enemies/mini_golem.tscn"
const CHEST_PATH: String = "res://scenes/props/chest.tscn"
const OFFER_COST_SHARE: float = 0.20
const ATTRITION_SECONDS: float = 120.0
const DARK_COLOR := Color(0.015, 0.015, 0.04)
const RUNE_COLORS: Array[Color] = [Color(0.95, 0.3, 0.3), Color(0.4, 0.9, 0.4), Color(0.4, 0.6, 1.0), Color(1.0, 0.85, 0.3)]

var kind: StringName
var cfg: LevelConfig
var generator: Node
var depth: int = 1
var opted_in: bool = false

var _offer: Altar
var _clock: float = 0.0
var _fog: Polygon2D
var _saved_modulate: Color = Color.WHITE
var _saved_light_scale: float = 1.0
var _curse_active: bool = false
var _kills: int = 0
var _attrition_left: float = 0.0
var _spawn_clock: float = 0.0
var _phantom: PhantomShadow
var _plates: Array[RunePlate] = []
var _board: SequenceBoard
var _order: Array[int] = []
var _progress: int = 0
var _plate_lock: float = 0.0


func setup_special(p_room: WFCRoom, p_kind: StringName, p_cfg: LevelConfig, p_generator: Node) -> void:
	kind = p_kind
	cfg = p_cfg
	generator = p_generator
	depth = cfg.depth
	var waves := 2
	var budget := int(60.0 * cfg.difficulty)
	if kind == &"gauntlet_attrition" or kind == &"phantoms_arena" or kind == &"cursed_hoard":
		waves = 1
	setup(p_room, waves, budget, Callable(self, "_pick"), Callable(generator, "_spawn_enemy"), [])
	# the reward chest (locked until the curse is beaten); the hoard has its own chests
	if kind != &"cursed_hoard":
		var chest := generator._spawn_into(room, CHEST_PATH, RoomKit.spot(room, Vector2(0, -60)), {"locked": true, "golden": true, "bonus_materials": 2}) as Node
		if chest != null:
			_reward_chests.append(chest)
	var cost := _cost()
	_offer = RoomKit.altar(room, &"altar", "ACCEPT THE CURSE: PAY %d HEALTH" % cost, SpecialRooms.CURSE_COLOR, _accept_curse, Vector2(0, 20))


func _cost() -> int:
	return int(ceil(float(Run.max_health()) * OFFER_COST_SHARE))


func _accept_curse(_by: Node) -> void:
	if opted_in:
		return
	if not RoomKit.pay_health(_cost()):
		return
	opted_in = true
	RoomKit.use_up(_offer, "THE CURSE IS ACCEPTED")
	_offer.visible = false
	Audio.play(preload("res://assets/sounds/hurt.wav"), -4.0, 0.5)
	RoomKit.toast("%s: THE CURSE IS ACCEPTED" % SpecialRooms.display_name(kind).to_upper(), SpecialRooms.CURSE_COLOR)
	if kind == &"cursed_hoard":
		_open_hoard()


## The enemies of a wave: golems in the Shackled Arena, the floor's usual enemies elsewhere.
func _pick(budget: int) -> Dictionary:
	if kind == &"shackled_arena":
		return {"path": GOLEM_PATH, "cost": 30} if budget >= 30 else {}
	return generator.pick_enemy(budget)


# ------------------------------------------------------------------ flow

func _start() -> void:
	if not opted_in or kind == &"cursed_hoard":
		return
	super()
	_curse_on()


func _physics_process(delta: float) -> void:
	super(delta)
	if state == State.ACTIVE:
		_tick_curse(delta)


func _win() -> void:
	_curse_off()
	super()
	_reward()


func _reset() -> void:
	if state == State.ACTIVE:
		_curse_off()
		GameManager.room_banner.emit("", Color.WHITE)
	super()
	if is_instance_valid(_phantom):
		_phantom.queue_free()
	for plate in _plates:
		if is_instance_valid(plate):
			plate.queue_free()
	_plates.clear()
	if is_instance_valid(_board):
		_board.queue_free()


func _exit_tree() -> void:
	_curse_off()


## Materials and ash for beating a curse. Cursed rooms are where materials come from.
func _reward() -> void:
	GameManager.room_banner.emit("", Color.WHITE)
	var at := RoomKit.center(room)
	Loot.drop_materials(RoomKit.spawned(room), at, 3 + depth / 3, depth, RoomKit.tier(depth, 0))
	Loot.drop_ash(RoomKit.spawned(room), at, int(round(90.0 * Loot.floor_scale(depth))))
	RoomKit.toast("THE CURSE IS BROKEN", Color(1.0, 0.85, 0.5))


# ------------------------------------------------------------------ what each curse does

func _curse_on() -> void:
	_curse_active = true
	var player := RoomKit.player()
	match kind:
		&"shackled_arena":
			player.dash_disabled = true
			GameManager.room_banner.emit("SHACKLED: NO DASH", SpecialRooms.CURSE_COLOR)
		&"suffocating_fog":
			_fog = Polygon2D.new()
			var b := room.get_global_bounds()
			_fog.polygon = PackedVector2Array([room.to_local(b.position), room.to_local(Vector2(b.end.x, b.position.y)), room.to_local(b.end), room.to_local(Vector2(b.position.x, b.end.y))])
			_fog.color = Color(0.4, 0.85, 0.3, 0.17)
			_fog.z_index = 9
			room.add_child(_fog)
			player.blade.hit_landed.connect(_fog_heal)
			GameManager.room_banner.emit("THE FOG DRAINS YOU: STRIKE TO HEAL", Color(0.5, 0.95, 0.4))
		&"blind_pits":
			var game := RoomKit.game()
			if game != null:
				var canvas := game.get_node("CanvasModulate") as CanvasModulate
				_saved_modulate = canvas.color
				create_tween().tween_property(canvas, "color", DARK_COLOR, 0.8)
			var light := player.get_node("PointLight2D") as PointLight2D
			_saved_light_scale = light.texture_scale
			create_tween().tween_property(light, "texture_scale", 0.18, 0.8)
			GameManager.room_banner.emit("THE PITS ARE BLIND: LISTEN, LOOK FOR EYES", SpecialRooms.CURSE_COLOR)


func _curse_off() -> void:
	if not _curse_active:
		return
	_curse_active = false
	var player := RoomKit.player()
	if player != null:
		player.dash_disabled = false
		if player.blade.hit_landed.is_connected(_fog_heal):
			player.blade.hit_landed.disconnect(_fog_heal)
	if is_instance_valid(_fog):
		_fog.queue_free()
	if kind == &"blind_pits":
		var game := RoomKit.game()
		if game != null and game.has_node("CanvasModulate"):
			(game.get_node("CanvasModulate") as CanvasModulate).color = _saved_modulate
		if player != null and player.has_node("PointLight2D"):
			(player.get_node("PointLight2D") as PointLight2D).texture_scale = _saved_light_scale


func _tick_curse(delta: float) -> void:
	_clock += delta
	match kind:
		&"suffocating_fog":
			if _clock >= 0.75:
				_clock = 0.0
				var player := RoomKit.player()
				if player.health_component.current_health > 1:
					player.health_component.take_damage(1 + depth / 4)
		&"gauntlet_attrition":
			_tick_attrition(delta)
		&"phantoms_arena":
			_tick_phantom(delta)


func _fog_heal(_enemy: Node2D) -> void:
	RoomKit.heal(2 + depth / 3)


## Blind Pits: every enemy gets two glowing red eyes (a small red light on it).
func _next_wave() -> void:
	if kind == &"gauntlet_attrition":
		_attrition_left = ATTRITION_SECONDS
		_spawn_clock = 0.0
		_kills = 0
		_alive = 0
		return
	if kind == &"phantoms_arena":
		_begin_phantom()
		return
	super()
	if kind == &"blind_pits":
		for enemy in _enemies:
			if is_instance_valid(enemy) and not enemy.has_node("Eyes"):
				var eyes := PointLight2D.new()
				eyes.name = "Eyes"
				eyes.color = Color(1.0, 0.15, 0.1)
				eyes.energy = 1.1
				eyes.texture = _eye_texture()
				eyes.texture_scale = 0.22
				eyes.position = Vector2(0, -6)
				enemy.add_child(eyes)


func _eye_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(0.3, 0.3, 0.3), Color.BLACK])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


# ------------------------------------------------------------------ the Gauntlet of Attrition

func _tick_attrition(delta: float) -> void:
	_attrition_left -= delta
	_spawn_clock -= delta
	GameManager.room_banner.emit("ATTRITION  %d:%02d   KILLS %d" % [int(maxf(_attrition_left, 0.0)) / 60, int(maxf(_attrition_left, 0.0)) % 60, _kills], SpecialRooms.CURSE_COLOR)
	if _attrition_left <= 0.0:
		_end_attrition()
		return
	if _spawn_clock <= 0.0 and _alive < 8:
		_spawn_clock = 2.4
		var choice: Dictionary = generator.pick_enemy(int(35.0 * cfg.difficulty))
		var points := room.find_spawn_points(1, 60.0, room.get_reserved_points(), 1, SPAWN_DOOR_CLEARANCE)
		if not choice.is_empty() and not points.is_empty():
			var enemy := _spawn.call(room, choice["path"], points[0], {}) as EnemyBase
			if enemy != null:
				_alive += 1
				_enemies.append(enemy)
				enemy.defeated.connect(_on_enemy_defeated)
				enemy.wake_up()


func _on_enemy_defeated(_enemy: EnemyBase) -> void:
	_alive -= 1
	if kind == &"gauntlet_attrition":
		_kills += 1
		return
	if _alive <= 0 and state == State.ACTIVE:
		_on_wave_cleared()


## Time is up: whatever still stands falls apart, and the loot is paid by how many you killed.
func _end_attrition() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy) and not (enemy as EnemyBase)._dead:
			BossFX.puff(RoomKit.spawned(room), enemy.global_position, 0.8)
			enemy.queue_free()
	_enemies.clear()
	_alive = 0
	var at := RoomKit.center(room)
	Loot.drop_materials(RoomKit.spawned(room), at, mini(_kills / 5, 10), depth, RoomKit.tier(depth, 0))
	Loot.drop_ash(RoomKit.spawned(room), at, int(round(float(_kills) * 6.0 * Loot.floor_scale(depth))))
	RoomKit.toast("YOU SURVIVED: %d KILLS" % _kills, Color(1.0, 0.85, 0.5))
	_win()


# ------------------------------------------------------------------ the Phantom's Arena

class PhantomShadow extends Node2D:
	## An unkillable shadow of the floor's boss: it drifts after the player through walls and hurts on contact.
	var speed: float = 52.0
	var damage: int = 12
	var _hit_cooldown: float = 0.0
	var _clock: float = 0.0

	func _physics_process(delta: float) -> void:
		_clock += delta
		_hit_cooldown = maxf(0.0, _hit_cooldown - delta)
		var player := GameManager.player
		if not is_instance_valid(player) or player.is_dead:
			return
		var to: Vector2 = player.global_position - global_position
		global_position += to.normalized() * speed * delta
		if to.length() < 14.0 and _hit_cooldown <= 0.0:
			_hit_cooldown = 1.0
			player.take_damage(damage, global_position, 260.0)
		queue_redraw()

	func _draw() -> void:
		var pulse := 1.0 + 0.08 * sin(_clock * 4.0)
		draw_circle(Vector2(0, 4), 16.0 * pulse, Color(0, 0, 0, 0.35))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -34), Vector2(14, 6), Vector2(-14, 6)]), Color(0.05, 0.03, 0.09, 0.92))
		draw_circle(Vector2(0, -20), 9.0 * pulse, Color(0.05, 0.03, 0.09, 0.95))
		draw_circle(Vector2(-3.5, -21), 1.8, Color(0.9, 0.2, 0.9))
		draw_circle(Vector2(3.5, -21), 1.8, Color(0.9, 0.2, 0.9))


class RunePlate extends Node2D:
	var index: int = 0
	var color: Color = Color.WHITE
	var lit: bool = false

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 13.0, Color(0.08, 0.06, 0.1))
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 20, color.darkened(0.2) if not lit else color, 2.0)
		draw_circle(Vector2.ZERO, 6.0, color if lit else color.darkened(0.65))


## Shows the order in which the runes must be stepped on (coloured dots; the ones done so far are bright).
class SequenceBoard extends Node2D:
	var order: Array[int] = []
	var progress: int = 0
	var colors: Array[Color] = []

	func _draw() -> void:
		draw_rect(Rect2(-40, -14, 80, 28), Color(0.06, 0.04, 0.08, 0.9))
		draw_rect(Rect2(-40, -14, 80, 28), Color(0.5, 0.2, 0.25), false, 2.0)
		for i in order.size():
			var c: Color = colors[order[i]]
			draw_circle(Vector2(-27 + 18 * i, 0), 6.0, c if i < progress else c.darkened(0.55))
			if i == progress:
				draw_arc(Vector2(-27 + 18 * i, 0), 8.5, 0.0, TAU, 16, Color.WHITE, 1.5)


func _begin_phantom() -> void:
	_order.clear()
	var order: Array = [0, 1, 2, 3]
	order.shuffle()
	for i in order:
		_order.append(i)
	_progress = 0
	var ring := [Vector2(-90, -40), Vector2(90, -40), Vector2(-90, 50), Vector2(90, 50)]
	for i in 4:
		var plate := RunePlate.new()
		plate.index = i
		plate.color = RUNE_COLORS[i]
		RoomKit.spawned(room).add_child(plate)
		plate.global_position = RoomKit.spot(room, ring[i])
		_plates.append(plate)
	_board = SequenceBoard.new()
	_board.order = _order
	_board.colors = RUNE_COLORS
	RoomKit.spawned(room).add_child(_board)
	_board.global_position = RoomKit.spot(room, Vector2(0, -78))
	_phantom = PhantomShadow.new()
	_phantom.z_index = 6
	RoomKit.spawned(room).add_child(_phantom)
	_phantom.global_position = RoomKit.spot(room, Vector2(0, -50))
	_phantom.damage = int(ceil(12.0 * cfg.damage_mult))
	GameManager.room_banner.emit("STEP ON THE RUNES IN THE SHOWN ORDER. THE SHADOW CANNOT BE KILLED.", SpecialRooms.CURSE_COLOR)
	Audio.play(preload("res://assets/sounds/explosion.wav"), -6.0, 0.4)


func _tick_phantom(delta: float) -> void:
	_plate_lock = maxf(0.0, _plate_lock - delta)
	if _plate_lock > 0.0 or _plates.is_empty() or _progress >= _order.size():
		return
	var player := RoomKit.player()
	for plate in _plates:
		if player.global_position.distance_to(plate.global_position) > 15.0:
			continue
		if plate.index == _order[_progress]:
			plate.lit = true
			plate.queue_redraw()
			_progress += 1
			_board.progress = _progress
			_board.queue_redraw()
			_plate_lock = 0.6
			Audio.play(preload("res://assets/sounds/coin.wav"), -6.0, 0.8 + 0.15 * _progress)
			if _progress >= _order.size():
				_solve_phantom()
			return
		elif not plate.lit:
			_wrong_rune()
			return


func _wrong_rune() -> void:
	_progress = 0
	_plate_lock = 1.0
	for plate in _plates:
		plate.lit = false
		plate.queue_redraw()
	_board.progress = 0
	_board.queue_redraw()
	var player := RoomKit.player()
	player.take_damage(int(ceil(8.0 * cfg.damage_mult)), player.global_position + Vector2(0, 8), 80.0)
	RoomKit.toast("THE WRONG RUNE: THE ORDER RESETS", Color(1.0, 0.5, 0.4))


func _solve_phantom() -> void:
	if is_instance_valid(_phantom):
		BossFX.puff(RoomKit.spawned(room), _phantom.global_position, 1.2)
		_phantom.queue_free()
	await get_tree().create_timer(0.6).timeout
	for plate in _plates:
		if is_instance_valid(plate):
			plate.queue_free()
	_plates.clear()
	if is_instance_valid(_board):
		_board.queue_free()
	_win()


# ------------------------------------------------------------------ the Cursed Hoard

func _open_hoard() -> void:
	var ring := [Vector2(-80, -30), Vector2(80, -30), Vector2(-100, 40), Vector2(100, 40), Vector2(0, -70)]
	var real := randi() % 5
	for i in 5:
		var chest := RoomKit.altar(room, &"chest", "OPEN THE CHEST", Color(1.0, 0.85, 0.4), func(_by: Node) -> void: pass, ring[i])
		chest.callback = _open_hoard_chest.bind(chest, i == real)


func _open_hoard_chest(_by: Node, chest: Altar, is_real: bool) -> void:
	chest.opened = true
	chest.enabled = false
	chest.disabled_prompt = ""
	chest.visible = true
	if is_real:
		_give_legendary(chest.global_position)
		chest.disabled_prompt = "EMPTY"
		return
	chest.visible = false
	var mimic := generator._spawn_enemy(room, MIMIC_PATH, chest.global_position, {"is_elite": true}) as EnemyBase
	if mimic != null:
		mimic.wake_up()
	RoomKit.toast("IT BITES!", Color(1.0, 0.4, 0.3))
	GameManager.shake_camera(4.0, 0.25)


func _give_legendary(at: Vector2) -> void:
	var pool: Array = RunData.BLUEPRINTS.keys().filter(func(id: StringName) -> bool: return not Run.blueprints.has(id) and not Run.carried_blueprints.has(id))
	if pool.is_empty():
		Loot.drop_materials(RoomKit.spawned(room), at, 6, depth, 3)
		RoomKit.toast("THE REAL CHEST: MATERIALS FIT FOR A KING", Color(1.0, 0.85, 0.4))
		return
	var id: StringName = pool[randi() % pool.size()]
	Pickup.spawn(RoomKit.spawned(room), at + Vector2(0, 8), Pickup.Kind.BLUEPRINT, 1, id)
	Loot.drop_materials(RoomKit.spawned(room), at, 3, depth, RoomKit.tier(depth, 1))
	RoomKit.toast("THE REAL CHEST: A BLUEPRINT!", Color(1.0, 0.85, 0.4))
	GameManager.shake_camera(4.0, 0.3)
