class_name BossBase
extends EnemyBase
## Shared brain of every boss (the Slime Queen, the Golem...). A boss is an EnemyBase that
##   - makes an ENTRANCE (invulnerable, a short show of force) before the fight begins,
##   - ROAMS between attacks (walks after the player) and then picks the next attack,
##   - performs an attack as a list of STEPS {time, anim, fit, enter, tick, done, exit} run by a tiny sequencer
##     (no coroutines, so nothing is left dangling when she dies or the room is freed),
##   - has SUPER-ARMOR: a hit never interrupts an attack (only a flash, a flinch while idle and a small push),
##   - shows its health through BossRoomController, which owns the boss bar.
##
## A boss subclass fills in the blanks marked "override": which attacks it has (_choose_attack and
## _build_attack), how its entrance looks, and what happens when it is hurt (_after_damage).
##
## Step keys:  time  seconds the step lasts (required)      anim  base animation name ("charge" -> charge_left...)
##             fit   stretch the animation to this many seconds
##             enter / tick(delta) / done / exit   Callables. "done" only runs when the step finishes normally,
##             "exit" always runs (also when the step is interrupted), so clean-up goes in "exit".

enum Phase { DORMANT, INTRO, FIGHT, TRANSFORM }

const ROAR_SFX: AudioStream = preload("res://assets/sounds/power_up.wav")
const THUD_SFX: AudioStream = preload("res://assets/sounds/hurt.wav")
const SPIT_SFX: AudioStream = preload("res://assets/sounds/tap.wav")
## How long a boss's entrance lasts (the player is held still for it; keep equal to BossRoomController.INTRO_TIME).
const INTRO_TIME: float = 1.9

## The room the boss fights in (set by BossRoomController).
var arena: WFCRoom

var _phase: Phase = Phase.DORMANT
var _invulnerable: bool = false
var _steps: Array[Dictionary] = []
var _step: Dictionary = {}
var _step_time: float = 0.0
## The velocity the current behaviour wants this frame (knockback is added on top).
var _intent: Vector2 = Vector2.ZERO
var _roam_time: float = 0.0
var _attack_pause: float = 0.6
var _last_attack: StringName = &""
var _hurt_timer: float = 0.0


# ------------------------------------------------------------ overrides

## Does this boss make an entrance when it wakes up?
func _has_intro() -> bool:
	return true


## Effects at the start of the entrance (override).
func _play_intro_effects() -> void:
	pass


## The steps of the entrance (override). Must add up to about INTRO_TIME.
func _intro_steps() -> Array[Dictionary]:
	return [{"time": INTRO_TIME, "anim": "idle"}]


## Which attack comes next (override).
func _choose_attack() -> StringName:
	return &""


## The steps of an attack (override).
func _build_attack(_kind: StringName) -> Array[Dictionary]:
	return []


## Seconds of roaming before the next attack, after one ends.
func _pause_after_attack() -> float:
	return 0.5


## How close the boss walks up to the player while roaming.
func _preferred_distance() -> float:
	return 60.0


## Called after a hit has been taken and survived (override: splitting, enraging...).
func _after_damage() -> void:
	pass


## Multiplier on the damage taken right now (override: a dizzy boss takes more).
func _damage_taken_mult() -> float:
	return 1.0


# ------------------------------------------------------------ waking up

func wake_up() -> void:
	if _phase != Phase.DORMANT:
		return # already awake: a room wakes everything in it when the player walks in, after the controller did
	_ensure_free_position()
	visible = true
	set_physics_process(true)
	_face(Vector2.DOWN)
	if _has_intro():
		_begin_intro()
	else:
		_phase = Phase.FIGHT


func _begin_intro() -> void:
	_phase = Phase.INTRO
	_invulnerable = true
	_play_intro_effects()
	_steps = _intro_steps()
	_next_step()


# ------------------------------------------------------------ the main loop

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if player == null:
		_find_player()
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	_intent = Vector2.ZERO
	if player != null:
		match _phase:
			Phase.FIGHT:
				if _step.is_empty():
					_update_roam(delta)
				else:
					_update_step(delta)
			Phase.INTRO, Phase.TRANSFORM:
				if not _step.is_empty():
					_update_step(delta)
	velocity = _intent + _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, knockback_decay * delta)
	move_and_slide()
	_pick_animation()


