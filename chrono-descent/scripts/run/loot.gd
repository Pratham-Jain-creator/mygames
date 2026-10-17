class_name Loot
extends RefCounted
## What things drop. Ash comes from everything that dies (a little more on deeper floors). Macabre MATERIALS come from
## elites, bosses and special rooms, never from common enemies. A boss drops its blueprint the first time it falls.

## Base ash per enemy, by scene name. Anything not listed drops DEFAULT_ASH.
const ASH_BY_ENEMY: Dictionary = {
	"slime": 4, "skeleton_warrior": 6, "skeleton_archer": 6, "bat": 2, "dracula": 14, "skull_spirit": 9, "mini_golem": 12,
	"mimic_chest": 18, "slime_queen": 70, "golem_boss": 90, "mimic_boss": 110, "dracula_boss": 200,
}
const DEFAULT_ASH: int = 5
const ELITE_ASH_MULT: float = 3.5


## Ash scales with the floor (+6% per floor) and with the Ash Magnet charm (applied by Run.add_ash).
static func floor_scale(depth: int) -> float:
	return 1.0 + 0.06 * float(maxi(depth - 1, 0))


## Everything an enemy leaves behind. `parent` is where the pickups are put.
static func enemy_died(enemy: EnemyBase) -> void:
	if enemy.has_meta("boss_loot_by_room"):
		return # a boss room pays out (see BossRoomController)
	var parent := enemy.get_parent()
	if parent == null:
		return
	var depth := maxi(GameManager.current_depth, 1)
	var scene_name := enemy.scene_file_path.get_file().get_basename()
	var ash := float(ASH_BY_ENEMY.get(scene_name, DEFAULT_ASH)) * floor_scale(depth)
	if enemy.is_elite:
		ash *= ELITE_ASH_MULT
	drop_ash(parent, enemy.global_position, int(round(ash)))
	if enemy.is_elite:
		drop_materials(parent, enemy.global_position, 1 + randi() % 2 + int(Run.stat(&"drop_mats")), depth)


## Ash is dropped as a few pickups, so it pops out in a little burst.
static func drop_ash(parent: Node, pos: Vector2, total: int) -> void:
	if total <= 0:
		return
	var pieces := clampi(total / 6 + 1, 1, 8)
	var each := maxi(1, total / pieces)
	var remaining := total
	for i in pieces:
		var share := each if i < pieces - 1 else remaining
		remaining -= share
		Pickup.spawn(parent, pos, Pickup.Kind.ASH, maxi(share, 1))


## `count` materials of the floor's tier (with a small chance of a better tier).
static func drop_materials(parent: Node, pos: Vector2, count: int, depth: int, tier_override: int = 0) -> void:
	for i in count:
		var tier := tier_override if tier_override > 0 else RunData.tier_for_floor(depth)
		if tier_override == 0 and tier < 3 and randf() < 0.12:
			tier += 1
		var options := RunData.materials_of_tier(tier)
		Pickup.spawn(parent, pos, Pickup.Kind.MATERIAL, 1, options[randi() % options.size()])


## A boss: lots of ash, several materials, and its blueprint the first time.
static func boss_died(parent: Node, pos: Vector2, boss_kind: StringName, depth: int) -> void:
	drop_ash(parent, pos, int(round(float(ASH_BY_ENEMY.get(String(boss_kind), 80)) * floor_scale(depth))))
	drop_materials(parent, pos, 4 + int(Run.stat(&"drop_mats")), depth)
	var blueprint: StringName = RunData.BOSS_BLUEPRINT.get(boss_kind, &"")
	if blueprint != &"" and not Run.bosses_beaten.has(boss_kind):
		Run.bosses_beaten[boss_kind] = true
		Pickup.spawn(parent, pos + Vector2(0, 8), Pickup.Kind.BLUEPRINT, 1, blueprint)
	Run.save_profile()
