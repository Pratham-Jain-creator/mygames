class_name BlastModule
extends Module
## Slow lobbed explosive (numbers: data/modules/blast.tres): big area damage, big
## Flux cost. Explosions crush Aegis (they hit it like an Edge swing). The blast
## also shoves the shooter, so aiming at your feet is a (costly) rocket-jump.

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
	if not player.flux.spend(data.cost, "blast"):
		return
	_last_ms = now
	var dir: Vector3 = args.get("d", Vector3.ZERO)
	if dir.length() < 0.5:
		dir = player.aim_dir()
	dir = (dir.normalized() + Vector3.UP * tune(&"lob")).normalized()
	Projectile.launch(player, self, "blast", player.eye_pos() + dir * 0.8, dir, tune(&"speed"), data.damage, tune(&"radius"), [], null, 0.0, 4.0, tune(&"gravity"))
	player.fx_play.rpc("cast", player.eye_pos(), player.eye_pos())
