extends "res://scripts/enemy.gd"
## Brute: oversized Sentinel. Slow, huge posture bar, hits hard, thrusts often.


func _ready() -> void:
	super()
	$Model.scale = Vector3.ONE * 1.4
	$HpBar.position.y = 3.3
	$PostureBar.position.y = 3.15
