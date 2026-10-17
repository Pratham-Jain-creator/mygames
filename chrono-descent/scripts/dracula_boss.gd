class_name DraculaBoss
extends BossBase
## BOSS: Count Dracula (sprites: dracula_boss.png), the last guardian of floor 10. He summons far more bats than his
## minions ever do. Attacks, all telegraphed:
##   SLASH   three lunging claw slashes in a row (four when enraged)
##   ORBS    a fan of blood orbs flung at you
##   BATS    he calls a swarm of bats (4, or 6 enraged) that keep harassing you while he fights
##   MIST    he dissolves into bats, reappears behind you and slashes
## At half health he ENRAGES: a roar that calls more bats, then everything comes faster and bigger.

const CELL_SCALE: float = 0.36
const SLASH_RADIUS: float = 40.0
const ORB_SPEED: float = 105.0
const MAX_BATS: int = 10

var _enraged: bool = false
var _lunge_hit: bool = false
var _stage: int = 0
var _fired: int = 0


## A blood orb: flies straight, vanishes on walls, hurts the player on contact.
class BloodOrb extends Node2D:
	var dir: Vector2 = Vector2.DOWN
	var speed: float = 105.0
	var damage: int = 10
	var _life: float = 4.0
	var _t: float = 0.0

	func _physics_process(delta: float) -> void:
		_t += delta
		_life -= delta
		var step := dir * speed * delta
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, 1)
		if _life <= 0.0 or not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			queue_free()
			return
		global_position += step
		var player := GameManager.player
		if is_instance_valid(player) and not player.is_dead and player.global_position.distance_to(global_position + Vector2(0, 2)) < 9.0:
			player.take_damage(damage, global_position - dir * 10.0, 200.0)
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var pulse := 1.0 + 0.15 * sin(_t * 18.0)
		draw_circle(Vector2.ZERO, 8.0 * pulse, Color(0.9, 0.1, 0.2, 0.22))
		draw_circle(Vector2.ZERO, 4.5 * pulse, Color(0.85, 0.08, 0.15))
		draw_circle(Vector2(-1.2, -1.2), 1.4, Color(1.0, 0.7, 0.7, 0.9))


func _setup_frames() -> void:
	anim.sprite_frames = SpriteLib.dracula_boss()
	anim.play("idle_down")


# ------------------------------------------------------------ entrance

func _play_intro_effects() -> void:
	var host := get_parent()
	BossFX.burst(host, global_position, Color(0.35, 0.2, 0.5), 26, 120.0)
	BossFX.puff(host, global_position, 1.3)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.7)


func _intro_steps() -> Array[Dictionary]:
	return [
		{"time": INTRO_TIME * 0.65, "anim": "reform", "fit": INTRO_TIME * 0.65},
		{"time": INTRO_TIME * 0.35, "anim": "bigcast", "fit": INTRO_TIME * 0.35, "exit": _intro_roar},
	]


func _intro_roar() -> void:
	var host := get_parent()
	BossFX.ring(host, global_position, Color(0.9, 0.15, 0.25), 130.0, 0.8)
	Audio.play_2d(ROAR_SFX, global_position, 0.0, 0.4)
	GameManager.shake_camera(6.0, 0.5)


# ------------------------------------------------------------ choosing attacks

func _preferred_distance() -> float:
	return 70.0


func _pause_after_attack() -> float:
	return 0.45 if _enraged else 0.8


func _choose_attack() -> StringName:
	var distance := _to_player().length()
	var options: Array = [[&"slash", 3.0 if distance < 120.0 else 1.2], [&"orbs", 2.5 if distance > 60.0 else 1.0], [&"mist", 2.0]]
	if _live_bats() < MAX_BATS - 3:
		options.append([&"bats", 3.0])
	return _weighted_pick(options)


func _build_attack(kind: StringName) -> Array[Dictionary]:
	match kind:
		&"slash":
			return _build_slash()
		&"orbs":
			return _build_orbs()
		&"bats":
			return _build_bats()
	return _build_mist()


func _live_bats() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("boss_minion"):
		if node is Bat and is_instance_valid(node) and not (node as Bat)._dead:
			n += 1
	return n


# ------------------------------------------------------------ SLASH

func _build_slash() -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for i in (4 if _enraged else 3):
		steps.append({"time": 0.45 if i == 0 else 0.3, "anim": "attack", "fit": 0.75, "enter": _slash_windup, "tick": _slash_aim})
		steps.append({"time": 0.24, "enter": _slash_lunge, "tick": _slash_tick})
	steps.append({"time": 0.7, "anim": "idle"})
	return steps


func _slash_windup() -> void:
	_face(_to_player())
	_dash_dir = _to_player().normalized()
	anim.self_modulate = Color(1.0, 0.65, 0.65)
	BossFX.alert(self, 0.4, -50.0)


func _slash_aim(_delta: float) -> void:
	if _step_time < float(_step["time"]) - 0.12:
		_dash_dir = _to_player().normalized()
		_face(_dash_dir)


func _slash_lunge() -> void:
	anim.self_modulate = body_tint
	_lunge_hit = false
	GameManager.shake_camera(2.0, 0.12)


func _slash_tick(_delta: float) -> void:
	_intent = _dash_dir * 250.0
	if not _lunge_hit and player != null and global_position.distance_to(player.global_position) < SLASH_RADIUS:
		_lunge_hit = true
		player.take_damage(int(ceil(15.0 * damage_multiplier)), global_position, 280.0)


