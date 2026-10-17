extends Node3D
## Pendulum axe. The swing itself is the "swing" animation; this only offsets the phase
## so two axes in a row don't swing in lockstep.

@export var phase := 0.0


func _ready() -> void:
	$AnimationPlayer.play("swing")
	$AnimationPlayer.seek(phase, true)
