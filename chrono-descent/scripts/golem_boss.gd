class_name GolemBoss
extends BossBase
## BOSS: the Ancient Golem. A slow, huge stone guardian with three attacks (and no helpers: it never summons):
##
##   SPIN   it winds up with its arms out (red "!" warning), then SPINS: it whirls after the player, damaging
##          everything in a ring around it again and again, and ends DIZZY: a window where it takes more damage
##   SLAM   it raises both fists while a red ellipse fills on the floor, then smashes the ground: a shockwave
##          hits everything inside the ellipse; the floor cracks and rocks fly
##   THROW  it gathers a glowing orb (a dashed line shows where it aims), then hurls it; the orb bursts on contact
##
## At half health it ENRAGES: faster, longer spins, a double slam and a three-orb throw.
## The shared boss machinery (entrance, step sequencer, super-armor) is in BossBase.

const ORB_PATH: String = "res://scenes/enemies/golem_orb_boss.tscn"
const KIND: int = GolemFX.Kind.BOSS
const SLAM_RADIUS: float = 74.0
const SLAM_RAISE_TIME: float = 0.8
const SPIN_TIME: float = 1.9
const SPIN_SPEED: float = 82.0
const ENRAGE_AT: float = 0.5
const ORANGE: Color = Color(1.0, 0.55, 0.2)

static var _orb_scene: PackedScene

var _enraged: bool = false
var _dizzy: bool = false
var _slam_center: Vector2 = Vector2.ZERO
var _telegraph: AnimatedSprite2D
var _aim_line: Sprite2D
var _charge_fx: AnimatedSprite2D
var _arcs: GolemFX.SpinArcs
var _spin_pulse: float = 0.0
var _dust_timer: float = 0.0

@onready var spin_hitbox: Hitbox = $SpinHitbox


func _ready() -> void:
	super()
	spin_hitbox.damage = int(ceil(8.0 * damage_multiplier))
	spin_hitbox.knockback_force = 240.0
	spin_hitbox.one_hit_per_target = true
	spin_hitbox.set_deferred("monitoring", false)


# ------------------------------------------------------------ entrance

## It claws its way up out of the floor.
func _play_intro_effects() -> void:
	var host := get_parent()
	GolemFX.cracks(host, global_position + Vector2(0, 8), KIND, 1.3, 3.0)
	GolemFX.dust(host, global_position + Vector2(0, 10), KIND, 1.0)
	GolemFX.chips(host, global_position, KIND, 16, 150.0)
	Audio.play_2d(THUD_SFX, global_position, 0.0, 0.35)
	var final_scale := scale
	scale = final_scale * 0.4
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", final_scale, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)


func _intro_steps() -> Array[Dictionary]:
	return [
		{"time": INTRO_TIME * 0.5, "anim": "idle"},
		{"time": INTRO_TIME * 0.5, "anim": "raise", "fit": INTRO_TIME * 0.5, "exit": _intro_pound},
	]


func _intro_pound() -> void:
	var host := get_parent()
	GolemFX.shock_ring(host, global_position + Vector2(0, 8), KIND, 110.0, 0.7)
	GolemFX.dust(host, global_position + Vector2(0, 10), KIND, 1.2)
	GolemFX.chips(host, global_position, KIND, 12, 130.0)
	Audio.play_2d(ROAR_SFX, global_position, 0.0, 0.3)
	GameManager.shake_camera(9.0, 0.6)


# ------------------------------------------------------------ choosing attacks

func _preferred_distance() -> float:
	return 56.0


func _pause_after_attack() -> float:
	return 0.55 if _enraged else 0.85


func _choose_attack() -> StringName:
	var distance := _to_player().length()
	var spin_w := 3.0 if distance < 120.0 else 1.5
	var slam_w := 3.5 if distance < 110.0 else 1.2
	var throw_w := 1.5 if distance < 110.0 else 4.0
	return _weighted_pick([[&"spin", spin_w], [&"slam", slam_w], [&"throw", throw_w]])


func _build_attack(kind: StringName) -> Array[Dictionary]:
	match kind:
		&"spin":
			return _build_spin()
		&"slam":
			return _build_slam()
	return _build_throw()


func _damage_taken_mult() -> float:
	return 1.35 if _dizzy else 1.0


# ------------------------------------------------------------ SPIN

