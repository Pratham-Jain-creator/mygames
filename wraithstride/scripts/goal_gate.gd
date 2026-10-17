extends Area3D
## Exit gate. Entering it stops the run clock and announces the clear time.

var _done := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _done or not body.is_in_group("player"):
		return
	_done = true
	Game.run_active = false
	$AnimationPlayer.play("activate")
	Game.level_cleared.emit(Game.run_time)
