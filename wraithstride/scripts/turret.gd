extends StaticBody3D
## Sentry totem. Tracks you, charges (glow), fires a spark bolt. Deflect the bolt or break line of sight.
## It can be destroyed, but never has to be.

const BOLT: PackedScene = preload("res://scenes/fx/spark_bolt.tscn")

@export var fire_interval := 2.8
@export var range_m := 30.0
@export var max_hp := 70.0
@export var jp_reward := 30

@onready var head: Node3D = $Head
@onready var muzzle: Marker3D = $Head/Muzzle
@onready var anim: AnimationPlayer = $AnimationPlayer

var hp := 0.0
var cd := 1.5
var dead := false
var player: Node3D = null


func _ready() -> void:
	hp = max_hp
	anim.play("idle")


func _physics_process(delta: float) -> void:
	if dead:
		return
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
		return
	if player.get("alive") != true:
		return
	var aim := player.global_position + Vector3(0, 1.0, 0)
	if muzzle.global_position.distance_to(aim) > range_m:
		return
	head.look_at(aim, Vector3.UP)
	cd -= delta
	if cd <= 0.0 and _has_line_of_sight(aim):
		cd = fire_interval
		anim.play("charge", 0.05)  # method track calls _fire at the end of the glow


func _has_line_of_sight(aim: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(muzzle.global_position, aim, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# method track in "charge"
func _fire() -> void:
	if dead or not is_instance_valid(player):
		return
	var b: Node3D = BOLT.instantiate()
	get_parent().add_child(b)
	b.setup(muzzle.global_position, player.global_position + Vector3(0, 1.0, 0))


func take_hit(dmg: float, _posture: float, _from: Node3D) -> String:
	if dead:
		return "dead"
	hp -= dmg
	if hp <= 0.0:
		dead = true
		remove_from_group("enemy")
		$CollisionShape3D.set_deferred("disabled", true)
		anim.play("die", 0.0)
		Game.enemy_killed.emit(false, jp_reward)
		return "kill"
	return "hit"


func reset_to_home() -> void:
	if not dead:
		hp = max_hp
		cd = 1.5
