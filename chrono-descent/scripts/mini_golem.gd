class_name MiniGolem
extends EnemyBase
## A mini golem: a slow, sturdy stone brute. It walks after the player and
##   SLAMS   (close range): it raises its fists while a ground ellipse fills, then smashes it; a shockwave
##           hurts everything inside the ellipse
##   THROWS  (mid range, now and then): it gathers a glowing orb, then hurls it
## It uses EnemyBase's normal telegraph -> attack -> recover cycle; the throw is the same cycle with another
## animation and an orb instead of the slam. Animations come from the scene (windup_* / attack_* are the two
## halves of the slam, charge_* / cast_* the throw).

const ORB_PATH: String = "res://scenes/enemies/golem_orb_mini.tscn"
const KIND: int = GolemFX.Kind.MINI
## Slam: the ground ellipse sits this far in front of the golem and is this wide (half-width, px).
const SLAM_FORWARD: float = 16.0
const SLAM_RADIUS: float = 36.0
const THROW_MIN: float = 90.0
const THROW_MAX: float = 190.0

static var _orb_scene: PackedScene

var _throwing: bool = false
var _throw_check: float = 0.0
var _slam_center: Vector2 = Vector2.ZERO
var _telegraph: AnimatedSprite2D
var _aim_line: Sprite2D
var _throw_dir: Vector2 = Vector2.DOWN


## Close in, and when the cooldown allows: slam when near, sometimes throw when at mid range.
func _update_chase(delta: float) -> void:
	var to := _to_player()
	_face(to)
	var dist := to.length()
	if _cooldown <= 0.0:
		if dist <= attack_range:
			_throwing = false
			_change_state(State.WINDUP)
			return
		_throw_check -= delta
		if _throw_check <= 0.0:
			_throw_check = 0.9
			if dist >= THROW_MIN and dist <= THROW_MAX and randf() < 0.55:
				_throwing = true
				_change_state(State.WINDUP)
				return
	if dist > attack_range * 0.85:
		velocity = to.normalized() * move_speed


func _enter_state(s: State) -> void:
	super(s)
	match s:
		State.WINDUP:
			_slam_center = global_position + _facing * SLAM_FORWARD + Vector2(0.0, 4.0)
			if _throwing:
				_throw_dir = _to_player().normalized()
				_play_fitted("charge", windup_time)
				_aim_line = GolemFX.aim_line(get_parent(), global_position + Vector2(0.0, -4.0), _throw_dir, 230.0, KIND)
			else:
				_telegraph = GolemFX.slam_telegraph(get_parent(), _slam_center, KIND, SLAM_RADIUS, windup_time)
		State.ATTACK:
			if _throwing:
				_play_fitted("cast", attack_time)
				_fire_orb()
			else:
				_slam_impact()


func _exit_state(s: State) -> void:
	super(s)
	if s == State.WINDUP:
		_clear_telegraphs()


func _update_windup(delta: float) -> void:
	super(delta)
	# the aim line follows the player until the last moment
	if _throwing and state == State.WINDUP and is_instance_valid(_aim_line):
		if _state_time < windup_time - 0.15:
			_throw_dir = _to_player().normalized()
		_aim_line.rotation = _throw_dir.angle()
		_aim_line.global_position = global_position + Vector2(0.0, -4.0)


func _clear_telegraphs() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	if is_instance_valid(_aim_line):
		_aim_line.queue_free()
	_telegraph = null
	_aim_line = null


## The fists hit the floor: the shockwave damages everything inside the ellipse.
func _slam_impact() -> void:
	var host := get_parent()
	if player != null and GolemFX.ellipse_contains(_slam_center, SLAM_RADIUS, player.global_position):
		player.take_damage(melee_damage, global_position, melee_knockback)
	GolemFX.shock_ring(host, _slam_center, KIND, SLAM_RADIUS, 0.45)
	GolemFX.dust(host, _slam_center + Vector2(0.0, 4.0), KIND, 0.7)
	GolemFX.cracks(host, _slam_center, KIND, 0.7, 1.2)
	GolemFX.chips(host, _slam_center, KIND, 8, 100.0)
	GameManager.shake_camera(2.5, 0.2)


func _fire_orb() -> void:
	if _orb_scene == null:
		_orb_scene = load(ORB_PATH) as PackedScene
	if _orb_scene == null:
		return
	var orb := _orb_scene.instantiate() as BossOrb
	get_parent().add_child(orb)
	orb.global_position = global_position + _throw_dir * 14.0 + Vector2(0.0, -4.0)
	orb.setup(_throw_dir, 135.0, int(ceil(9.0 * damage_multiplier)), 130.0, 3.0)


## Plays an animation of this facing, stretched to last `seconds`.
func _play_fitted(base: String, seconds: float) -> void:
	var resolved := _resolve_anim(base)
	if not anim.sprite_frames.has_animation(resolved):
		return
	var length := float(anim.sprite_frames.get_frame_count(resolved)) / maxf(anim.sprite_frames.get_animation_speed(resolved), 0.01)
	anim.speed_scale = length / maxf(seconds, 0.05)
	anim.play(resolved)


## Stone falls apart in a cloud of dust.
func _on_died() -> void:
	_clear_telegraphs()
	var host := get_parent()
	GolemFX.dust(host, global_position + Vector2(0.0, 6.0), KIND, 0.8)
	GolemFX.chips(host, global_position, KIND, 8, 110.0)
	super()
