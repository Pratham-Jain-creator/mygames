extends Area3D
## Soul shrine. Touch it once to set the respawn point.

var activated := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if activated or not body.is_in_group("player"):
		return
	activated = true
	Game.set_checkpoint(global_position + Vector3(0.0, 0.3, 0.0), body.rotation.y)
	$AnimationPlayer.play("activate")
	$AnimationPlayer.queue("active_idle")
	Game.message.emit("Soul shrine awakened")
