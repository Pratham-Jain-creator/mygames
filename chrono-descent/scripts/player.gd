extends CharacterBody2D
## The prisoner. Moves in 8 directions, dashes (with brief invulnerability), swings the one sword (see Blade)
## and drinks from the canteen. Everything he carries or wears lives in the Run autoload.

## Emitted when the object the player could interact with changes (null = nothing in reach).
signal interactable_changed(target: Node2D)
## The selected quick item (canteen / memory echo) changed.
signal quick_changed

const SPEED: float = 150.0
const DASH_SPEED: float = 270.0
const DASH_TIME: float = 0.34
## The first part of a dash is invulnerable.
const DASH_INVULN_FRACTION: float = 0.7
const DASH_COOLDOWN: float = 0.55
const KNOCKBACK_DECAY: float = 700.0
const HURT_TIME: float = 0.4
const RESPAWN_INVINCIBILITY: float = 1.5
const INPUT_BUFFER_TIME: float = 0.12
const INTERACT_RANGE: float = 30.0
## Stick tilt (0..1) from which moving counts as RUNNING.
const RUN_THRESHOLD: float = 0.75
const ATTACK_MOVE_FACTOR: float = 0.4
const DRINK_TIME: float = 0.7
const DRINK_MOVE_FACTOR: float = 0.35
## Share of maximum health one canteen charge heals.
const CANTEEN_HEAL: float = 0.45
## down, down_right, right, up_right, up, up_left, left, down_left: the rows of every prisoner sheet.
const DIR_NAMES: Array[String] = ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]
const HURT_SFX: AudioStream = preload("res://assets/sounds/hurt.wav")
const USE_SFX: AudioStream = preload("res://assets/sounds/power_up.wav")
const SHIELD_SFX: AudioStream = preload("res://assets/sounds/explosion.wav")

var is_dead: bool = false
var is_invincible: bool = false
var is_dashing: bool = false
## Shackled Arena: no dash.
var dash_disabled: bool = false
var last_facing_dir: Vector2 = Vector2.DOWN
var current_interactable: Node2D
## True while a menu / transition owns the controls: the player stands still.
var input_locked: bool = false
## 0 = canteen, 1 = memory echo.
var quick_index: int = 0

var _dash_time_left: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_dir: Vector2 = Vector2.DOWN
var _knockback: Vector2 = Vector2.ZERO
var _lunge_velocity: Vector2 = Vector2.ZERO
var _hurt_time: float = 0.0
var _attack_buffer: float = 0.0
var _dash_buffer: float = 0.0
var _drinking: float = 0.0
var _move_strength: float = 0.0
var _regen_pool: float = 0.0
var _drink_pending: bool = false

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var blade: Blade = $Blade
@onready var health_component: HealthComponent = $HealthComponent
@onready var iframe_timer: Timer = $IFrameTimer


func _ready() -> void:
	add_to_group("player")
	anim.sprite_frames = SpriteLib.prisoner()
	anim.play("idle_down")
	health_component.died.connect(_on_died)
	iframe_timer.timeout.connect(_on_iframes_ended)
	blade.setup(self, anim)
	Run.changed.connect(_sync_health)
	GameManager.enemy_killed.connect(_on_enemy_killed)
	_sync_health()
	health_component.current_health = health_component.max_health
	health_component.health_changed.emit(health_component.current_health, health_component.max_health)


