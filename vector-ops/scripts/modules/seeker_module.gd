class_name SeekerModule
extends Module
## Homing projectile (numbers: data/modules/seeker.tres). Locks the visible
## enemy closest to the crosshair when fired. Ghosts cannot be locked. Hold to keep firing.

var _cd: float = 0.0
var _last_ms: int = 0


func cooldown_ratio() -> float:
	return clampf(_cd / data.cooldown, 0.0, 1.0)


func controller_update(delta: float) -> void:
	_cd -= delta
	if held() and _cd <= 0.0 and player.flux.active_flux >= data.cost:
		_cd = data.cooldown
		send({"d": player.aim_dir()})


func server_use(args: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_ms < int(data.cooldown * 800.0):
		return
	if not player.flux.spend(data.cost, "seeker"):
		return
	_last_ms = now
	var dir: Vector3 = args.get("d", Vector3.ZERO)
	if dir.length() < 0.5:
		dir = player.aim_dir()
	dir = dir.normalized()
	var eye: Vector3 = player.eye_pos()
	Projectile.launch(player, self, "seeker", eye + dir * 0.6, dir, tune(&"speed"), data.damage, 0.0, [], _find_target(eye, dir), tune(&"turn"), tune(&"flight_time"))
	player.fx_play.rpc("cast", eye, eye)


## The visible enemy closest to the aim direction inside the lock cone and range.
func _find_target(eye: Vector3, dir: Vector3) -> Player:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var best: Player = null
	var best_dot: float = tune(&"lock_dot")
	for p in player.get_tree().get_nodes_in_group("players"):
		if p.team == player.team or p.flux.ejected or p.flux.stealth == 1:
			continue
		var c: Vector3 = p.global_position + Vector3(0, 1.1, 0)
		if eye.distance_to(c) > data.range_m:
			continue
		var dt: float = dir.dot((c - eye).normalized())
		if dt <= best_dot:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, c, 1)).is_empty():
			continue
		best = p
		best_dot = dt
	return best
