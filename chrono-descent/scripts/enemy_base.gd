class_name EnemyBase
extends CharacterBody2D
## Shared brain for every enemy.
##
## Intention cycle:  SLEEP -> CHASE (approach) -> WINDUP (telegraph) -> ATTACK -> RECOVER -> CHASE ...
## Any hit interrupts into HURT (hurt animation + knockback + flash + sound), then back to CHASE.
## Animations live in each enemy scene (AnimatedSprite2D > SpriteFrames): idle, move, attack,
## hurt, death. Every one is optional. Subclasses mostly only override _update_chase / _fire.
## Every number below is an exported parameter, so each enemy scene tunes its own behaviour.

enum State { SLEEP, CHASE, WINDUP, ATTACK, RECOVER, HURT, DEAD }

## Emitted once when this enemy dies (hook for loot, score, room-clear logic...).
signal defeated(enemy: EnemyBase)

const HURT_SFX := preload("res://assets/sounds/hurt.wav")
const ELITE_HEALTH_MULT: float = 3.0
const ELITE_DAMAGE_MULT: float = 1.4
const ELITE_SCALE: float = 1.25

@export_group("Movement")
@export var move_speed: float = 40.0
## Floating enemies bob up and down visually.
@export var flying: bool = false
## On: animations are named "<name>_<down|left|right|up>" (idle_down, move_left...) and the one for the
## direction the enemy faces is played; the sprite is never flipped. Off: one animation per name, flipped to
## face left / right. A "windup" animation (played during the telegraph) and an "attack" animation (played
## during the attack itself) may be given separately; with only "attack" it covers both.
@export var directional: bool = false
## Name of a skeleton sheet in assets/sprites/enemies/mobs ("skeleton_melee.png"): when set, the sprite frames are
## built from it in code (see SpriteLib.skeleton) and the scene's AnimatedSprite2D can be empty.
@export var skeleton_sheet: String = ""
## Other sheets built in code: "dracula", "bat", "spirit".
@export var sprite_kind: String = ""
## While chasing, the enemy stays at least this far from the player's CENTRE instead of pressing into them (an enemy
## glued to the player's head or feet could neither move nor be dodged): too close and it steps back, close
## enough and it circles around the player until its next attack is ready. 0 = old behaviour (walk straight in).
@export var standoff_distance: float = 17.0

@export_group("Scaling (set by the level director)")
## Floors get harder: health and damage are multiplied by these when the enemy is spawned.
@export var health_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
## Tints the sprite (e.g. a gold boss). Telegraph / hurt effects return to this colour.
@export var body_tint: Color = Color.WHITE

@export_group("Loot")
## Elites (stronger, red-tinted, spawned by some rooms) drop much more ash and materials.
@export var is_elite: bool = false

@export_group("Attack intention")
## Start telegraphing an attack when the player is this close.
@export var attack_range: float = 40.0
## Telegraph time before the attack lands (the player's chance to react).
@export var windup_time: float = 0.4
@export var attack_time: float = 0.25
@export var recover_time: float = 0.5
## Minimum seconds between the end of one attack and the start of the next.
@export var attack_cooldown: float = 1.2
## > 0 makes the attack a lunge/dash toward where the player was when the windup began.
@export var dash_speed: float = 0.0
@export var telegraph_color: Color = Color(1.0, 0.78, 0.45)
@export var telegraph_squash: bool = false

@export_group("Melee hitbox (optional AttackHitbox / EnemyHitbox child)")
@export var melee_damage: int = 10
@export var melee_knockback: float = 160.0
## Pushes the hitbox this far out in the facing direction while attacking.
@export var melee_reach: float = 0.0

@export_group("Hurt")
@export_range(0.0, 1.0) var knockback_resistance: float = 0.0
@export var hurt_stun_time: float = 0.25
@export var knockback_decay: float = 650.0
@export var hurt_flash_color: Color = Color(1.0, 0.35, 0.35)

@export_group("Audio")
## Played on every hit, including the killing blow. Goes through the Audio autoload, so it
## keeps playing after this enemy is freed.
@export var hurt_sfx: AudioStream = HURT_SFX
@export var hurt_sfx_pitch: float = 1.25
@export var hurt_sfx_volume_db: float = -6.0
## Optional extra sound when the enemy dies (leave empty for none).
@export var death_sfx: AudioStream
@export var death_sfx_pitch: float = 0.8

