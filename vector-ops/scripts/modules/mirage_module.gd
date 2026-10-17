class_name MirageModule
extends Module
## Optical camouflage. Press to toggle. Your body turns (almost) invisible but
## you stay fully visible on enemy radar. Turning it on turns Ghost off.

var _cd: float = 0.0


func controller_update(delta: float) -> void:
	_cd -= delta
	if pressed() and _cd <= 0.0:
		_cd = 0.3
		send({})


func server_use(_args: Dictionary) -> void:
	player.flux.toggle_stealth(2)
