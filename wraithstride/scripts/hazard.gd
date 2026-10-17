extends Area3D
## Trap hurt-zone. Anything with a die() method (the player) that touches it is slain.
## The motion (swing / spin) is an AnimationPlayer loop in the trap's scene.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("die"):
		body.die("trap")