var state: State = State.SLEEP
var player: Node2D
var attack_hitbox: Hitbox

var _state_time: float = 0.0
var _cooldown: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.RIGHT
var _dash_dir: Vector2 = Vector2.RIGHT
var _dead: bool = false
var _hit_base_pos: Vector2 = Vector2.ZERO
var _bob_t: float = 0.0
var _strafe_sign: float = 1.0
var _strafe_flip_cooldown: float = 0.0
## The scale the enemy's sprite is drawn at (set in the scene). Squash effects and the hurt reset return to THIS, not
## to 1: most enemy sprites are shown smaller than their sheet cells.
var _anim_scale: Vector2 = Vector2.ONE

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var health: HealthComponent = $HealthComponent


func _ready() -> void:
	add_to_group("enemy")
	_setup_frames()
	_anim_scale = anim.scale
	visible = false
	# Draw above the floor tiles of EVERY room. An enemy belongs to the room it spawned in, and a room
	# that comes later in the scene tree paints its floor over the earlier rooms' enemies, so a
	# follower chasing you into another room would turn invisible (while still hitting you).
	if z_index == 0:
		z_index = 1
	set_physics_process(false)
	if is_elite:
		health_multiplier *= ELITE_HEALTH_MULT
		damage_multiplier *= ELITE_DAMAGE_MULT
		scale = Vector2.ONE * ELITE_SCALE
		body_tint = body_tint.lerp(Color(1.0, 0.55, 0.5), 0.6)
	health_multiplier *= 1.0 + Run.stat(&"enemy_hp")
	melee_damage = int(ceil(melee_damage * damage_multiplier))

	var hb := get_node_or_null("AttackHitbox")
	if hb == null:
		hb = get_node_or_null("EnemyHitbox")
	attack_hitbox = hb as Hitbox
	if attack_hitbox:
		attack_hitbox.damage = melee_damage
		attack_hitbox.knockback_force = melee_knockback
		attack_hitbox.continuous_damage = false
		attack_hitbox.set_deferred("monitoring", false)
		_hit_base_pos = attack_hitbox.position

	_play("idle", true)
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	health.died.connect(_on_died)
	health.max_health = int(ceil(health.max_health * health_multiplier))
	health.current_health = health.max_health
	anim.self_modulate = body_tint
	call_deferred("_find_player")


func wake_up() -> void:
	_ensure_free_position()
	visible = true
	set_physics_process(true)
	_change_state(State.CHASE)


# ------------------------------------------------------------ frames and loot

## Scenes whose sprites are built in code (SpriteLib) give the AnimatedSprite2D its frames here. Subclasses with their
## own sheets override this.
func _setup_frames() -> void:
	match sprite_kind:
		"dracula":
			anim.sprite_frames = SpriteLib.dracula_mob()
			anim.play("idle_down")
			return
		"bat":
			anim.sprite_frames = SpriteLib.bat()
			anim.play("idle_down")
			return
		"spirit":
			anim.sprite_frames = SpriteLib.skull_spirit()
			anim.play("idle_down")
			return
	if skeleton_sheet != "":
		anim.sprite_frames = SpriteLib.skeleton(skeleton_sheet)
		anim.play("idle_down")


## Drops this enemy's ash (and, for elites, materials) where it died. Bosses do not call this: the boss room does.
func _drop_loot() -> void:
	Loot.enemy_died(self)


func _find_player() -> void:
	# Deferred call: the enemy may already have been removed (e.g. its floor collapsed).
	if not is_inside_tree():
		return
	player = get_tree().get_first_node_in_group("player")


# ------------------------------------------------------------ spawn safety

## True when the enemy's body currently overlaps a wall, a prop or another solid body.
func is_stuck() -> bool:
	return _overlaps_solid_at(global_position)


func _overlaps_solid_at(world_pos: Vector2) -> bool:
	# recovery_as_collision = true makes a zero-length test report overlaps too.
	return test_move(Transform2D(0.0, world_pos), Vector2.ZERO, null, 0.08, true)


