class_name BoltModule
extends Module
## Heavy sniper (numbers: data/modules/bolt.tres). First click opens the scope (zoomed, you cannot move at all),
## the next click fires and closes it. Slide (Shift / B) cancels.
## On a gamepad, a shot that misses by a little is bent onto the target (Player.pad_snap). Carrying a Bolt slows you.
## One huge Flux spend per shot, and the shot flags your position on the enemy
## radar (even through Ghost) for a while.

const ZONE_MULT := {"head": 2.0, "torso": 1.0, "leg": 0.85, "arm_r": 0.85, "arm_l": 0.85}

var _cd: float = 0.0
var _last_ms: int = 0


func cooldown_ratio() -> float:
	return clampf(_cd / data.cooldown, 0.0, 1.0)


func _on_deactivate() -> void:
	player.scoped = false


func _spread() -> float:
	if player.scoped:
		return 0.02
	var s: float = 0.05
	if not player.is_on_floor():
		s += 3.0
	s += 2.5 * clampf(Vector2(player.velocity.x, player.velocity.z).length() / 4.0, 0.0, 1.0)
	return s


func controller_update(delta: float) -> void:
	_cd -= delta
	player.spread_deg = _spread()
	if player.scoped:
		if player.cmd.slide_pressed and not player.is_bot:
			player.scoped = false # Shift / B cancels the scope
		elif player.flux.active_flux < data.cost:
			player.scoped = false # can't fire any more: never leave the player frozen
		elif pressed() and _cd <= 0.0:
			_cd = data.cooldown
			send({"d": cone(player.pad_snap(player.aim_dir()), _spread())})
			player.scoped = false
	elif pressed():
		if player.flux.active_flux >= data.cost:
			player.scoped = true # first click: scope in
		else:
			player.send_event("deny", {}) # not enough Flux to fire: no scope


func server_use(args: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_ms < int(data.cooldown * 800.0):
		return
	if not player.flux.spend(data.cost, "bolt"):
		return
	_last_ms = now
	player.flux.signature = maxf(player.flux.signature, FluxComponent.SIG_BOLT)
	var dir: Vector3 = args.get("d", Vector3.ZERO)
	if dir.length() < 0.5:
		dir = player.aim_dir()
	dir = dir.normalized()
	var origin: Vector3 = player.eye_pos()
	var end: Vector3 = origin + dir * data.range_m
	var q := PhysicsRayQueryParameters3D.create(origin, end, 3, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"]
		var c: Object = hit["collider"]
		if c is Bunker:
			c.damage(data.damage)
		elif is_enemy(c):
			var zone: String = hit_zone(c, end)
			hit_player(c, data.damage * float(ZONE_MULT[zone]), "Bolt", zone)
	player.fx_play.rpc("bolt", origin, end)
