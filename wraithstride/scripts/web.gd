extends Area3D
## Spider web strands. Walking into them snares you (slow, no jump).
## A dash tears straight through (dash i-frames ignore the snare).

@export var snare_time := 2.5


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("ensnare"):
		body.ensnare(snare_time)
