extends "res://scripts/enemy.gd"
## Spider: fast, fragile. Bites up close; from range it spits web bolts that snare you,
## then rushes in. Dash (i-frames) to break free. Uses the Sentinel state machine.

const BOLT: PackedScene = preload("res://scenes/fx/web_bolt.tscn")

@export var spit_range := 18.0
var spit_cd := 2.0


func _state_chase(delta: float) -> void:
	if not _player_ok():
		state = State.IDLE
		return
	var to := player.global_position - global_position
	var vertical := absf(to.y)
	to.y = 0.0
	var dist := to.length()
	if dist > leash_range or vertical > 8.0:
		state = State.IDLE
		return
	_face(player.global_position, 10.0, delta)
	spit_cd -= delta
	var snared: bool = float(player.get("snare")) > 0.0
	if dist > 2.0 and edge_ray.is_colliding():
		var dir := to / dist
		var sp := move_speed * (1.4 if snared else 1.0)
		velocity.x = dir.x * sp
		velocity.z = dir.z * sp
		_play(&"walk")
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_play(&"idle")
	if dist < 2.8 and attack_cd <= 0.0:
		_begin_attack()
	elif spit_cd <= 0.0 and dist > 6.0 and dist < spit_range and not snared:
		_begin_spit()


func _begin_spit() -> void:
	current_attack = &"spit"
	state = State.ATTACK
	attack_t = 0.0
	spit_cd = 4.0
	anim.play("spit", 0.1)


# method track in the "spit" animation
func _on_spit() -> void:
	if state != State.ATTACK or not _player_ok():
		return
	var b: Node3D = BOLT.instantiate()
	get_parent().add_child(b)
	b.setup(global_position + Vector3(0, 0.8, 0), player.global_position + Vector3(0, 1.0, 0))
