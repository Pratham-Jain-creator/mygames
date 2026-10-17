class_name SlimeQueen
extends BossBase
## BOSS: the Slime Queen (and, smaller, her fragments). The shared boss machinery lives in BossBase.
##
## Attacks (all telegraphed; none can be interrupted):
##   SPIT    a fan of purple orbs (two volleys for the Queen, one aimed orb for a fragment)
##   DASH    she charges up (red warning lane + "!"), then dashes three times in a row, re-aiming between
##           dashes (a fragment dashes twice), and is exhausted afterwards: the moment to hit her
##   SUMMON  magic circles open on the floor and slimes climb out (the Queen only)
## SPLITTING: at half of her own health she cracks apart into TWO smaller queens that share what is left
## of her health; each of those splits again at half health into TWO normal slimes. The fight is won when
## every piece is dead. BossRoomController keeps the shared health pool and the boss bar.

## Emitted when she (or a fragment) splits: the controller registers the children.
signal split_into(parent: SlimeQueen, children: Array)

const ORB_SCENE: PackedScene = preload("res://scenes/enemies/boss_orb.tscn")
const SLIME_SCENE: PackedScene = preload("res://scenes/enemies/slime.tscn")
## Fraction of her own max health at which a piece splits.
const SPLIT_AT: float = 0.5
const MAX_MINIONS: int = 4
const FRAGMENT_SCALE: float = 0.72
const PURPLE: Color = Color(0.75, 0.4, 1.0)

@export_group("Slime Queen")
## 0 = the Queen herself, 1 = one of her two fragments (they split into normal slimes).
@export var generation: int = 0
## When above 0, this piece starts with exactly this much health (fragments inherit a share of the pool).
@export var fixed_health: int = 0

var _split_started: bool = false
var _lane: Sprite2D
var _summon_points: Array = []
var _summoned: bool = false
var _minions: Array = []


func _ready() -> void:
	super()
	if fixed_health > 0:
		health.max_health = fixed_health
		health.current_health = fixed_health
	if generation > 0:
		melee_damage = 10
		if attack_hitbox:
			attack_hitbox.damage = int(ceil(10.0 * damage_multiplier))
	if attack_hitbox:
		attack_hitbox.one_hit_per_target = true # one hit per dash


# ------------------------------------------------------------ entrance

func _has_intro() -> bool:
	return generation == 0


## She grows out of a summoning circle.
func _play_intro_effects() -> void:
	var host := get_parent()
	BossFX.summon_circle(host, global_position + Vector2(0, 6), INTRO_TIME, 0.85)
	BossFX.burst(host, global_position, PURPLE, 28, 125.0)
	BossFX.ring(host, global_position, PURPLE, 120.0, 0.75)
	Audio.play_2d(ROAR_SFX, global_position, -2.0, 0.5)
	var final_scale := scale
	scale = final_scale * 0.25
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", final_scale, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.45)


func _intro_steps() -> Array[Dictionary]:
	return [
		{"time": INTRO_TIME * 0.45, "anim": "idle"},
		{"time": INTRO_TIME * 0.55, "anim": "summon", "fit": INTRO_TIME * 0.55, "enter": _intro_roar},
	]


func _intro_roar() -> void:
	var host := get_parent()
	BossFX.ring(host, global_position, Color(1.0, 0.85, 1.0), 150.0, 0.8)
	BossFX.burst(host, global_position, Color(0.9, 0.7, 1.0), 20, 150.0)
	Audio.play_2d(ROAR_SFX, global_position, 0.0, 0.4)
	GameManager.shake_camera(5.0, 0.6)