## Safety net on top of the room's spawn-point rules: if the enemy still ended up inside
## something solid, search outward in rings for the nearest free spot and move there.
func _ensure_free_position() -> void:
	if not _overlaps_solid_at(global_position):
		return
	var origin := global_position
	for radius in [8.0, 16.0, 24.0, 32.0, 48.0, 64.0, 96.0]:
		for i in 12:
			var candidate: Vector2 = origin + Vector2.RIGHT.rotated(TAU * float(i) / 12.0) * radius
			if not _overlaps_solid_at(candidate):
				global_position = candidate
				return
	push_warning("%s could not find a free spot near %s" % [name, str(origin)])


# ------------------------------------------------------------ sprite helpers

func _has_anim(n: String) -> bool:
	if anim.sprite_frames == null:
		return false
	if directional and anim.sprite_frames.has_animation("%s_down" % n):
		return true
	return anim.sprite_frames.has_animation(n)


## The animation to really play for a name: its variant for the facing direction when `directional`.
func _resolve_anim(n: String) -> String:
	if directional:
		var variant := "%s_%s" % [n, _dir4()]
		if anim.sprite_frames.has_animation(variant):
			return variant
	return n


## The facing as one of the four sheet rows.
func _dir4() -> String:
	if absf(_facing.x) > absf(_facing.y):
		return "right" if _facing.x > 0.0 else "left"
	return "down" if _facing.y >= 0.0 else "up"


func _play(n: String, force: bool = false) -> void:
	var a := n
	if not _has_anim(a):
		a = "idle" if _has_anim("idle") else "default"
	if not _has_anim(a):
		return
	a = _resolve_anim(a)
	if force or anim.animation != a:
		anim.play(a)


# ------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if player == null:
		_find_player()
	_cooldown = maxf(0.0, _cooldown - delta)
	_state_time += delta
	velocity = Vector2.ZERO

	if player != null:
		match state:
			State.CHASE:
				_update_chase(delta)
			State.WINDUP:
				_update_windup(delta)
			State.ATTACK:
				_update_attack(delta)
			State.RECOVER:
				_update_recover(delta)
			State.HURT:
				if _state_time >= hurt_stun_time:
					_change_state(State.CHASE)

	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, knockback_decay * delta)
	move_and_slide()
	_update_animation(false)

	if flying:
		_bob_t += delta * 4.0
		anim.position.y = sin(_bob_t) * 2.0


func _to_player() -> Vector2:
	return player.global_position - global_position if player else Vector2.ZERO