func _build_spin() -> Array[Dictionary]:
	var duration := SPIN_TIME * (1.3 if _enraged else 1.0)
	return [
		{"time": 0.75, "anim": "spin", "fit": 3.2, "enter": _begin_spin_wind, "exit": _end_spin_wind},
		{"time": duration, "anim": "spin", "enter": _begin_spin, "tick": _tick_spin, "exit": _end_spin},
		{"time": 1.15, "anim": "idle", "enter": _begin_dizzy, "exit": _end_dizzy},
	]


func _begin_spin_wind() -> void:
	_face(_to_player())
	BossFX.alert(self, 0.75, -64.0)
	anim.self_modulate = Color(1.0, 0.65, 0.55)
	Audio.play_2d(ROAR_SFX, global_position, -4.0, 0.5)
	GolemFX.dust(get_parent(), global_position + Vector2(0, 12), KIND, 0.6)


func _end_spin_wind() -> void:
	anim.self_modulate = body_tint


func _begin_spin() -> void:
	_set_hitbox_node(spin_hitbox, true)
	_arcs = GolemFX.spin_arcs(self, 50.0)
	_arcs.position = Vector2(0.0, 8.0)
	_spin_pulse = 0.0
	_dust_timer = 0.0
	Audio.play_2d(THUD_SFX, global_position, -2.0, 0.45)
	GameManager.shake_camera(3.0, 0.3)


func _tick_spin(delta: float) -> void:
	var to := _to_player()
	_face(to)
	_intent = to.normalized() * SPIN_SPEED * (1.25 if _enraged else 1.0)
	_spin_pulse -= delta
	if _spin_pulse <= 0.0:
		_spin_pulse = 0.4
		spin_hitbox.pulse() # damages the player again every 0.4 s while standing in the ring
	_dust_timer -= delta
	if _dust_timer <= 0.0:
		_dust_timer = 0.17
		GolemFX.dust(get_parent(), global_position + Vector2(randf_range(-14.0, 14.0), 14.0), KIND, 0.5)
		GameManager.shake_camera(1.2, 0.1)


func _end_spin() -> void:
	_set_hitbox_node(spin_hitbox, false)
	if is_instance_valid(_arcs):
		_arcs.queue_free()
	_arcs = null


## After a spin it staggers, dizzy: the moment to hit it (it takes extra damage).
func _begin_dizzy() -> void:
	_dizzy = true
	anim.self_modulate = Color(1.0, 0.9, 0.55)
	GolemFX.dust(get_parent(), global_position + Vector2(0, 12), KIND, 0.7)


func _end_dizzy() -> void:
	_dizzy = false
	anim.self_modulate = body_tint


# ------------------------------------------------------------ SLAM

func _build_slam() -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var count := 2 if _enraged else 1
	for i in count:
		var raise_time := SLAM_RAISE_TIME if i == 0 else 0.55
		steps.append({"time": raise_time, "anim": "raise", "fit": raise_time, "enter": _begin_raise.bind(raise_time), "exit": _end_raise})
		steps.append({"time": 0.55, "anim": "slam", "enter": _do_slam})
	steps.append({"time": 0.75, "anim": "idle"})
	return steps


func _begin_raise(raise_time: float) -> void:
	_face(_to_player())
	_slam_center = global_position + Vector2(0.0, 8.0)
	_telegraph = GolemFX.slam_telegraph(get_parent(), _slam_center, KIND, SLAM_RADIUS, raise_time)
	BossFX.alert(self, 0.5, -64.0)
	Audio.play_2d(ROAR_SFX, global_position, -5.0, 0.55)


func _end_raise() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null


## The fists hit the floor: the shockwave damages everything inside the red ellipse.
func _do_slam() -> void:
	var host := get_parent()
	if player != null and GolemFX.ellipse_contains(_slam_center, SLAM_RADIUS, player.global_position):
		player.take_damage(int(ceil(18.0 * damage_multiplier)), global_position, 340.0)
	GolemFX.shock_ring(host, _slam_center, KIND, SLAM_RADIUS, 0.55)
	GolemFX.cracks(host, _slam_center, KIND, 1.0)
	GolemFX.dust(host, _slam_center + Vector2(-26.0, 6.0), KIND, 0.8)
	GolemFX.dust(host, _slam_center + Vector2(26.0, 6.0), KIND, 0.8)
	GolemFX.chips(host, _slam_center, KIND, 14, 150.0)
	Audio.play_2d(THUD_SFX, global_position, 0.0, 0.4)
	GameManager.shake_camera(8.0, 0.45)


# ------------------------------------------------------------ THROW