## A freshly split fragment hops out to the side and joins the fight.
func start_fragment(impulse: Vector2) -> void:
	_ensure_free_position()
	visible = true
	set_physics_process(true)
	_phase = Phase.FIGHT
	_attack_pause = 0.9
	_knockback = impulse
	var final_scale := scale
	scale = final_scale * 0.5
	create_tween().tween_property(self, "scale", final_scale, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------ choosing and building attacks

func _preferred_distance() -> float:
	return 64.0


func _pause_after_attack() -> float:
	return 0.5 if generation == 0 else 0.4


func _choose_attack() -> StringName:
	var options: Array = [[&"spit", 3.0], [&"dash", 3.0]]
	if generation == 0 and _live_minions() < MAX_MINIONS:
		options.append([&"summon", 2.5])
	return _weighted_pick(options)


func _build_attack(kind: StringName) -> Array[Dictionary]:
	match kind:
		&"spit":
			return _build_spit()
		&"dash":
			return _build_dash()
	return _build_summon()


func _build_spit() -> Array[Dictionary]:
	var volleys := 2 if generation == 0 else 1
	var steps: Array[Dictionary] = []
	for v in volleys:
		steps.append({"time": 0.34, "anim": "spit", "enter": _aim_at_player, "done": _fire_orbs.bind(v)})
		if v < volleys - 1:
			steps.append({"time": 0.2})
	steps.append({"time": 0.55, "anim": "idle"})
	return steps


func _build_dash() -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var count := 3 if generation == 0 else 2
	for i in count:
		var charge_time := 0.62 if i == 0 else 0.34
		steps.append({"time": charge_time, "anim": "charge", "fit": charge_time, "enter": _begin_charge.bind(i == 0), "tick": _tick_charge, "exit": _end_charge})
		steps.append({"time": 0.32, "anim": "dash", "enter": _begin_dash, "tick": _tick_dash, "exit": _end_dash})
		steps.append({"time": 0.22, "anim": "skid", "tick": _tick_skid})
	steps.append({"time": 0.85 if generation == 0 else 0.7, "anim": "idle"}) # exhausted: the opening
	return steps


func _build_summon() -> Array[Dictionary]:
	return [
		{"time": 1.0, "anim": "summon", "fit": 1.0, "enter": _begin_summon, "tick": _tick_summon},
		{"time": 0.5, "anim": "idle"},
	]


# ------------------------------------------------------------ spit

func _aim_at_player() -> void:
	_face(_to_player())


func _fire_orbs(volley: int) -> void:
	if player == null or not is_inside_tree():
		return
	var dir := _to_player().normalized()
	var angles: Array = [0.0]
	if generation == 0:
		angles = [-0.38, 0.0, 0.38] if volley == 0 else [-0.57, -0.19, 0.19, 0.57]
	var orb_damage := int(ceil((9.0 if generation == 0 else 7.0) * damage_multiplier))
	for a in angles:
		var orb := ORB_SCENE.instantiate() as BossOrb
		get_parent().add_child(orb)
		orb.global_position = global_position + dir * 12.0
		orb.scale = Vector2.ONE * (1.0 if generation == 0 else 0.8)
		orb.setup(dir.rotated(float(a)), 150.0 if generation == 0 else 135.0, orb_damage, 110.0, 3.2)
	Audio.play_2d(SPIT_SFX, global_position, -2.0, 0.55)
	GameManager.shake_camera(1.2, 0.1)


# ------------------------------------------------------------ multi dash

func _dash_speed() -> float:
	return 270.0 if generation == 0 else 235.0


func _begin_charge(first: bool) -> void:
	_face(_to_player())
	_dash_dir = _to_player().normalized()
	if first:
		BossFX.alert(self, 0.7)
		Audio.play_2d(ROAR_SFX, global_position, -6.0, 0.8)
	_lane = BossFX.dash_lane(get_parent(), global_position, _dash_dir, 330.0)
	anim.self_modulate = Color(1.0, 0.6, 0.65)


func _tick_charge(_delta: float) -> void:
	# keeps aiming at the player until the last moment, then locks: the player's cue to move
	if _step_time < float(_step["time"]) - 0.14:
		_dash_dir = _to_player().normalized()
		_face(_dash_dir)
	if is_instance_valid(_lane):
		_lane.rotation = _dash_dir.angle()
		_lane.global_position = global_position
		_lane.modulate.a = 0.6 + 0.3 * sin(_step_time * 30.0)


func _end_charge() -> void:
	anim.self_modulate = body_tint
	if is_instance_valid(_lane):
		var lane := _lane
		_lane = null
		var tween := lane.create_tween()
		tween.tween_property(lane, "modulate:a", 0.0, 0.12)
		tween.tween_callback(lane.queue_free)


func _begin_dash() -> void:
	_set_hitbox(true)
	Audio.play_2d(THUD_SFX, global_position, -3.0, 0.6)
	GameManager.shake_camera(2.5, 0.15)
	BossFX.burst(get_parent(), global_position, Color(0.8, 0.55, 1.0), 10, 60.0)


func _tick_dash(_delta: float) -> void:
	_intent = _dash_dir * _dash_speed()
	# slamming into a wall ends the dash with a bang
	if _step_time > 0.06 and get_slide_collision_count() > 0:
		GameManager.shake_camera(3.5, 0.2)
		BossFX.ring(get_parent(), global_position, PURPLE, 46.0, 0.3)
		_step_time = float(_step["time"])


func _end_dash() -> void:
	_set_hitbox(false)


func _tick_skid(_delta: float) -> void:
	_intent = _dash_dir * _dash_speed() * 0.5 * (1.0 - clampf(_step_time / 0.22, 0.0, 1.0))


# ------------------------------------------------------------ summon

func _begin_summon() -> void:
	_face(_to_player())
	var count := 2 if health.current_health > int(health.max_health * 0.75) else 3
	_summon_points = _pick_summon_points(count)
	_summoned = false
	for p in _summon_points:
		BossFX.summon_circle(get_parent(), p, 0.95, 0.4)
	BossFX.ring(get_parent(), global_position, Color(1.0, 0.6, 0.9), 70.0, 0.6)
	Audio.play_2d(ROAR_SFX, global_position, -3.0, 0.6)


func _tick_summon(_delta: float) -> void:
	if not _summoned and _step_time >= 0.7:
		_summoned = true
		_spawn_minions()


func _pick_summon_points(count: int) -> Array:
	var points: Array = []
	if arena != null:
		var found: Array = arena.find_spawn_points(count, 56.0, arena.get_reserved_points(), 1, 90.0)
		points = found
	while points.size() < count:
		points.append(global_position + Vector2.from_angle(randf() * TAU) * 70.0)
	return points


func _spawn_minions() -> void:
	for p in _summon_points:
		BossFX.puff(get_parent(), p, 0.9)
		var slime := SLIME_SCENE.instantiate() as EnemyBase
		slime.health_multiplier = health_multiplier
		slime.damage_multiplier = damage_multiplier
		slime.add_to_group("boss_minion")
		get_parent().add_child(slime)
		slime.global_position = p
		slime.wake_up()
		_minions.append(slime)
	GameManager.shake_camera(2.0, 0.2)


func _live_minions() -> int:
	_minions = _minions.filter(func(m: Variant) -> bool: return is_instance_valid(m) and not (m as EnemyBase)._dead)
	return _minions.size()


# ------------------------------------------------------------ splitting

func _after_damage() -> void:
	_check_split()


func _check_split() -> void:
	if _split_started or _dead:
		return
	if health.current_health > 0 and health.current_health <= int(float(health.max_health) * SPLIT_AT):
		_begin_split()


func _begin_split() -> void:
	_split_started = true
	_phase = Phase.TRANSFORM
	_invulnerable = true
	_interrupt()
	_steps = [{"time": 0.36, "anim": "split", "enter": _split_enter, "done": _do_split}]
	_next_step()


func _split_enter() -> void:
	modulate = Color(2.4, 2.4, 2.4)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.3)
	BossFX.ring(get_parent(), global_position, Color(1.0, 0.9, 1.0), 90.0, 0.5)
	Audio.play_2d(ROAR_SFX, global_position, -2.0, 0.45)
	GameManager.shake_camera(4.0, 0.35)


