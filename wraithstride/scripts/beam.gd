extends Node3D
## Spell / thrust beam. Stretches a unit-length mesh from `from` to `to`;
## the fade-out and queue_free are handled by the "zap" animation in beam.tscn.


func setup(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 0.05:
		queue_free()
		return
	global_position = from
	var dir := (to - from) / dist
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	look_at(to, up)
	scale = Vector3(1.0, 1.0, dist)