## Maximum health follows the armor, charms and grafts. When it grows you gain the difference.
func _sync_health() -> void:
	var wanted := Run.max_health()
	if wanted == health_component.max_health:
		return
	var gained := wanted - health_component.max_health
	health_component.max_health = wanted
	health_component.current_health = clampi(health_component.current_health + maxi(gained, 0), 1, wanted)
	health_component.health_changed.emit(health_component.current_health, wanted)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_tick_regen(delta)
	if input_locked:
		blade.cancel()
		velocity = Vector2.ZERO
		_attack_buffer = 0.0
		_dash_buffer = 0.0
		is_dashing = false
		_drinking = 0.0
		_drink_pending = false
		_play_anim("idle")
		_set_interactable(null)
		return
	_hurt_time = maxf(0.0, _hurt_time - delta)
	_attack_buffer = maxf(0.0, _attack_buffer - delta)
	_dash_buffer = maxf(0.0, _dash_buffer - delta)
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	_drinking = maxf(0.0, _drinking - delta)
	if _drink_pending and _drinking <= 0.0:
		_drink_pending = false
		_finish_drink()
	if Input.is_action_just_pressed("attack"):
		_attack_buffer = INPUT_BUFFER_TIME
	if Input.is_action_just_pressed("roll"):
		_dash_buffer = INPUT_BUFFER_TIME
	_handle_quick_input()

	if is_dashing:
		_dash_state(delta)
	else:
		_normal_state()
	var base_velocity := velocity
	velocity = base_velocity + _knockback + _lunge_velocity
	move_and_slide()
	velocity = base_velocity
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_lunge_velocity = _lunge_velocity.move_toward(Vector2.ZERO, 500.0 * delta)

	_update_animation()
	_try_attack()
	_update_interaction()
	if Input.is_action_just_pressed("use_item"):
		_use_quick()


# ------------------------------------------------------------------ movement

func _normal_state() -> void:
	if _dash_buffer > 0.0 and not dash_disabled and _dash_cooldown <= 0.0 and (not blade.attacking or blade.can_cancel()):
		_dash_buffer = 0.0
		_start_dash()
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_move_strength = input_dir.length()
	if input_dir != Vector2.ZERO:
		var factor := 1.0
		if blade.attacking:
			factor = ATTACK_MOVE_FACTOR
		elif _drinking > 0.0:
			factor = DRINK_MOVE_FACTOR
		velocity = input_dir * _move_speed() * factor
		if not blade.attacking:
			last_facing_dir = input_dir
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)


func _move_speed() -> float:
	return SPEED * maxf(0.4, 1.0 + Run.stat(&"move"))


func _start_dash() -> void:
	blade.cancel()
	_drinking = 0.0
	_drink_pending = false
	is_dashing = true
	_dash_time_left = DASH_TIME
	_dash_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _dash_dir == Vector2.ZERO:
		_dash_dir = last_facing_dir
	_dash_dir = _dash_dir.normalized()
	last_facing_dir = _dash_dir
	_dash_cooldown = DASH_COOLDOWN * (1.0 + Run.stat(&"dash_cd"))
	velocity = _dash_dir * DASH_SPEED


func _dash_state(delta: float) -> void:
	_dash_time_left -= delta
	if _dash_time_left <= 0.0:
		is_dashing = false
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)


func _is_dash_invulnerable() -> bool:
	var window := DASH_TIME * DASH_INVULN_FRACTION * (1.0 + Run.stat(&"iframes"))
	return is_dashing and _dash_time_left > DASH_TIME - window


## The body steps into a sword blow.
func lunge(impulse: Vector2) -> void:
	_lunge_velocity = impulse


# ------------------------------------------------------------------ animation

## The 8-way direction name of the current facing: "down", "down_right"...
func facing_name() -> String:
	var angle := fposmod(rad_to_deg(atan2(last_facing_dir.x, last_facing_dir.y)), 360.0)
	return DIR_NAMES[int(round(angle / 45.0)) % 8]


## The facing snapped to the same 8 directions as the sprite, as a unit vector.
func facing8() -> Vector2:
	var angle := deg_to_rad(float(DIR_NAMES.find(facing_name())) * 45.0)
	return Vector2(sin(angle), cos(angle))


func _play_anim(base_name: String) -> void:
	var full := "%s_%s" % [base_name, facing_name()]
	if anim.animation != full:
		anim.play(full)


## The blade asks for an attack animation fitted to last `total` seconds.
func play_attack(attack_name: String, frames: int, total: float) -> void:
	var full := "attack_%s_%s" % [attack_name, facing_name()]
	var fps := anim.sprite_frames.get_animation_speed(full)
	anim.speed_scale = (float(frames) / maxf(fps, 1.0)) / maxf(total, 0.05)
	anim.play(full)


