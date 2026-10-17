class_name MetaSave
extends RefCounted
## Tiny persistent storage (settings + cross-run bonuses like Seed Capital).

const PATH := "user://meta.cfg"


static func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(PATH)
	return c


static func get_value(section: String, key: String, default: Variant) -> Variant:
	return _cfg().get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	var c := _cfg()
	c.set_value(section, key, value)
	c.save(PATH)


static func consume_start_bonus() -> int:
	var v: int = int(get_value("run", "start_bonus", 0))
	if v != 0:
		set_value("run", "start_bonus", 0)
	return v


static func record_run(network_reached: int, won: bool) -> void:
	var c := _cfg()
	c.set_value("stats", "runs", int(c.get_value("stats", "runs", 0)) + 1)
	c.set_value("stats", "wins", int(c.get_value("stats", "wins", 0)) + (1 if won else 0))
	c.set_value("stats", "best_network", maxi(int(c.get_value("stats", "best_network", 0)), network_reached))
	c.save(PATH)
