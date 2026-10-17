class_name AegisModule
extends Module
## Directional shield (Task 2.2). Hold this hand's mouse button to raise it.
## 90 degree arc, 2 Flux/s upkeep, blocked hits cost 60% of their damage in
## Active Flux. It slows you, needs 0.25 s to raise, never protects Fractured
## Flux, and an Edge hit breaks it. Blocking is resolved in FluxComponent; the
## shield mesh is shown by the Player whenever flux.shield_on is true.

var _t: float = 0.0


func controller_update(delta: float) -> void:
	_t -= delta
	# shield is up if ANY hand holding an Aegis is pressed
	var want: bool = false
	for h in 2:
		var m = player.active_module(h)
		if m != null and m is AegisModule and m.held():
			want = true
	want = want and player.flux.active_flux > 1.0 and not player.flux.shield_locked
	if _t <= 0.0 and want != player.flux.shield_on:
		_t = 0.1
		send({"on": want})


func server_use(args: Dictionary) -> void:
	player.flux.set_shield(bool(args.get("on", false)))
