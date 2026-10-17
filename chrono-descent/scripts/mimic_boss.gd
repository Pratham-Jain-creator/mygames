class_name MimicBoss
extends BossBase
## BOSS: the Great Mimic (sprites: mimic_boss.png). A gilded chest the size of a wagon, with teeth. It never summons
## anything until it is ENRAGED at half health. Attacks, all telegraphed in red:
##   BITE   three lunging bites in a row, then it gasps for air: the opening
##   LASH   its tongue aims at you (a red line), then whips along it; twice in a row
##   SLAM   it leaps to a red circle where you stand and lands with a shockwave
##   CALL   (enraged only) two small mimics tear themselves off its lid
## The shared boss machinery (entrance, step sequencer, super-armor) is in BossBase.

const SHEET: String = "res://assets/sprites/enemies/boss/mimic_boss.png"
const CELL: int = 224
const MINION_PATH: String = "res://scenes/enemies/mimic_chest.tscn"
const LASH_LENGTH: float = 175.0
const LASH_REACH: float = 13.0
const SLAM_RADIUS: float = 58.0
const RED := Color(1.0, 0.25, 0.25)

var _enraged: bool = false
var _lunge_hit: bool = false
var _lash_dir: Vector2 = Vector2.DOWN
var _lash_done: bool = false
var _line: Line2D
var _circle: TelegraphCircle
var _slam_target: Vector2 = Vector2.ZERO
var _slam_stage: int = 0
var _called: bool = false
var _minions: Array[Node] = []


## A red disc on the floor: where the slam will land.
class TelegraphCircle extends Node2D:
	var radius: float = 58.0
	var life: float = 1.0
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_t / maxf(life, 0.05), 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.2, 0.2, 0.12 + 0.14 * k))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(1.0, 0.3, 0.3, 0.8), 2.0)
		draw_arc(Vector2.ZERO, radius * k, 0.0, TAU, 40, Color(1.0, 0.6, 0.5, 0.9), 2.0)


func _setup_frames() -> void:
	anim.sprite_frames = SpriteLib.mimic(SHEET, CELL)
	anim.play("idle_down")


# ------------------------------------------------------------ entrance

## It has been pretending to be a chest. It stops pretending.
func _play_intro_effects() -> void:
	var host := get_parent()
	BossFX.puff(host, global_position + Vector2(0, 10), 1.4)
	BossFX.ring(host, global_position, Color(1.0, 0.7, 0.3), 90.0, 0.7)
	Audio.play_2d(THUD_SFX, global_position, 0.0, 0.4)
	var final_scale := scale
	scale = final_scale * 0.5
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", final_scale, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.4)


func _intro_steps() -> Array[Dictionary]:
	return [
		{"time": INTRO_TIME * 0.35, "anim": "idle"},
		{"time": INTRO_TIME * 0.65, "anim": "reveal", "fit": INTRO_TIME * 0.65, "exit": _intro_roar},
	]


func _intro_roar() -> void:
	var host := get_parent()
	BossFX.ring(host, global_position, Color(1.0, 0.5, 0.3), 140.0, 0.8)
	BossFX.burst(host, global_position, Color(1.0, 0.8, 0.4), 24, 150.0)
	Audio.play_2d(ROAR_SFX, global_position, 0.0, 0.35)
	GameManager.shake_camera(7.0, 0.6)


# ------------------------------------------------------------ choosing attacks

func _preferred_distance() -> float:
	return 62.0


func _pause_after_attack() -> float:
	return 0.5 if _enraged else 0.85


func _choose_attack() -> StringName:
	var distance := _to_player().length()
	var options: Array = [[&"bite", 3.0 if distance < 130.0 else 1.5], [&"lash", 3.0 if distance < 190.0 else 1.5], [&"slam", 2.5]]
	if _enraged and _live_minions() < 2 and not _called:
		options.append([&"call", 4.0])
	var choice := _weighted_pick(options)
	if choice == &"call":
		_called = true
	return choice


func _build_attack(kind: StringName) -> Array[Dictionary]:
	match kind:
		&"bite":
			return _build_bite()
		&"lash":
			return _build_lash()
		&"slam":
			return _build_slam()
	return _build_call()


