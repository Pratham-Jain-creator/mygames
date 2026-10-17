extends CharacterBody3D
## Sentinel: armoured dungeon guard with Sekiro-style posture.
## - Yellow "!"  = slash: deflect it (RMB right before it lands) to wreck its posture.
## - Red "!!"    = perilous thrust: cannot be blocked. Dash INTO it for a mikiri (instant posture break).
## - Posture full -> kneeling and vulnerable -> any hit is a DEATHBLOW.
## Visuals + attack timing live in sentinel.tscn (AnimationPlayer). Method tracks inside the
## animations call _on_attack_hit / _on_attack_end / _on_recoil_end at the right frames.

enum State { IDLE, CHASE, ATTACK, RECOIL, STAGGER, DEAD }

@export var max_hp := 90.0
@export var max_posture := 90.0
@export var move_speed := 3.8
@export var detect_range := 22.0
@export var leash_range := 32.0
@export var damage := 22.0
@export var posture_damage := 26.0
@export var jp_reward := 40
@export var thrust_chance := 0.35

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var hp_bar: Node3D = $HpBar
@onready var posture_bar: Node3D = $PostureBar
@onready var edge_ray: RayCast3D = $EdgeRay

var hp := 0.0
var posture := 0.0
var state: State = State.IDLE
var vulnerable := false
var home := Vector3.ZERO
var home_yaw := 0.0
var player: Node3D = null
var attack_cd := 1.0
var attack_t := 0.0
var stagger_t := 0.0
var posture_delay := 0.0
var current_attack: StringName = &"slash"
var gravity := 24.0


func _ready() -> void:
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	home = global_position
	home_yaw = rotation.y
	hp = max_hp
	anim.play("idle")


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
	if not is_on_floor():
		velocity.y -= gravity * delta
	attack_cd = maxf(attack_cd - delta, 0.0)
	posture_delay -= delta
	if posture_delay <= 0.0 and state != State.STAGGER:
		posture = maxf(posture - 12.0 * delta, 0.0)

	match state:
		State.IDLE:
			_state_idle()
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			attack_t += delta
			if attack_t < 0.5 and _player_ok():
				_face(player.global_position, 6.0, delta, 2.4)  # limited turn rate: fast movers dodge by circling
			velocity.x = 0.0
			velocity.z = 0.0
		State.RECOIL:
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		State.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
			stagger_t -= delta
			if stagger_t <= 0.0:
				vulnerable = false
				posture = max_posture * 0.3
				state = State.CHASE
	move_and_slide()
	if global_position.y < -40.0:
		queue_free()
	_update_bars()


func _player_ok() -> bool:
	return is_instance_valid(player) and player.get("alive") == true


func _state_idle() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _player_ok():
		var to := player.global_position - global_position
		if absf(to.y) < 6.0 and Vector2(to.x, to.z).length() < detect_range:
			state = State.CHASE
	_play(&"idle")


func _state_chase(delta: float) -> void:
	if not _player_ok():
		state = State.IDLE
		return
	var to := player.global_position - global_position
	var vertical := absf(to.y)
	to.y = 0.0
	var dist := to.length()
	if dist > leash_range or vertical > 6.0:
		state = State.IDLE
		return
	_face(player.global_position, 8.0, delta)
	if dist > 2.2 and edge_ray.is_colliding():
		var dir := to / dist  # unit vector toward the player
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		_play(&"walk")
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_play(&"idle")
	if dist < 3.0 and attack_cd <= 0.0:
		_begin_attack()


func _face(pos: Vector3, rate: float, delta: float, max_turn: float = 99.0) -> void:
	var to := pos - global_position
	to.y = 0.0
	if to.length_squared() < 0.001:
		return
	# Forward is -Z, so yaw = atan2(-x, -z).
	var diff := angle_difference(rotation.y, atan2(-to.x, -to.z))
	var step := diff * clampf(rate * delta, 0.0, 1.0)
	rotation.y += clampf(step, -max_turn * delta, max_turn * delta)


func _play(name: StringName) -> void:
	if anim.current_animation != String(name):
		anim.play(name, 0.15)


func _begin_attack() -> void:
	current_attack = &"thrust" if randf() < thrust_chance else &"slash"
	state = State.ATTACK
	attack_t = 0.0
	anim.play(current_attack, 0.1)


# --- called from animation method tracks -------------------------------------------
func _on_attack_hit() -> void:
	if state != State.ATTACK or not _player_ok():
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var reach := 3.9 if current_attack == &"thrust" else 3.2
	if to.length() > reach:
		return
	var fwd := -global_transform.basis.z
	if fwd.dot(to.normalized()) < 0.3:
		return
	var perilous := current_attack == &"thrust"
	var result: String = player.receive_attack(damage, posture_damage, self, perilous)
	match result:
		"deflected":
			_add_posture(38.0)
			if state != State.STAGGER:
				state = State.RECOIL
				anim.play("recoil", 0.0)
		"blocked":
			_add_posture(6.0)
		"mikiri":
			_break_posture()


func _on_attack_end() -> void:
	if state == State.ATTACK:
		state = State.CHASE
		attack_cd = randf_range(0.8, 1.6)


func _on_recoil_end() -> void:
	if state == State.RECOIL:
		state = State.CHASE
		attack_cd = 0.6


# --- being hit -----------------------------------------------------------------------
## Returns "deathblow" | "kill" | "break" | "hit" | "dead".
func take_hit(dmg: float, posture_dmg: float, _from: Node3D) -> String:
	if state == State.DEAD:
		return "dead"
	if vulnerable:
		_die(true)
		return "deathblow"
	# Mid-attack = super armour: reduced damage, no flinch.
	var mult := 0.5 if state == State.ATTACK else 1.0
	hp -= dmg * mult
	if hp <= 0.0:
		_die(false)
		return "kill"
	_add_posture(posture_dmg * mult)
	if state == State.STAGGER:
		return "break"
	if state == State.IDLE:
		state = State.CHASE
	if state == State.CHASE:
		anim.play("hurt", 0.0)
	return "hit"


func _add_posture(amount: float) -> void:
	posture = minf(posture + amount, max_posture)
	posture_delay = 2.0
	if posture >= max_posture and state != State.STAGGER:
		_break_posture()


func _break_posture() -> void:
	state = State.STAGGER
	vulnerable = true
	stagger_t = 3.0
	posture = max_posture
	anim.play("stagger", 0.1)


func _die(deathblow: bool) -> void:
	state = State.DEAD
	vulnerable = false
	remove_from_group("enemy")
	$CollisionShape3D.set_deferred("disabled", true)
	hp_bar.visible = false
	posture_bar.visible = false
	anim.play("die", 0.05)
	Game.enemy_killed.emit(deathblow, jp_reward)


func reset_to_home() -> void:
	if state == State.DEAD:
		return
	global_position = home
	rotation.y = home_yaw
	velocity = Vector3.ZERO
	hp = max_hp
	posture = 0.0
	vulnerable = false
	state = State.IDLE
	attack_cd = 1.0
	anim.play("idle", 0.0)


func _update_bars() -> void:
	hp_bar.visible = hp < max_hp
	posture_bar.visible = posture > 0.5
	hp_bar.scale.x = maxf(hp / max_hp, 0.001)
	posture_bar.scale.x = maxf(posture / max_posture, 0.001)
