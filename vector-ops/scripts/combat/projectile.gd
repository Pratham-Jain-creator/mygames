class_name Projectile
extends Node3D
## Server-simulated slow projectile (Blast, Seeker). Every peer shows a
## cosmetic mirror driven by Player.proj_sync.

var shooter: Player
var module: Module
var kind: String = "seeker"
var speed: float = 24.0
var damage: float = 20.0
var radius: float = 0.0 # explosion radius (0 = direct hit only)
var dir: Vector3 = Vector3.FORWARD
var path: Array = []
var target: Player = null
var turn_rate: float = 0.0
var life: float = 4.0
var gravity: float = 0.0 # > 0 makes the projectile fall in an arc (Blast)
var pid: int = 0
var _wp: int = 0


static func launch(sh: Player, mod: Module, k: String, from: Vector3, d: Vector3, spd: float,
		dmg: float, rad: float, wps: Array, tgt: Player, turn: float, life_s: float = 4.0, grav: float = 0.0) -> void:
	var scene := sh.get_tree().current_scene
	if scene == null:
		return
	var p := Projectile.new()
	p.shooter = sh
	p.module = mod
	p.kind = k
	p.speed = spd
	p.damage = dmg
	p.radius = rad
	p.dir = d.normalized()
	p.path = wps
	p.target = tgt
	p.turn_rate = turn
	p.life = life_s
	p.gravity = grav
	p.pid = randi()
	scene.add_child(p)
	p.global_position = from


func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter) or not is_instance_valid(module) or GameState.phase != GameState.Phase.LIVE:
		queue_free()
		return
	life -= delta
	if life <= 0.0:
		_finish()
		return
	if gravity > 0.0:
		var vel: Vector3 = dir * speed + Vector3(0, -gravity * delta, 0)
		speed = vel.length()
		dir = vel / speed
	var step: float = speed * delta
	if _wp < path.size():
		var to: Vector3 = path[_wp] - global_position
		if to.length() <= step + 0.4:
			_wp += 1
		else:
			dir = to.normalized()
	elif target != null and is_instance_valid(target) and not target.flux.ejected and turn_rate > 0.0:
		var want: Vector3 = (target.global_position + Vector3(0, 1.1, 0) - global_position).normalized()
		var ang: float = dir.angle_to(want)
		if ang > 0.001:
			dir = dir.slerp(want, clampf(turn_rate * delta / ang, 0.0, 1.0)).normalized()
	var from: Vector3 = global_position
	var to_p: Vector3 = from + dir * step
	var q := PhysicsRayQueryParameters3D.create(from, to_p, 3, [shooter.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"]
		_impact(hit["position"], hit["collider"])
		return
	global_position = to_p
	shooter.proj_sync.rpc(pid, kind, global_position, true)


func _impact(pos: Vector3, collider: Object) -> void:
	if kind == "seeker" and module.is_enemy(collider) and collider.flux.shield_stops(pos):
		# an Aegis in the way eats the Seeker: no damage, no Flux cost for the shield
		collider.flux._fx("block")
		shooter.send_event("hit", {"killed": false, "blocked": true, "zone": "torso"})
		collider.send_event("hurt", {"from": pos, "blocked": true, "zone": "torso"})
		_finish()
		return
	if radius > 0.0:
		_explode(pos)
	elif module.is_enemy(collider):
		var z: String = module.hit_zone(collider, pos)
		module.hit_player(collider, damage * (1.5 if z == "head" else 1.0), module.data.display_name, z)
	elif collider is Bunker:
		collider.damage(damage)
	_finish()


func _explode(pos: Vector3) -> void:
	shooter.fx_play.rpc("boom", pos, pos)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for p in get_tree().get_nodes_in_group("players"):
		if p.flux.ejected:
			continue
		var c: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		var d: float = c.distance_to(pos)
		if d > radius:
			continue
		var enemy: bool = p.team != shooter.team
		if enemy:
			var wall := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.2, 0), c, 1)
			if not space.intersect_ray(wall).is_empty():
				continue
			module.hit_player(p, damage * lerpf(1.0, 0.4, d / radius), "Blast", "torso", true)
		if enemy or p == shooter:
			var push: Vector3 = (c - pos).normalized() * 9.0 * (1.0 - d / radius)
			p.send_event("impulse", {"v": Vector3(push.x, 3.0 + maxf(push.y, 0.0) + 4.0 * (1.0 - d / radius), push.z)})
	for b in get_tree().get_nodes_in_group("bunkers"):
		if b.global_position.distance_to(pos) < radius + 1.5:
			b.damage(damage * 0.8)


func _finish() -> void:
	if is_instance_valid(shooter):
		shooter.proj_sync.rpc(pid, kind, global_position, false)
	queue_free()
