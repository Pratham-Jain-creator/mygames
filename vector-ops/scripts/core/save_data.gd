class_name SaveData
extends RefCounted
## Persists the player's profile between sessions in user://vector_ops.cfg:
## operator name, current loadout, settings and the saved custom builds.
## The live values stay in GameState; this only reads and writes them.

const PATH := "user://vector_ops.cfg"
const NAME_MAX := 16
const BUILD_NAME_MAX := 20


static func load_all() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		apply_audio()
		return
	var nm: String = String(cf.get_value("profile", "name", GameState.local_name)).strip_edges()
	GameState.local_name = nm.substr(0, NAME_MAX) if nm != "" else "Operator"
	var lo: Variant = cf.get_value("profile", "loadout", GameState.local_loadout)
	GameState.local_loadout = Loadout.sanitize(lo if lo is Array else [])
	GameState.sens_mult = clampf(float(cf.get_value("settings", "sens", 1.0)), 0.3, 3.0)
	GameState.fov_setting = clampf(float(cf.get_value("settings", "fov", 85.0)), 60.0, 110.0)
	GameState.master_volume = clampf(float(cf.get_value("settings", "volume", 1.0)), 0.0, 1.0)
	GameState.saved_builds = []
	var raw: Variant = cf.get_value("builds", "list", [])
	if raw is Array:
		for b in raw:
			if b is Dictionary and b.has("name") and b.has("sel") and b["sel"] is Array:
				GameState.saved_builds.append({"name": String(b["name"]).substr(0, BUILD_NAME_MAX), "sel": Loadout.sanitize(b["sel"])})
	apply_audio()


static func save_all() -> void:
	var cf := ConfigFile.new()
	cf.set_value("profile", "name", GameState.local_name)
	cf.set_value("profile", "loadout", GameState.local_loadout)
	cf.set_value("settings", "sens", GameState.sens_mult)
	cf.set_value("settings", "fov", GameState.fov_setting)
	cf.set_value("settings", "volume", GameState.master_volume)
	cf.set_value("builds", "list", GameState.saved_builds)
	cf.save(PATH)


static func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(GameState.master_volume, 0.0001)))
