class_name RoomKit
extends RefCounted
## Small helpers every special room uses, so the room scripts only describe what is special about them.

const GATE_COLOR := Color(1, 1, 1)


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func game() -> Game:
	return tree().get_first_node_in_group("game") as Game


static func player() -> CharacterBody2D:
	return GameManager.player


static func menu() -> ChoiceMenu:
	return GameManager.choice_menu


static func center(room: WFCRoom) -> Vector2:
	return room.get_global_bounds().get_center()


## A free floor position near the room's centre plus an offset.
static func spot(room: WFCRoom, offset: Vector2 = Vector2.ZERO) -> Vector2:
	return room.nearest_free_point(center(room) + offset, 1)


static func spawned(room: WFCRoom) -> Node:
	return room.get_node("Spawned")


static func altar(room: WFCRoom, style: StringName, prompt: String, color: Color, callback: Callable, offset: Vector2 = Vector2.ZERO) -> Altar:
	return Altar.make(spawned(room), spot(room, offset), style, prompt, color, callback)


static func toast(text: String, color: Color = Color.WHITE) -> void:
	GameManager.toast_requested.emit(text, null, color)


static func level_of(room: WFCRoom) -> Level:
	return room.get_parent() as Level


## Shortens the floor's timer (the Smuggler's Exchange sells things for time). False when there is not enough left.
static func spend_time(room: WFCRoom, seconds: float) -> bool:
	var level := level_of(room)
	if level == null or level.time_left <= seconds + 30.0:
		return false
	level.time_left -= seconds
	return true


## Marks a one-use prop as used up.
static func use_up(altar_node: Altar, text: String = "USED") -> void:
	altar_node.enabled = false
	altar_node.disabled_prompt = text
	if altar_node.style == &"chest":
		altar_node.opened = true


## `count` distinct random entries of an array (or fewer when there are fewer).
static func pick_distinct(source: Array, count: int) -> Array:
	var copy := source.duplicate()
	copy.shuffle()
	return copy.slice(0, mini(count, copy.size()))


## Heals the player, repaying blood debt first.
static func heal(amount: int) -> void:
	var p := player()
	if p != null and p.has_method("heal_player"):
		p.heal_player(amount)


## Damages the player without killing them (a cost, not an attack). Returns false when they cannot afford it.
static func pay_health(amount: int) -> bool:
	var p := player()
	if p == null:
		return false
	var health: HealthComponent = p.health_component
	if health.current_health <= amount + 1:
		toast("YOU ARE TOO WEAK FOR THAT", Color(1.0, 0.5, 0.4))
		return false
	health.take_damage(amount)
	GameManager.shake_camera(3.0, 0.2)
	return true


## Tier of materials to drop on this floor, optionally one better.
static func tier(depth: int, bonus: int = 0) -> int:
	return clampi(RunData.tier_for_floor(depth) + bonus, 1, 3)
