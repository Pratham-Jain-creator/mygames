extends Area3D
## Projectile: web bolts (snare) and turret sparks (damage). Deflect it with RMB to destroy it.

@export var speed := 16.0
@export var damage := 8.0
@export var posture_damage := 10.0
@export var snare_time := 2.2
@export var life := 4.0

var dir := Vector3.FORWARD


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## Call after add_child().
func setup(from: Vector3, to: Vector3) -> void:
	global_position = from
	dir = (to - from).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.99:
		look_at(from + dir, Vector3.UP)


func _physics_process(delta: float) -> void:
	global_position += dir * speed * delta  # straight-line travel: position += direction * speed * dt
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("receive_attack"):
		var res: String = body.receive_attack(damage, posture_damage, self, false)
		if res == "hit" and snare_time > 0.0 and body.has_method("ensnare"):
			body.ensnare(snare_time)
		if res == "evaded":
			return  # i-frames: the bolt flies on through
	queue_free()