func _build_throw() -> Array[Dictionary]:
	return [
		{"time": 0.75, "anim": "charge", "fit": 0.75, "enter": _begin_throw_charge, "tick": _tick_throw_charge, "exit": _end_throw_charge},
		{"time": 0.5, "anim": "cast", "enter": _release_throw},
		{"time": 0.6, "anim": "idle"},
	]


func _begin_throw_charge() -> void:
	_face(_to_player())
	_dash_dir = _to_player().normalized()
	_aim_line = GolemFX.aim_line(get_parent(), global_position, _dash_dir, 340.0, KIND)
	_charge_fx = GolemFX.animated(self, Vector2.ZERO, KIND, "charge", 12.0, true, 0.5, 6)
	_charge_fx.position = Vector2(0.0, -10.0) + _dash_dir * 16.0
	Audio.play_2d(ROAR_SFX, global_position, -6.0, 0.7)


func _tick_throw_charge(_delta: float) -> void:
	# keeps aiming until the last moment, then the line freezes: the player's cue to sidestep
	if _step_time < float(_step["time"]) - 0.2:
		_dash_dir = _to_player().normalized()
		_face(_dash_dir)
	if is_instance_valid(_aim_line):
		_aim_line.rotation = _dash_dir.angle()
		_aim_line.global_position = global_position + Vector2(0.0, -6.0)
	if is_instance_valid(_charge_fx):
		_charge_fx.position = Vector2(0.0, -10.0) + _dash_dir * 16.0


func _end_throw_charge() -> void:
	if is_instance_valid(_aim_line):
		_aim_line.queue_free()
	if is_instance_valid(_charge_fx):
		_charge_fx.queue_free()
	_aim_line = null
	_charge_fx = null


func _release_throw() -> void:
	if _orb_scene == null:
		_orb_scene = load(ORB_PATH) as PackedScene
	if _orb_scene == null:
		return
	var angles: Array = [-0.3, 0.0, 0.3] if _enraged else [0.0]
	for a in angles:
		var orb := _orb_scene.instantiate() as BossOrb
		get_parent().add_child(orb)
		orb.global_position = global_position + _dash_dir * 18.0 + Vector2(0.0, -8.0)
		orb.scale = Vector2.ONE * 1.25
		orb.setup(_dash_dir.rotated(float(a)), 175.0, int(ceil(12.0 * damage_multiplier)), 200.0, 3.6)
	Audio.play_2d(THUD_SFX, global_position, -3.0, 0.7)
	GameManager.shake_camera(2.5, 0.2)


# ------------------------------------------------------------ enraging and dying

func _after_damage() -> void:
	if not _enraged and health.current_health > 0 and health.current_health <= int(float(health.max_health) * ENRAGE_AT):
		_begin_enrage()


## At half health it roars, glowing hotter: faster, longer spins, a double slam and a three-orb throw.
func _begin_enrage() -> void:
	_enraged = true
	_phase = Phase.TRANSFORM
	_invulnerable = true
	_interrupt()
	_end_dizzy()
	move_speed *= 1.25
	body_tint = Color(1.0, 0.78, 0.68)
	anim.self_modulate = body_tint
	_steps = [{"time": 1.0, "anim": "raise", "fit": 1.0, "enter": _enrage_roar, "exit": _enrage_done}]
	_next_step()


func _enrage_roar() -> void:
	var host := get_parent()
	GolemFX.shock_ring(host, global_position + Vector2(0, 8), KIND, 130.0, 0.8)
	GolemFX.cracks(host, global_position + Vector2(0, 8), KIND, 1.4, 4.0)
	GolemFX.dust(host, global_position + Vector2(0, 10), KIND, 1.2)
	GolemFX.chips(host, global_position, KIND, 16, 160.0)
	Audio.play_2d(ROAR_SFX, global_position, 0.0, 0.3)
	GameManager.shake_camera(9.0, 0.7)
	GameManager.boss_announce.emit("THE GOLEM ENRAGES!")


func _enrage_done() -> void:
	_phase = Phase.FIGHT
	_invulnerable = false
	_attack_pause = 0.4
	_roam_time = 0.0


func _on_died() -> void:
	var host := get_parent()
	GolemFX.dust(host, global_position + Vector2(0, 10), KIND, 1.3)
	GolemFX.chips(host, global_position, KIND, 18, 170.0)
	GolemFX.cracks(host, global_position + Vector2(0, 8), KIND, 1.2, 3.0)
	_end_throw_charge()
	_end_raise()
	_end_spin()
	super()