# ------------------------------------------------------------ BITE

func _build_bite() -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var count := 4 if _enraged else 3
	for i in count:
		steps.append({"time": 0.45 if i == 0 else 0.3, "anim": "attack", "fit": 0.85, "enter": _begin_bite_windup, "tick": _tick_bite_windup})
		steps.append({"time": 0.26, "enter": _begin_lunge, "tick": _tick_lunge})
	steps.append({"time": 0.9, "anim": "idle"}) # out of breath
	return steps


func _begin_bite_windup() -> void:
	_face(_to_player())
	_dash_dir = _to_player().normalized()
	anim.self_modulate = Color(1.0, 0.65, 0.6)
	BossFX.alert(self, 0.4, -58.0)


func _tick_bite_windup(_delta: float) -> void:
	if _step_time < float(_step["time"]) - 0.12:
		_dash_dir = _to_player().normalized()
		_face(_dash_dir)


func _begin_lunge() -> void:
	anim.self_modulate = body_tint
	_lunge_hit = false
	Audio.play_2d(THUD_SFX, global_position, -3.0, 0.6)
	GameManager.shake_camera(2.5, 0.15)


func _tick_lunge(_delta: float) -> void:
	_intent = _dash_dir * 270.0
	if not _lunge_hit and player != null and global_position.distance_to(player.global_position) < 40.0:
		_lunge_hit = true
		player.take_damage(int(ceil(16.0 * damage_multiplier)), global_position, 300.0)


# ------------------------------------------------------------ LASH

func _build_lash() -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for i in 2:
		steps.append({"time": 1.0, "anim": "lash", "fit": 1.0, "enter": _begin_lash, "tick": _tick_lash, "exit": _end_lash})
	steps.append({"time": 0.6, "anim": "idle"})
	return steps


func _begin_lash() -> void:
	_face(_to_player())
	_lash_dir = _to_player().normalized()
	_lash_done = false
	_line = Line2D.new()
	_line.width = 4.0
	_line.default_color = Color(1.0, 0.25, 0.25, 0.7)
	_line.z_index = 4
	add_child(_line)
	Audio.play_2d(ROAR_SFX, global_position, -6.0, 0.9)


func _tick_lash(_delta: float) -> void:
	if _step_time < 0.55:
		_lash_dir = _to_player().normalized()
		_face(_lash_dir)
	if is_instance_valid(_line):
		_line.clear_points()
		_line.add_point(Vector2(0, -6))
		_line.add_point(Vector2(0, -6) + _lash_dir * LASH_LENGTH)
		_line.default_color.a = 0.55 + 0.3 * sin(_step_time * 30.0) if not _lash_done else 0.0
	if not _lash_done and _step_time >= 0.7:
		_lash_done = true
		var origin := global_position + Vector2(0, -6)
		var tip := origin + _lash_dir * LASH_LENGTH
		var target := player.global_position + Vector2(0, 2)
		if Geometry2D.get_closest_point_to_segment(target, origin, tip).distance_to(target) <= LASH_REACH:
			player.take_damage(int(ceil(18.0 * damage_multiplier)), global_position, 280.0)
		GameManager.shake_camera(3.0, 0.15)
		Audio.play_2d(THUD_SFX, global_position, -4.0, 1.3)


func _end_lash() -> void:
	if is_instance_valid(_line):
		_line.queue_free()
	_line = null


# ------------------------------------------------------------ SLAM

func _build_slam() -> Array[Dictionary]:
	return [
		{"time": 1.15, "anim": "slam", "fit": 1.15, "enter": _begin_slam, "tick": _tick_slam, "exit": _end_slam},
		{"time": 0.6, "anim": "idle"},
	]


func _begin_slam() -> void:
	_face(_to_player())
	_slam_target = player.global_position + Vector2(0, 4)
	_slam_stage = 0
	_circle = TelegraphCircle.new()
	_circle.radius = SLAM_RADIUS
	_circle.life = 0.85
	_circle.z_index = 0
	get_parent().add_child(_circle)
	_circle.global_position = _slam_target
	Audio.play_2d(ROAR_SFX, global_position, -5.0, 0.7)


