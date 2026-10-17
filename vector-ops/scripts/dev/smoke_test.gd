extends Node
## Dev tool, NOT registered by default. To use it: add
##   SmokeTest="*res://scripts/dev/smoke_test.gd"
## under [autoload] in project.godot (and remove it again afterwards). It starts a
## solo match, then drives every module's controller/server code once and prints
## "SMOKE ..." lines, so script errors in any module show up in the output.

func _ready() -> void:
	await get_tree().create_timer(2.5).timeout
	for id in Loadout.ids():
		var d := Loadout.get_data(id)
		print("SMOKE data ", id, " | ", d.hud_meta, " | ", d.description)
	GameState.solo_game()
	var lp = null
	for i in 40:
		await get_tree().create_timer(1.0).timeout
		lp = GameState.get_local_player()
		print("SMOKE t=", i, " phase=", GameState.phase, " in_session=", GameState.in_session, " lp=", lp)
		if lp != null and GameState.phase == GameState.Phase.LIVE:
			break
	if lp == null:
		return
	for id in Loadout.ids():
		var m: Module = Loadout.create_module(id)
		lp.add_child(m)
		m.setup(lp, 0, 0)
		m.activate()
		lp.flux.active_flux = lp.flux.max_flux
		var aim: Vector3 = lp.aim_dir()
		var args := {"d": aim, "path": [lp.eye_pos() + aim * 5.0], "to": lp.global_position + Vector3(2, 0, 0), "dir": Vector3.ZERO, "on": true}
		m.controller_update(0.016)
		m.server_use(args)
		print("SMOKE ok ", id, " cooldown_ratio=", m.cooldown_ratio())
		await get_tree().create_timer(0.4).timeout
		m.deactivate()
		m.queue_free()
	print("SMOKE done")
