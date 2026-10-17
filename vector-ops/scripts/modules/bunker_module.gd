class_name BunkerModule
extends Module
## Barricade: drops a static wall on the floor a few metres in front of you,
## square to your facing - no need to aim at the ground. Look at an existing
## barricade to stack the new one on top of it. A white outline shows where it
## will go. You can have several; each only breaks when its health runs out.

const PREVIEW_SCENE := preload("res://scenes/combat/bunker_preview.tscn")

var _cd: float = 0.0
var _last_ms: int = 0
var _preview: Node3D = null


func cooldown_ratio() -> float:
	return clampf(_cd / data.cooldown, 0.0, 1.0)


func controller_update(delta: float) -> void:
	_cd -= delta
	if pressed() and _cd <= 0.0 and player.flux.active_flux >= data.cost:
		_cd = data.cooldown
		send({"d": player.aim_dir()})


## White outline of the spot the barricade would take (local player only).
func _process(_delta: float) -> void:
	var show_it: bool = player != null and player.is_local and is_active and GameState.phase == GameState.Phase.LIVE \
			and not player.flux.ejected and not player.flux.hand_off(hand)
	var xf = placement(player.aim_dir()) if show_it else null
	if xf == null:
		if _preview != null:
			_preview.visible = false
		return
	if _preview == null:
		_preview = PREVIEW_SCENE.instantiate()
		player.get_tree().current_scene.add_child(_preview)
	_preview.visible = true
	_preview.global_transform = xf


func _on_deactivate() -> void:
	_free_preview()


func _exit_tree() -> void:
	_free_preview()


func _free_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


func _deny() -> void:
	player.send_event("deny", {})


## Where a barricade would go if placed now (Transform3D), or null if there is no valid spot.
func placement(aim: Vector3):
	var dir := Vector3(aim.x, 0.0, aim.z)
	if dir.length() < 0.1:
		dir = -player.global_transform.basis.z
		dir.y = 0.0
	dir = dir.normalized()
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var base: Vector3 = player.global_position
	var chest: Vector3 = base + Vector3(0, 1.0, 0)
	var xf: Transform3D
	var stacking := false
	var wall: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + dir * (tune(&"place_dist") + 1.0), 1, [player.get_rid()]))
	if not wall.is_empty() and wall["collider"] is Bunker:
		# looking at a barricade: the new one goes on top of it
		var b: Bunker = wall["collider"]
		xf = Transform3D(b.global_basis, b.global_position + Vector3(0, Bunker.SIZE.y, 0))
		stacking = true
	else:
		var place_dist: float = tune(&"place_dist")
		var spot: Vector3 = base + dir * place_dist
		if not wall.is_empty():
			var wd: float = chest.distance_to(wall["position"]) - 0.6
			if wd < tune(&"min_dist"):
				return null
			spot = base + dir * minf(place_dist, wd)
		var floor_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3(0, 1.5, 0), spot + Vector3(0, -6.0, 0), 1, [player.get_rid()]))
		if floor_hit.is_empty() or Vector3(floor_hit["normal"]).y < 0.6:
			return null
		xf = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), floor_hit["position"] + Vector3(0, Bunker.SIZE.y * 0.5, 0))
	# the spot must be free of other barricades (when stacking, climb to the next free level)
	var solid := BoxShape3D.new()
	solid.size = Bunker.SIZE - Vector3(0.1, 0.1, 0.1)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = solid
	q.collision_mask = 1
	for i in 3:
		q.transform = xf
		if space.intersect_shape(q, 1).is_empty():
			break
		if not stacking or i == 2:
			return null
		xf.origin.y += Bunker.SIZE.y
	if xf.origin.y - base.y > tune(&"max_up"):
		return null
	# never trap a player inside the wall
	var room := BoxShape3D.new()
	room.size = Bunker.SIZE + Vector3(0.4, 0.0, 0.4)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = room
	params.transform = xf
	params.collision_mask = 2
	if not space.intersect_shape(params, 1).is_empty():
		return null
	return xf


func server_use(args: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_ms < int(data.cooldown * 800.0) or player.flux.active_flux < data.cost:
		return
	var xf = placement(args.get("d", Vector3.ZERO))
	if xf == null:
		_deny()
		return
	if not player.flux.spend(data.cost, "bunker"):
		return
	_last_ms = now
	player.place_bunker(xf)
