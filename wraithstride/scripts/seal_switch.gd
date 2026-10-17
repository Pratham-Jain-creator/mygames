extends Area3D
## Seal orb. Touch it to break the seal. Place it somewhere risky; the room's doors need every seal.

@onready var anim: AnimationPlayer = $AnimationPlayer
var room: Node = null
var done := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	anim.play("idle")
	var n := get_parent()
	while n != null and not n.has_method("register_switch"):
		n = n.get_parent()
	room = n
	if room != null:
		room.register_switch(self)


func _on_body_entered(body: Node3D) -> void:
	if done or not body.has_method("die"):
		return
	done = true
	anim.play("press")
	if room != null:
		room.switch_pressed(self)