## The halves fly apart: two smaller queens (or, from a fragment, two normal slimes) share what is left.
func _do_split() -> void:
	var host := get_parent()
	var half := maxi(1, int(float(health.current_health) / 2.0))
	var kids: Array = []
	for side in [-1.0, 1.0]:
		var kid: EnemyBase
		if generation == 0:
			kid = (load(scene_file_path) as PackedScene).instantiate() as EnemyBase
			kid.set("generation", generation + 1)
			kid.set("fixed_health", half)
			kid.set("arena", arena)
			kid.scale = scale * FRAGMENT_SCALE
		else:
			kid = SLIME_SCENE.instantiate() as EnemyBase
			kid.body_tint = Color(0.92, 0.78, 1.0)
		kid.health_multiplier = 1.0
		kid.damage_multiplier = damage_multiplier
		host.add_child(kid)
		kid.global_position = global_position + Vector2(side * 22.0, 0.0)
		if generation != 0:
			kid.health.max_health = half
			kid.health.current_health = half
		kids.append(kid)
		var impulse := Vector2(side * 150.0, -30.0)
		if kid is SlimeQueen:
			(kid as SlimeQueen).start_fragment(impulse)
		else:
			kid.wake_up()
			kid._knockback = impulse
		BossFX.puff(host, kid.global_position, 0.9)
	BossFX.burst(host, global_position, Color(0.75, 0.45, 1.0), 26, 140.0)
	BossFX.ring(host, global_position, PURPLE, 70.0, 0.4)
	split_into.emit(self, kids)
	visible = false
	queue_free()