## Between attacks the boss walks after the player and then picks the next attack.
func _update_roam(delta: float) -> void:
	var to := _to_player()
	_face(to)
	if to.length() > _preferred_distance():
		_intent = to.normalized() * move_speed
	_roam_time += delta
	if _roam_time >= _attack_pause:
		_start_attack(_choose_attack())


func _start_attack(kind: StringName) -> void:
	_last_attack = kind
	_steps = _build_attack(kind)
	_next_step()


## Weighted random pick from [[name, weight], ...]; the attack just used is less likely to come again.
func _weighted_pick(options: Array) -> StringName:
	var total := 0.0
	for o in options:
		total += float(o[1]) * (0.35 if o[0] == _last_attack else 1.0)
	var roll := randf() * total
	for o in options:
		roll -= float(o[1]) * (0.35 if o[0] == _last_attack else 1.0)
		if roll <= 0.0:
			return o[0]
	return options[0][0]


func _pick_animation() -> void:
	if _phase == Phase.DORMANT:
		return
	if not _step.is_empty() and String(_step.get("anim", "")) != "":
		return # a step owns the animation
	if _hurt_timer > 0.0 and _has_anim("hurt"):
		_play("hurt")
	else:
		_play("move" if _intent.length() > 4.0 else "idle")


# ------------------------------------------------------------ the step sequencer

func _next_step() -> void:
	if not _step.is_empty():
		if _step.has("done"):
			(_step["done"] as Callable).call()
		if _step.has("exit"):
			(_step["exit"] as Callable).call()
	anim.speed_scale = 1.0
	if _dead:
		return
	if _steps.is_empty():
		_step = {}
		_on_steps_done()
		return
	_step = _steps.pop_front()
	_step_time = 0.0
	if _step.has("anim"):
		_play_step_anim(String(_step["anim"]), float(_step.get("fit", 0.0)))
	if _step.has("enter"):
		(_step["enter"] as Callable).call()


func _update_step(delta: float) -> void:
	_step_time += delta
	if _step.has("tick"):
		(_step["tick"] as Callable).call(delta)
	if not _step.is_empty() and _step_time >= float(_step["time"]):
		_next_step()


## Drops whatever the boss is doing (its clean-up runs, its "done" action does NOT).
func _interrupt() -> void:
	if not _step.is_empty() and _step.has("exit"):
		(_step["exit"] as Callable).call()
	_step = {}
	_steps = []
	anim.speed_scale = 1.0


func _on_steps_done() -> void:
	match _phase:
		Phase.INTRO:
			_invulnerable = false
			_phase = Phase.FIGHT
			_attack_pause = 0.6
			_roam_time = 0.0
		Phase.FIGHT:
			_attack_pause = _pause_after_attack()
			_roam_time = 0.0


func _play_step_anim(base: String, fit: float) -> void:
	var resolved := _resolve_anim(base)
	if not anim.sprite_frames.has_animation(resolved):
		return
	if fit > 0.0:
		var length := float(anim.sprite_frames.get_frame_count(resolved)) / maxf(anim.sprite_frames.get_animation_speed(resolved), 0.01)
		anim.speed_scale = length / fit
	anim.play(resolved)


# ------------------------------------------------------------ hitboxes

## Switches a damage box on or off (a dash's contact box, a spin's ring...). Turning it on forgets who was hit.
func _set_hitbox_node(box: Hitbox, on: bool) -> void:
	if box == null:
		return
	if on:
		box.reset_hits()
	box.set_deferred("monitoring", on)


func _set_hitbox(on: bool) -> void:
	_set_hitbox_node(attack_hitbox, on)


# ------------------------------------------------------------ taking damage

## A boss shrugs hits off: no stagger, only a flash, a flinch while idle, and a little push.
func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO, knockback_force: float = 0.0) -> void:
	if _dead or _phase == Phase.DORMANT or _invulnerable:
		return
	var dealt := maxi(1, int(round(float(amount) * _damage_taken_mult())))
	Audio.play_2d(hurt_sfx, global_position, hurt_sfx_volume_db, hurt_sfx_pitch)
	health.take_damage(dealt)
	if _dead:
		return
	if knockback_force > 0.0:
		var dir := (global_position - from_pos).normalized() if from_pos != Vector2.ZERO else -_facing
		_knockback = dir * knockback_force * (1.0 - knockback_resistance)
	_flash()
	_hurt_timer = 0.28
	_after_damage()


func _on_died() -> void:
	_interrupt()
	_invulnerable = true
	super()


## The boss room pays out (see BossRoomController), not the boss itself.
func _drop_loot() -> void:
	pass
