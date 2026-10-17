extends Area2D

func _ready() -> void:
	pass

func _on_body_entered(body: Node2D) -> void:
	Global.health -= 1
	if (Global.health == 0):
		get_tree().call_group("death_menu", "pause")