# ------------------------------------------------------------ ORBS

func _build_orbs() -> Array[Dictionary]:
	return [
		{"time": 0.95, "anim": "cast", "fit": 0.95, "enter": _orbs_begin, "tick": _orbs_tick},
		{"time": 0.5, "anim": "idle"},
	]


func _orbs_begin() -> void:
	_face(_to_player())
	_fired = 0
	BossFX.alert(self, 0.5, -50.0)


func _orbs_tick(_delta: float) -> void:
	if _fired == 0 and _step_time >= 0.55:
		_fired = 1
		var count := 7 if _enraged else 5
		var base := _to_player().normalized()
		var spread := deg_to_rad(70.0 if _enraged else 55.0)
		for i in count:
			var orb := BloodOrb.new()
			orb.dir = base.rotated(lerpf(-spread * 0.5, spread * 0.5, float(i) / float(count - 1)))
			orb.speed = ORB_SPEED * (1.2 if _enraged else 1.0)
			orb.damage = int(ceil(10.0 * damage_multiplier))
			orb.z_index = 5
			get_parent().add_child(orb)
			orb.global_position = global_position + Vector2(0, -8)
		Audio.play_2d(SPIT_SFX, global_position, -4.0, 0.7)


# ------------------------------------------------------------ BATS

func _build_bats() -> Array[Dictionary]:
	return [
		{"time": 1.3, "anim": "summon", "fit": 1.3, "enter": _bats_begin, "tick": _bats_tick},
		{"time": 0.4, "anim": "idle"},
	]


func _bats_begin() -> void:
	_face(_to_player())
	_fired = 0
	BossFX.alert(self, 0.6, -50.0)
	Audio.play_2d(ROAR_SFX, global_position, -3.0, 0.5)


func _bats_tick(_delta: float) -> void:
	if _fired == 0 and _step_time >= 0.75:
		_fired = 1
		_call_bats(6 if _enraged else 4)


func _call_bats(count: int) -> void:
	count = mini(count, MAX_BATS - _live_bats())
	if count <= 0:
		return
	BossFX.puff(get_parent(), global_position, 1.0)
	Bat.summon(get_parent(), global_position + Vector2(0, -10), count, health_multiplier, damage_multiplier, true)


# ------------------------------------------------------------ MIST (dissolve into bats, reappear, slash)

func _build_mist() -> Array[Dictionary]:
	var steps: Array[Dictionary] = [
		{"time": 0.6, "anim": "dissolve", "fit": 0.6, "enter": _mist_begin, "done": _mist_vanish},
		{"time": 0.4},
		{"time": 0.6, "anim": "reform", "fit": 0.6, "enter": _mist_appear, "exit": _mist_end},
	]
	steps.append({"time": 0.3, "anim": "attack", "fit": 0.75, "enter": _slash_windup, "tick": _slash_aim})
	steps.append({"time": 0.24, "enter": _slash_lunge, "tick": _slash_tick})
	steps.append({"time": 0.6, "anim": "idle"})
	return steps


func _mist_begin() -> void:
	BossFX.burst(get_parent(), global_position, Color(0.3, 0.2, 0.45), 16, 90.0)


func _mist_vanish() -> void:
	_invulnerable = true
	anim.visible = false
	# he comes back close behind the player
	var target := player.global_position + Vector2.from_angle(randf() * TAU) * 55.0
	if arena != null:
		target = arena.nearest_free_point(target, 1)
	global_position = target


func _mist_appear() -> void:
	anim.visible = true
	_face(_to_player())
	BossFX.burst(get_parent(), global_position, Color(0.3, 0.2, 0.45), 16, 90.0)


func _mist_end() -> void:
	anim.visible = true
	if _phase == Phase.FIGHT:
		_invulnerable = false


# ------------------------------------------------------------ enraging

func _after_damage() -> void:
	if not _enraged and health.current_health > 0 and health.current_health <= int(float(health.max_health) * 0.5):
		_begin_enrage()


func _begin_enrage() -> void:
	_enraged = true
	_phase = Phase.TRANSFORM
	_invulnerable = true
	_interrupt()
	anim.visible = true
	move_speed *= 1.25
	body_tint = Color(1.0, 0.8, 0.8)
	anim.self_modulate = body_tint
	_steps = [{"time": 1.2, "anim": "bigcast", "fit": 1.2, "enter": _enrage_roar, "exit": _enrage_done}]
	_next_step()


func _enrage_roar() -> void:
	var host := get_parent()
	BossFX.ring(host, global_position, Color(0.95, 0.1, 0.2), 150.0, 0.8)
	Audio.play_2d(ROAR_SFX, global_position, 0.0, 0.3)
	GameManager.shake_camera(8.0, 0.7)
	GameManager.boss_announce.emit("THE COUNT'S HUNGER WAKES!")
	_call_bats(5)


func _enrage_done() -> void:
	_phase = Phase.FIGHT
	_invulnerable = false
	_attack_pause = 0.4
	_roam_time = 0.0


func _on_died() -> void:
	anim.visible = true
	BossFX.burst(get_parent(), global_position, Color(0.3, 0.2, 0.45), 22, 120.0)
	super()
