class_name KineticModule
extends Module
## Hitscan rifle with aim-skill mechanics (numbers: data/modules/kinetic.tres):
##  - spread grows while sprinting, airborne, moving and firing continuously
##  - head 1.5x, torso 1x, limbs 0.85x. Leg hit = slow, arm hit = that hand off
##  - damage falls off between falloff_start and falloff_end metres

const ZONE_MULT := {"head": 1.5, "torso": 1.0, "leg": 0.85, "arm_r": 0.85, "arm_l": 0.85}

var _cd: float = 0.0
var _bloom: float = 0.0
var _last_shot_ms: int = 0


func controller_update(delta: float) -> void:
	_cd -= delta
	if not held():
		_bloom = maxf(0.0, _bloom - 3.5 * delta)
	var spread: float = _current_spread()
	player.spread_deg = spread
	if held() and _cd <= 0.0 and player.flux.active_flux >= data.cost:
		_cd = data.cooldown
		_bloom = minf(_bloom + 0.35, tune(&"max_bloom"))
		# "m" = where the barrel is on this peer's screen, so the tracer leaves the muzzle
		send({"d": _apply_spread(player.aim_dir(), spread), "m": player.viewmodel.muzzle_of("kinetic", hand)})


func _current_spread() -> float:
	var s: float = tune(&"base_spread") + _bloom
	if player.is_sprinting():
		s += 2.0
	if not player.is_on_floor():
		s += 1.4
	var hv: float = Vector2(player.velocity.x, player.velocity.z).length()
	s += 0.5 * clampf(hv / 6.0, 0.0, 1.0)
	return s


func _apply_spread(dir: Vector3, deg: float) -> Vector3:
	var ang: float = deg_to_rad(deg) * sqrt(randf())
	var rot: float = randf() * TAU
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var b := Basis.looking_at(dir, up)
	return (b * Vector3(sin(ang) * cos(rot), sin(ang) * sin(rot), -cos(ang))).normalized()


func server_use(args: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_shot_ms < int(data.cooldown * 700.0):
		return
	if not player.flux.spend(data.cost, "kinetic"):
		return
	_last_shot_ms = now
	var dir: Vector3 = args.get("d", Vector3.ZERO)
	if dir.length() < 0.5:
		dir = player.aim_dir()
	dir = dir.normalized()
	var origin: Vector3 = player.eye_pos()
	var muzzle: Vector3 = args.get("m", Vector3.ZERO)
	if muzzle == Vector3.ZERO or muzzle.distance_to(origin) > 2.5:
		muzzle = player.viewmodel.muzzle_of("kinetic", hand) # bots / bad data: use the server's own copy of the gun
	if muzzle == Vector3.ZERO or muzzle.distance_to(origin) > 2.5:
		muzzle = origin
	var end: Vector3 = origin + dir * data.range_m
	var q := PhysicsRayQueryParameters3D.create(origin, end, 3, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"]
		var c: Object = hit["collider"]
		if is_enemy(c) and c.flux.is_deflecting(player.global_position):
			# Edge timing: the round is reflected back at the shooter
			c.flux._fx("block")
			player.flux.take_damage(data.damage, c, "Deflected Kinetic", c.global_position)
			player.send_event("hurt", {"from": c.global_position, "blocked": false, "zone": "torso"})
			c.send_event("hit", {"killed": player.flux.ejected, "blocked": false, "zone": "torso"})
		elif c is Bunker:
			c.damage(data.damage)
		elif is_enemy(c):
			var zone: String = hit_zone(c, end)
			var dist: float = origin.distance_to(end)
			var span: float = tune(&"falloff_end") - tune(&"falloff_start")
			var fall: float = 1.0 - 0.5 * clampf((dist - tune(&"falloff_start")) / span, 0.0, 1.0)
			hit_player(c, data.damage * float(ZONE_MULT[zone]) * fall, "Kinetic", zone)
	player.fx_play.rpc("shot", muzzle, end)
