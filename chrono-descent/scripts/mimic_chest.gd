class_name MimicChest
extends EnemyBase
## A chest that is really a monster (sprites: mimic_chest.png / mimic_chest_golden.png). When woken it REVEALS itself
## (briefly invulnerable), then hops after you. Close up it BITES in a lunge (the normal EnemyBase attack, with the
## AttackHitbox); at mid range it LASHES with a long tongue, aimed when the wind-up starts. Elite mimics (the
## Cursed Hoard's) have triple health.

const LASH_MIN: float = 44.0
const LASH_MAX: float = 90.0
const LASH_LENGTH: float = 96.0
const LASH_REACH: float = 11.0
const REVEAL_TIME: float = 0.8

@export var golden: bool = false

var _revealed: bool = false
var _reveal_left: float = 0.0
var _lashing: bool = false
var _lash_dir: Vector2 = Vector2.DOWN
var _lash_line: Line2D
var _check_clock: float = 0.0


func _setup_frames() -> void:
	var sheet := "mimic_chest_golden.png" if golden else "mimic_chest.png"
	anim.sprite_frames = SpriteLib.mimic(SpriteLib.MOBS + sheet, 64)
	anim.play("idle_down")


## The room wakes everything when the player enters, and the Cursed Hoard wakes it again: only the first counts.
func wake_up() -> void:
	if _revealed:
		return
	_revealed = true
	super()
	_reveal_left = REVEAL_TIME
	anim.play("reveal_%s" % _dir4())
	Audio.play_2d(preload("res://assets/sounds/jump.wav"), global_position, -4.0, 0.6)


func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO, knockback_force: float = 0.0) -> void:
	if _reveal_left > 0.0:
		return # still showing its teeth
	super(amount, from_pos, knockback_force)


func _update_animation(force: bool) -> void:
	if _reveal_left > 0.0:
		return
	super(force)


func _update_chase(delta: float) -> void:
	if _reveal_left > 0.0:
		_reveal_left -= delta
		return
	var to := _to_player()
	var dist := to.length()
	_check_clock -= delta
	if _cooldown <= 0.0 and dist > attack_range and dist >= LASH_MIN and dist <= LASH_MAX and _check_clock <= 0.0:
		_check_clock = 0.35
		if randf() < 0.8:
			_lashing = true
			_change_state(State.WINDUP)
			return
	_lashing = false
	super(delta)


func _enter_state(s: State) -> void:
	super(s)
	match s:
		State.WINDUP:
			if _lashing:
				_lash_dir = _to_player().normalized()
				_face(_lash_dir)
				_play_fitted("lash", windup_time + attack_time)
				_show_lash_line()
		State.ATTACK:
			if _lashing:
				_do_lash()


func _exit_state(s: State) -> void:
	super(s)
	if s == State.WINDUP and is_instance_valid(_lash_line):
		_lash_line.queue_free()
		_lash_line = null


func _update_windup(delta: float) -> void:
	super(delta)
	# the aim follows the player until the last moment, then locks
	if _lashing and state == State.WINDUP and is_instance_valid(_lash_line):
		if _state_time < windup_time - 0.15:
			_lash_dir = _to_player().normalized()
			_face(_lash_dir)
		_lash_line.clear_points()
		_lash_line.add_point(Vector2(0, -4))
		_lash_line.add_point(Vector2(0, -4) + _lash_dir * LASH_LENGTH)


func _show_lash_line() -> void:
	_lash_line = Line2D.new()
	_lash_line.width = 3.0
	_lash_line.default_color = Color(1.0, 0.25, 0.25, 0.65)
	_lash_line.z_index = 4
	_lash_line.top_level = false
	add_child(_lash_line)
	_lash_line.add_point(Vector2(0, -4))
	_lash_line.add_point(Vector2(0, -4) + _lash_dir * LASH_LENGTH)


## The tongue hits whoever is within a hand's width of the line.
func _do_lash() -> void:
	var origin := global_position + Vector2(0, -4)
	var tip := origin + _lash_dir * LASH_LENGTH
	if player != null and not player.is_dead:
		var closest := Geometry2D.get_closest_point_to_segment(player.global_position + Vector2(0, 2), origin, tip)
		if closest.distance_to(player.global_position + Vector2(0, 2)) <= LASH_REACH:
			player.take_damage(int(ceil(12.0 * damage_multiplier)), global_position, 240.0)
	GameManager.shake_camera(1.5, 0.12)


func _play_fitted(base: String, seconds: float) -> void:
	var resolved := _resolve_anim(base)
	if not anim.sprite_frames.has_animation(resolved):
		return
	var length := float(anim.sprite_frames.get_frame_count(resolved)) / maxf(anim.sprite_frames.get_animation_speed(resolved), 0.01)
	anim.speed_scale = length / maxf(seconds, 0.05)
	anim.play(resolved)
