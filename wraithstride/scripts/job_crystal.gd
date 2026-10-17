extends Area3D
## Job crystal. Stand inside and press F to cycle to the next job (FFT-style job change).

var _inside := false


func _ready() -> void:
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	Game.job_changed.connect(_on_job_changed)


func _on_enter(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.near_crystal = true
		_inside = true


func _on_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.near_crystal = false
		_inside = false


func _on_job_changed(_id: StringName) -> void:
	if _inside:
		$AnimationPlayer.play("shine")
		$AnimationPlayer.queue("hum")
