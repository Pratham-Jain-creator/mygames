class_name EdgeModule
extends Module
## Short-range blade (numbers: data/modules/edge.tres; range_m includes the lunge): high damage, high Flux cost, commit-or-die (Task 4.1).
## The swing lunges you forward (closes the gap), breaks Aegis shields and
## briefly deflects incoming Kinetic rounds.

var _cd: float = 0.0
var _last_ms: int = 0


func cooldown_ratio() -> float:
	return clampf(_cd / data.cooldown, 0.0, 1.0)


func controller_update(delta: float) -> void:
	_cd -= delta
	if pressed() and _cd <= 0.0 and player.flux.active_flux >= data.cost:
		_cd = data.cooldown
		send({"d": player.aim_dir()})


func server_use(args: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_ms < int(data.cooldown * 800.0):
		return
	if not player.flux.spend(data.cost, "edge"):
		return
	_last_ms = now
	# perfect-timing window: Kinetic rounds hitting the blade's front arc are reflected
	player.flux.deflect_until = now + FluxComponent.DEFLECT_MS
	var dir: Vector3 = args.get("d", Vector3.ZERO)
	if dir.length() < 0.5:
		dir = player.aim_dir()
	dir = dir.normalized()
	var origin: Vector3 = player.eye_pos()
	var shape := SphereShape3D.new()
	shape.radius = tune(&"radius")
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, origin + dir * (data.range_m - tune(&"radius") + 0.2))
	params.collision_mask = 2
	params.exclude = [player.get_rid()]
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var results: Array = space.intersect_shape(params, 8)
	var best: Node = null
	var best_d: float = INF
	for r in results:
		var c: Object = r["collider"]
		if not is_enemy(c):
			continue
		var chest: Vector3 = c.global_position + Vector3(0, 1.0, 0)
		var wall := PhysicsRayQueryParameters3D.create(origin, chest, 1)
		if not space.intersect_ray(wall).is_empty():
			continue
		var d: float = origin.distance_to(chest)
		if d < best_d:
			best = c
			best_d = d
	if best != null:
		hit_player(best, data.damage, "Edge", "torso", true)
	# lunge toward where you are aiming (flat), even on a miss: commit or die
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.1:
		player.send_event("lunge", {"v": flat.normalized() * tune(&"lunge_speed")})
	player.fx_play.rpc("swing", origin, origin + dir * data.range_m)
