extends CharacterBody3D
## Wisp: floating ghost. Hovers, flashes a warning, then dives in a straight line.
## Deflect the dive to stagger it, or just dash sideways. Dies to a couple of hits.

enum S { IDLE, WIND, DIVE, RECOVER, DEAD }

@export var max_hp := 30.0
@export var detect_range := 20.0
@export var charge_speed := 18.0
@export var damage := 14.0
@export var jp_reward := 25

@onready var anim: AnimationPlayer = $AnimationPlayer

var hp := 0.0
var s: S = S.IDLE
var t := 0.0
var dir := Vector3.FORWARD
var home := Vector3.ZERO
var hit_done := false
var player: Node3D = null


func _ready() -> void:
	hp = max_hp
	home = global_position
	anim.play("idle")


func _physics_process(delta: float) -> void:
	if s == S.DEAD:
		return
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
		return
	var alive_ok: bool = player.get("alive") == true
	var aim := player.global_position + Vector3(0, 1.0, 0)
	match s:
		S.IDLE:
			velocity = velocity.move_toward(Vector3.ZERO, 20.0 * delta)
			if alive_ok and global_position.distance_to(aim) < detect_range:
				s = S.WIND
				t = 0.75
				anim.play("wind", 0.05)
		S.WIND:
			t -= delta
			dir = (aim - global_position).normalized()  # lock the dive line at the last moment
			if t <= 0.0:
				s = S.DIVE
				t = 0.8
				hit_done = false
				anim.play("dive", 0.05)
		S.DIVE:
			t -= delta
			velocity = dir * charge_speed
			if not hit_done and alive_ok and global_position.distance_to(aim) < 1.5:
				hit_done = true
				var res: String = player.receive_attack(damage, 14.0, self, false)
				if res == "deflected":
					hp -= 20.0
					if hp <= 0.0:
						_die()
						return
				_to_recover()
			elif t <= 0.0 or get_slide_collision_count() > 0:
				_to_recover()
		S.RECOVER:
			t -= delta
			velocity = velocity.move_toward(Vector3.ZERO, 25.0 * delta)
			if t <= 0.0:
				s = S.IDLE
				anim.play("idle", 0.2)
	move_and_slide()
	if global_position.y < -40.0:
		queue_free()


func _to_recover() -> void:
	s = S.RECOVER
	t = 1.1
	anim.play("recover", 0.05)


func take_hit(dmg: float, _posture: float, _from: Node3D) -> String:
	if s == S.DEAD:
		return "dead"
	hp -= dmg
	if hp <= 0.0:
		_die()
		return "kill"
	return "hit"


func _die() -> void:
	s = S.DEAD
	remove_from_group("enemy")
	$CollisionShape3D.set_deferred("disabled", true)
	anim.play("die", 0.0)
	Game.enemy_killed.emit(false, jp_reward)


func reset_to_home() -> void:
	if s == S.DEAD:
		return
	global_position = home
	velocity = Vector3.ZERO
	hp = max_hp
	s = S.IDLE
	anim.play("idle", 0.0)
