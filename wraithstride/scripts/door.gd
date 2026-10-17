extends Node3D
## Portcullis. The AnimationPlayer ("open") lifts the bars and disables the collider.

@onready var anim: AnimationPlayer = $AnimationPlayer
var is_open := false


func _ready() -> void:
	var n := get_parent()
	while n != null and not n.has_method("register_door"):
		n = n.get_parent()
	if n != null:
		n.register_door(self)


func open() -> void:
	if is_open:
		return
	is_open = true
	anim.play("open")