func _face(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	_facing = dir.normalized()
	if not directional and absf(dir.x) > 0.1:
		anim.flip_h = dir.x < 0.0


# ------------------------------------------------------------ state behaviour

## Approach the player; start an attack once in range and off cooldown. Never press into the player: see
## standoff_distance.
func _update_chase(delta: float) -> void:
	var to := _to_player()
	_face(to)
	if to.length() <= attack_range and _cooldown <= 0.0:
		_change_state(State.WINDUP)
		return
	var dir := to.normalized()
	var dist := to.length()
	if standoff_distance <= 0.0 or dist > standoff_distance + 3.0:
		velocity = dir * move_speed
	elif dist < standoff_distance - 3.0:
		velocity = -dir * move_speed * 0.8 # too close: step back
	else:
		# in position, waiting for the next attack: circle the player, and turn round when something blocks the way
		_strafe_flip_cooldown = maxf(0.0, _strafe_flip_cooldown - delta)
		for i in get_slide_collision_count():
			var collider := get_slide_collision(i).get_collider() as Node
			if collider != null and not collider.is_in_group("player") and _strafe_flip_cooldown <= 0.0:
				_strafe_sign = -_strafe_sign
				_strafe_flip_cooldown = 0.5
		velocity = dir.orthogonal() * _strafe_sign * move_speed * 0.6


func _update_windup(_delta: float) -> void:
	if dash_speed <= 0.0:
		_face(_to_player()) # keep aiming while telegraphing (lunges lock their direction)
	if _state_time >= windup_time:
		_change_state(State.ATTACK)


func _update_attack(_delta: float) -> void:
	if dash_speed > 0.0:
		velocity = _dash_dir * dash_speed
	if _state_time >= attack_time:
		_change_state(State.RECOVER)


func _update_recover(_delta: float) -> void:
	if _state_time >= recover_time:
		_change_state(State.CHASE)


func _change_state(new_state: State) -> void:
	if _dead:
		return
	_exit_state(state)
	state = new_state
	_state_time = 0.0
	_enter_state(new_state)
	_update_animation(true)


func _enter_state(s: State) -> void:
	match s:
		State.WINDUP:
			_dash_dir = _to_player().normalized() if player else _facing
			anim.self_modulate = telegraph_color
			_start_attack_anim()
			if telegraph_squash:
				var tw := create_tween()
				tw.tween_property(anim, "scale", _anim_scale * Vector2(1.25, 0.72), windup_time)
		State.ATTACK:
			anim.self_modulate = body_tint
			if telegraph_squash:
				anim.scale = _anim_scale * Vector2(0.88, 1.18)
				create_tween().tween_property(anim, "scale", _anim_scale, attack_time)
			if _has_anim("windup") and _has_anim("attack"):
				# separate wind-up / attack animations: the attack one plays now, fitted to the attack time
				var attack_anim := _resolve_anim("attack")
				var attack_length := anim.sprite_frames.get_frame_count(attack_anim) / maxf(anim.sprite_frames.get_animation_speed(attack_anim), 0.01)
				anim.speed_scale = attack_length / maxf(attack_time, 0.05)
				anim.play(attack_anim)
			if attack_hitbox:
				attack_hitbox.position = _hit_base_pos + _facing * melee_reach
				attack_hitbox.set_deferred("monitoring", true)
		State.HURT:
			anim.self_modulate = body_tint
			anim.speed_scale = 1.0
			anim.scale = _anim_scale


func _exit_state(s: State) -> void:
	if s == State.ATTACK:
		_cooldown = attack_cooldown
		anim.speed_scale = 1.0
		if attack_hitbox:
			attack_hitbox.set_deferred("monitoring", false)


## Stretches the telegraph animation so it finishes right when the windup ends (or, with no separate
## "windup" animation, the attack animation so it finishes when the attack ends).
func _start_attack_anim() -> void:
	var base := "windup" if _has_anim("windup") else "attack"
	if not _has_anim(base):
		return
	var resolved := _resolve_anim(base)
	var frames := anim.sprite_frames.get_frame_count(resolved)
	var length := frames / maxf(anim.sprite_frames.get_animation_speed(resolved), 0.01)
	var span := windup_time if base == "windup" else windup_time + attack_time
	anim.speed_scale = length / maxf(span, 0.05)
	anim.play(resolved)


func _update_animation(force: bool) -> void:
	match state:
		State.HURT:
			_play("hurt", force)
		State.WINDUP, State.ATTACK:
			if not _has_anim("attack") and not _has_anim("windup"):
				_play("idle", force)
		State.DEAD:
			pass
		State.CHASE:
			_play("move" if velocity.length() > 4.0 else "idle", force)
		_:
			_play("idle", force)


# ------------------------------------------------------------ taking damage

## Called by Hitbox / Projectile. from_pos + knockback_force are optional.
func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO, knockback_force: float = 0.0) -> void:
	if _dead:
		return
	# Played BEFORE applying damage so the killing blow is audible too. The Audio autoload owns
	# the player node, so the sound is unaffected by this enemy being freed right afterwards.
	Audio.play_2d(hurt_sfx, global_position, hurt_sfx_volume_db, hurt_sfx_pitch)
	health.take_damage(amount)
	if _dead:
		return
	if knockback_force > 0.0:
		var dir := (global_position - from_pos).normalized() if from_pos != Vector2.ZERO else -_facing
		_knockback = dir * knockback_force * (1.0 - knockback_resistance)
	_flash()
	if hurt_stun_time > 0.0:
		_change_state(State.HURT)


func _flash() -> void:
	modulate = hurt_flash_color
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.18)


func _on_died() -> void:
	_dead = true
	state = State.DEAD
	Audio.play_2d(death_sfx, global_position, hurt_sfx_volume_db, death_sfx_pitch)
	defeated.emit(self)
	GameManager.enemy_killed.emit(self)
	_drop_loot()
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	for a in find_children("*", "Area2D", true, false):
		(a as Area2D).set_deferred("monitoring", false)
	anim.self_modulate = body_tint
	anim.speed_scale = 1.0
	if _has_anim("death"):
		anim.play(_resolve_anim("death"))
		await anim.animation_finished
	else:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "scale", Vector2(1.3, 0.1), 0.25)
		tw.tween_property(self, "modulate:a", 0.0, 0.25)
		await tw.finished
	queue_free()
