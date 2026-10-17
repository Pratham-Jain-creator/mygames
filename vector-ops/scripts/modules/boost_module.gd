class_name BoostModule
extends Module
## Directional burst (numbers: data/modules/boost.tres). Lateral push toward the
## move input (none = straight up) plus a vertical kick.

var _cd: float = 0.0
var _last_ms: int = 0


func cooldown_ratio() -> float:
	return clampf(_cd / data.cooldown, 0.0, 1.0)


func controller_update(delta: float) -> void:
	_cd -= delta
	if pressed() and _cd <= 0.0 and player.flux.active_flux >= data.cost:
		_cd = data.cooldown
		send({"dir": player.world_move_dir()})


func server_use(args: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_ms < int(data.cooldown * 800.0):
		return
	if not player.flux.spend(data.cost, "boost"):
		return
	_last_ms = now
	var dir: Vector3 = args.get("dir", Vector3.ZERO)
	dir.y = 0.0
	if dir.length() > 0.1:
		dir = dir.normalized() * tune(&"lateral")
	else:
		dir = Vector3.ZERO
	player.send_event("impulse", {"v": dir + Vector3.UP * tune(&"vertical")})
	player.fx_play.rpc("boost", player.global_position, player.global_position)
