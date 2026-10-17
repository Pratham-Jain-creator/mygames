class_name DraculaMob
extends EnemyBase
## A vampire (sprites: dracula_mob.png). Up close he CLAWS (the normal EnemyBase lunge and hitbox). From a distance he
## may CALL HIS BATS, but only once in his whole life, and only 1 or 2 of them (rolled when he is born).

const SUMMON_MIN: float = 70.0
const SUMMON_MAX: float = 230.0

## Bats he can still call. 0 once he has used them.
var bats_left: int = 1
var _summoning: bool = false
var _check_clock: float = 0.0
var _base_dash: float = 0.0


func _ready() -> void:
	bats_left = 1 + randi() % 2
	_base_dash = dash_speed
	super()


func _update_chase(delta: float) -> void:
	_check_clock -= delta
	if bats_left > 0 and _cooldown <= 0.0 and _check_clock <= 0.0:
		var dist := _to_player().length()
		if dist >= SUMMON_MIN and dist <= SUMMON_MAX:
			_check_clock = 0.5
			if randf() < 0.5:
				_summoning = true
				_change_state(State.WINDUP)
				return
	_summoning = false
	super(delta)


func _enter_state(s: State) -> void:
	super(s)
	match s:
		State.WINDUP:
			if _summoning:
				dash_speed = 0.0 # he stands still to call them
				_face(_to_player())
				_play_fitted("summon", windup_time + attack_time)
				anim.self_modulate = Color(1.0, 0.6, 0.7)
		State.ATTACK:
			if _summoning:
				if attack_hitbox:
					attack_hitbox.set_deferred("monitoring", false)
				_call_bats()


func _exit_state(s: State) -> void:
	super(s)
	if s == State.ATTACK or s == State.HURT:
		dash_speed = _base_dash
		_summoning = false


func _call_bats() -> void:
	var count := bats_left
	bats_left = 0
	BossFX.puff(get_parent(), global_position, 0.9)
	Audio.play_2d(preload("res://assets/sounds/power_up.wav"), global_position, -6.0, 0.5)
	Bat.summon(get_parent(), global_position + Vector2(0, -6), count, health_multiplier, damage_multiplier, false)


func _play_fitted(base: String, seconds: float) -> void:
	var resolved := _resolve_anim(base)
	if not anim.sprite_frames.has_animation(resolved):
		return
	var length := float(anim.sprite_frames.get_frame_count(resolved)) / maxf(anim.sprite_frames.get_animation_speed(resolved), 0.01)
	anim.speed_scale = length / maxf(seconds, 0.05)
	anim.play(resolved)