func _update_animation() -> void:
	if blade.attacking:
		return
	anim.speed_scale = 1.0
	anim.self_modulate = Color.WHITE
	if _drinking > 0.0:
		anim.self_modulate = Color(0.7, 1.0, 0.75)
		_play_anim("idle")
	elif _hurt_time > 0.0:
		_play_anim("hurt")
	elif is_dashing:
		_play_anim("dash")
	elif velocity.length() > 5.0:
		var stride := 1.0
		if _move_strength < RUN_THRESHOLD:
			stride = clampf(_move_strength / RUN_THRESHOLD, 0.6, 1.0)
		anim.speed_scale = stride * maxf(0.6, 1.0 + Run.stat(&"move"))
		_play_anim("run" if _move_strength >= RUN_THRESHOLD else "walk")
	else:
		_play_anim("idle")


# ------------------------------------------------------------------ attacking

func _try_attack() -> void:
	if _attack_buffer <= 0.0 or is_dashing or _drinking > 0.0 or not blade.can_attack():
		return
	_attack_buffer = 0.0
	blade.swing(facing8())


# ------------------------------------------------------------------ quick items (canteen / memory echo)

func quick_items() -> Array[StringName]:
	var items: Array[StringName] = [&"canteen"]
	if Run.echoes > 0:
		items.append(&"echo")
	return items


func _handle_quick_input() -> void:
	var items := quick_items()
	if Input.is_action_just_pressed("hotbar_next"):
		quick_index = (quick_index + 1) % items.size()
		quick_changed.emit()
	elif Input.is_action_just_pressed("hotbar_prev"):
		quick_index = posmod(quick_index - 1, items.size())
		quick_changed.emit()
	if quick_index >= items.size():
		quick_index = 0
		quick_changed.emit()


func selected_quick() -> StringName:
	var items := quick_items()
	return items[mini(quick_index, items.size() - 1)]


func _use_quick() -> void:
	match selected_quick():
		&"canteen":
			use_canteen()
		&"echo":
			Run.echoes -= 1
			Run.save_profile()
			GameManager.reveal_map_requested.emit()
			Audio.play(USE_SFX, -6.0, 0.8)
			quick_changed.emit()


func use_canteen() -> void:
	if _drinking > 0.0 or is_dashing:
		return
	if Run.canteen <= 0:
		GameManager.toast_requested.emit("THE CANTEEN IS EMPTY", null, Color(1.0, 0.5, 0.4))
		return
	if health_component.current_health >= health_component.max_health and Run.blood_debt <= 0:
		GameManager.toast_requested.emit("ALREADY AT FULL HEALTH", null, Color(0.8, 0.8, 0.8))
		return
	Run.canteen -= 1
	Run.canteen_changed.emit()
	blade.cancel()
	if Run.instant_canteen:
		_finish_drink()
	else:
		_drinking = DRINK_TIME
		_drink_pending = true


func _finish_drink() -> void:
	var amount := int(round(float(health_component.max_health) * CANTEEN_HEAL * maxf(0.1, 1.0 + Run.stat(&"heal"))))
	heal_player(amount)
	Audio.play(USE_SFX, -8.0, 1.2)
	GameManager.toast_requested.emit("+%d HEALTH" % amount, null, Color(0.5, 1.0, 0.6))


## Healing of any kind first repays the blood debt (Blood Font), then restores health.
func heal_player(amount: int) -> void:
	var real := Run.absorb_heal(amount)
	if real > 0:
		health_component.heal(real)


func heal_from_hit(amount: int) -> void:
	heal_player(amount)


func _on_enemy_killed(_enemy: Node) -> void:
	var share := Run.stat(&"kill_heal")
	if share > 0.0 and not is_dead:
		heal_player(maxi(1, int(round(float(health_component.max_health) * share))))


