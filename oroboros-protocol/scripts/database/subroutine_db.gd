class_name SubroutineDB
extends RefCounted
## The "poker hands". recipe = [data, ice, breach, coolant] counts.
## Firmware Updates raise `lvl_base` / `lvl_mult` per level.
## "surgical_strike" and "fragment" are additions so every 3-node combo scores.

const ORDER := [
	"data_dump", "skirmish", "overclock", "cache_clear",
	"desperation", "maintenance", "surgical_strike",
]

const SUBS := {
	"data_dump": {"name": "Bulk Siphon", "recipe": [3, 0, 0, 0], "base": 20, "mult": 1, "lvl_base": 15, "lvl_mult": 1, "text": "3 Siphons"},
	"skirmish": {"name": "Skirmish", "recipe": [0, 2, 1, 0], "base": 0, "mult": 3, "lvl_base": 10, "lvl_mult": 1, "text": "1 Firewall, 2 Glitches"},
	"overclock": {"name": "Full Spectrum", "recipe": [1, 1, 0, 1], "base": 10, "mult": 2, "lvl_base": 15, "lvl_mult": 1, "text": "1 Siphon, 1 Glitch, 1 Patch"},
	"cache_clear": {"name": "Cache Clear", "recipe": [2, 0, 1, 0], "base": 30, "mult": 0, "lvl_base": 20, "lvl_mult": 1, "text": "1 Firewall, 2 Siphons"},
	"desperation": {"name": "Desperation", "recipe": [0, 3, 0, 0], "base": 0, "mult": 5, "lvl_base": 10, "lvl_mult": 2, "text": "3 Glitches"},
	"maintenance": {"name": "Maintenance", "recipe": [1, 0, 0, 2], "base": 10, "mult": 1, "lvl_base": 15, "lvl_mult": 1, "text": "2 Patches, 1 Siphon"},
	"surgical_strike": {"name": "Surgical Strike", "recipe": [1, 1, 1, 0], "base": 15, "mult": 2, "lvl_base": 10, "lvl_mult": 1, "text": "1 Firewall, 1 Glitch, 1 Siphon"},
	"fragment": {"name": "Fragment", "recipe": [-1, -1, -1, -1], "base": 5, "mult": 0, "lvl_base": 0, "lvl_mult": 0, "text": "Any other combination"},
}


static func identify(nodes: Array) -> String:
	# 4 Nodes: the best Subroutine formed by any 3 of them counts (the 4th just adds its value).
	if nodes.size() > 3:
		for id in ORDER:
			for skip in nodes.size():
				var sub: Array = nodes.duplicate()
				sub.remove_at(skip)
				var cc := [0, 0, 0, 0]
				for n in sub:
					cc[n.type] += 1
				if SUBS[id].recipe == cc:
					return id
		return "fragment"
	var c := [0, 0, 0, 0]
	for n in nodes:
		c[n.type] += 1
	for id in ORDER:
		if SUBS[id].recipe == c:
			return id
	return "fragment"


static func name_of(id: String) -> String:
	return SUBS[id].name


static func base_for(id: String, level: int) -> int:
	return int(SUBS[id].base) + int(SUBS[id].lvl_base) * level


static func mult_for(id: String, level: int) -> int:
	return int(SUBS[id].mult) + int(SUBS[id].lvl_mult) * level