func _tick_slam(_delta: float) -> void:
	if _slam_stage == 0 and _step_time >= 0.4:
		_slam_stage = 1
		create_tween().tween_property(self, "global_position", _slam_target - Vector2(0, 4), 0.4).set_trans(Tween.TRANS_SINE)
	if _slam_stage == 1 and _step_time >= 0.88:
		_slam_stage = 2
		var host := get_parent()
		BossFX.ring(host, _slam_target, Color(1.0, 0.5, 0.3), SLAM_RADIUS, 0.5)
		BossFX.puff(host, _slam_target, 1.2)
		BossFX.burst(host, _slam_target, Color(1.0, 0.8, 0.4), 14, 120.0)
		Audio.play_2d(THUD_SFX, global_position, 0.0, 0.45)
		GameManager.shake_camera(7.0, 0.4)
		if player != null and player.global_position.distance_to(_slam_target) <= SLAM_RADIUS:
			player.take_damage(int(ceil(22.0 * damage_multiplier)), _slam_target, 320.0)


func _end_slam() -> void:
	if is_instance_valid(_circle):
		_circle.queue_free()
	_circle = null


# ------------------------------------------------------------ CALL (enraged only)

func _build_call() -> Array[Dictionary]:
	return [
		{"time": 1.4, "anim": "taunt", "enter": _begin_call, "tick": _tick_call},
		{"time": 0.4, "anim": "idle"},
	]


func _begin_call() -> void:
	_called = false
	_slam_stage = 0
	BossFX.alert(self, 0.6, -58.0)
	Audio.play_2d(ROAR_SFX, global_position, -2.0, 0.55)


func _tick_call(_delta: float) -> void:
	if _slam_stage == 0 and _step_time >= 0.7:
		_slam_stage = 1
		var scene := load(MINION_PATH) as PackedScene
		if scene == null or arena == null:
			return
		var points := arena.find_spawn_points(2, 50.0, arena.get_reserved_points(), 1, 70.0)
		for p in points:
			var minion := scene.instantiate() as EnemyBase
			minion.health_multiplier = health_multiplier
			minion.damage_multiplier = damage_multiplier
			minion.add_to_group("boss_minion")
			get_parent().add_child(minion)
			minion.global_position = p
			minion.wake_up()
			_minions.append(minion)
			BossFX.puff(get_parent(), p, 1.0)


func _live_minions() -> int:
	_minions = _minions.filter(func(m: Node) -> bool: return is_instance_valid(m) and not (m as EnemyBase)._dead)
	return _minions.size()


# ------------------------------------------------------------ enraging

func _after_damage() -> void:
	if not _enraged and health.current_health > 0 and health.current_health <= int(float(health.max_health) * 0.5):
		_begin_enrage()


func _begin_enrage() -> void:
	_enraged = true
	_phase = Phase.TRANSFORM
	_invulnerable = true
	_interrupt()
	move_speed *= 1.2
	body_tint = Color(1.0, 0.75, 0.7)
	anim.self_modulate = body_tint
	_steps = [{"time": 1.0, "anim": "reveal", "fit": 1.0, "enter": _enrage_roar, "exit": _enrage_done}]
	_next_step()


func _enrage_roar() -> void:
	var host := get_parent()
	BossFX.ring(host, global_position, Color(1.0, 0.3, 0.2), 150.0, 0.8)
	BossFX.burst(host, global_position, Color(1.0, 0.6, 0.3), 26, 170.0)
	Audio.play_2d(ROAR_SFX, global_position, 0.0, 0.3)
	GameManager.shake_camera(8.0, 0.7)
	GameManager.boss_announce.emit("THE MIMIC GROWS HUNGRY!")


func _enrage_done() -> void:
	_phase = Phase.FIGHT
	_invulnerable = false
	_attack_pause = 0.4
	_roam_time = 0.0


func _on_died() -> void:
	_end_lash()
	_end_slam()
	BossFX.puff(get_parent(), global_position, 1.4)
	super()
