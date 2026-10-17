class_name EliteRoom
extends GauntletController
## The Champion's Cell: the doors seal and an ELITE enemy (three times the health, hits harder, carries materials)
## and its escort fight you. Winning unlocks a chest and drops extra materials.

const CHEST_PATH: String = "res://scenes/props/chest.tscn"

var kind: StringName
var cfg: LevelConfig
var generator: Node
var depth: int = 1


func setup_special(p_room: WFCRoom, p_kind: StringName, p_cfg: LevelConfig, p_generator: Node) -> void:
	kind = p_kind
	cfg = p_cfg
	generator = p_generator
	depth = cfg.depth
	setup(p_room, 1, int(25.0 * cfg.difficulty), Callable(generator, "pick_enemy"), Callable(generator, "_spawn_enemy"), [])
	elite_chance = 1.0 # the elite always comes
	var chest := generator._spawn_into(room, CHEST_PATH, RoomKit.spot(room, Vector2(0, -60)), {"locked": true, "bonus_materials": 1}) as Node
	if chest != null:
		_reward_chests.append(chest)


func _win() -> void:
	super()
	var at := RoomKit.center(room)
	Loot.drop_materials(RoomKit.spawned(room), at, 2, depth, RoomKit.tier(depth, 0))
	RoomKit.toast("THE CHAMPION IS DOWN", Color(1.0, 0.85, 0.5))