func _tick_regen(delta: float) -> void:
	var regen := Run.stat(&"regen")
	if regen == 0.0:
		return
	_regen_pool += regen * delta
	if _regen_pool >= 1.0:
		heal_player(int(_regen_pool))
		_regen_pool -= floorf(_regen_pool)
	elif _regen_pool <= -1.0:
		# bleeding never kills outright
		if health_component.current_health > 1:
			health_component.take_damage(1)
		_regen_pool += 1.0


# ------------------------------------------------------------------ damage

func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO, knockback_force: float = 0.0) -> void:
	if is_invincible or is_dead or _is_dash_invulnerable():
		return
	var dealt := maxi(1, int(round(float(amount) * Run.damage_taken_mult())))
	if _drinking > 0.0:
		_drinking = 0.0
		_drink_pending = false # a hit knocks the flask out of your hand: the charge is spent for nothing
	if Run.shield and dealt >= health_component.current_health:
		# Forlorn Shrine: the shield swallows the lethal blow
		Run.shield = false
		Run.changed.emit()
		Audio.play(SHIELD_SFX, -6.0, 1.6)
		GameManager.toast_requested.emit("THE SHIELD SHATTERS", null, Color(0.6, 0.85, 1.0))
		GameManager.shake_camera(4.0, 0.2)
		_start_iframes(0.8)
		return
	Audio.play(HURT_SFX, -4.0, 1.0, 0.05)
	if from_pos != Vector2.ZERO and knockback_force > 0.0:
		_knockback = (global_position - from_pos).normalized() * knockback_force
	_hurt_time = HURT_TIME
	anim.speed_scale = 1.0
	anim.play("hurt_%s" % facing_name())
	GameManager.shake_camera(3.0, 0.2)
	if InputHints.using_controller:
		Input.start_joy_vibration(0, 0.4, 0.7, 0.25)
	blade.cancel()
	health_component.take_damage(dealt)
	if is_dead:
		return
	_start_iframes(iframe_timer.wait_time)


func _start_iframes(seconds: float) -> void:
	is_invincible = true
	iframe_timer.start(seconds)
	modulate.a = 0.5


func _on_iframes_ended() -> void:
	is_invincible = false
	modulate.a = 1.0


func _on_died() -> void:
	blade.cancel()
	is_dead = true
	is_invincible = true
	velocity = Vector2.ZERO
	modulate.a = 1.0
	_set_interactable(null)
	anim.speed_scale = 1.0
	anim.self_modulate = Color.WHITE
	anim.play("death_%s" % facing_name())


func set_input_locked(locked: bool) -> void:
	input_locked = locked


## Brings the player back to life at a position (used by GameManager after a death).
func respawn(spawn_position: Vector2) -> void:
	blade.cancel()
	global_position = spawn_position
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_lunge_velocity = Vector2.ZERO
	_hurt_time = 0.0
	_drinking = 0.0
	is_dashing = false
	is_dead = false
	dash_disabled = false
	anim.rotation = 0.0
	anim.self_modulate = Color.WHITE
	_sync_health()
	health_component.reset()
	anim.play("idle_down")
	is_invincible = true
	modulate.a = 0.5
	iframe_timer.start(RESPAWN_INVINCIBILITY)


# ------------------------------------------------------------------ interaction

## Picks the nearest usable "interactable" in reach and uses it when the interact key is pressed.
## An interactable implements: can_interact() -> bool, interact(by: Node), get_prompt() -> String.
func _update_interaction() -> void:
	var best: Node2D = null
	var best_distance := INTERACT_RANGE
	for node in get_tree().get_nodes_in_group("interactable"):
		var candidate := node as Node2D
		if candidate == null or not candidate.is_visible_in_tree() or not candidate.has_method("can_interact") or not candidate.can_interact():
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	_set_interactable(best)
	if best != null and Input.is_action_just_pressed("interact"):
		best.interact(self)


func _set_interactable(target: Node2D) -> void:
	if target != current_interactable:
		current_interactable = target
		interactable_changed.emit(target)
