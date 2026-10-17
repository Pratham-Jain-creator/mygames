class_name ShiftModule
extends Module
## Blink (Shift): short-range teleport (numbers: data/modules/shift.tres), cancels velocity. The destination
## is raycast-validated and capsule-tested so the player never clips into walls.

var _cd: float = 0.0
var _last_ms: int = 0


func cooldown_ratio() -> float:
	return clampf(_cd / data.cooldown, 0.0, 1.0)


func controller_update(delta: float) -> void:
	_cd -= delta
	if pressed() and _cd <= 0.0 and player.flux.active_flux >= data.cost:
		var t: Vector3 = _compute_target()
		if t.is_finite():
			_cd = data.cooldown
			send({"to": t})


func _compute_target() -> Vector3:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var origin: Vector3 = player.eye_pos()
	var dir: Vector3 = player.aim_dir()
	dir = Vector3(dir.x, maxf(dir.y, 0.0), dir.z).normalized()
	var end: Vector3 = origin + dir * data.range_m
	var q := PhysicsRayQueryParameters3D.create(origin, end, 1, [player.get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"] + hit["normal"] * 0.6
	var foot_target: Vector3 = end - Vector3(0, player.EYE_HEIGHT, 0)
	var foot_start: Vector3 = player.global_position
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1
	for i in 10:
		var f: float = 1.0 - float(i) * 0.1
		var cand: Vector3 = foot_start.lerp(foot_target, f) + Vector3(0, 0.08, 0)
		params.transform = Transform3D(Basis.IDENTITY, cand + Vector3(0, 0.9, 0))
		if space.intersect_shape(params, 1).is_empty():
			if cand.distance_to(foot_start) < 1.0:
				return Vector3.INF
			return cand
	return Vector3.INF


func server_use(args: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_ms < int(data.cooldown * 800.0):
		return
	var to: Vector3 = args.get("to", Vector3.INF)
	if not to.is_finite() or player.global_position.distance_to(to) > data.range_m + 3.0:
		return
	if not player.flux.spend(data.cost, "shift"):
		return
	_last_ms = now
	var from: Vector3 = player.global_position
	player.send_event("teleport", {"pos": to})
	player.fx_play.rpc("shift", from + Vector3(0, 1, 0), to + Vector3(0, 1, 0))
