class_name HealModule
extends Module
## One-shot heal. Press once per round, then stand still for about a second
## (moving, sprinting, being hit or swapping the module away cancels it and
## the charge is NOT spent). It refills Active Flux up to your current cap,
## so Fractured Flux stays lost. The channel itself lives in FluxComponent
## (start_heal / heal_used / healing); this module only asks for it.

var _cd: float = 0.0


## Fully grey once this round's charge is spent.
func cooldown_ratio() -> float:
	return 1.0 if player.flux.heal_used else 0.0


func controller_update(delta: float) -> void:
	_cd -= delta
	if pressed() and _cd <= 0.0:
		_cd = 0.4
		send({})


func server_use(_args: Dictionary) -> void:
	if not player.flux.start_heal():
		player.send_event("deny", {})
