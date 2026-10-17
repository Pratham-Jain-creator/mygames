class_name GhostModule
extends Module
## Radar stealth. Press to toggle. While running, enemies do not see your blip
## unless you recently used something else (your signature fades only while
## Ghost is running). Turning it on turns Mirage off.

var _cd: float = 0.0


func controller_update(delta: float) -> void:
	_cd -= delta
	if pressed() and _cd <= 0.0:
		_cd = 0.3
		send({})


func server_use(_args: Dictionary) -> void:
	player.flux.toggle_stealth(1)
