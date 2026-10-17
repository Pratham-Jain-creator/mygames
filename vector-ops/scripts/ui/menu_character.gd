class_name MenuCharacter
extends PlayerModel
## The operator on the start screen (scenes/ui/menu_character.tscn).
## The head follows the cursor (code, because it is continuous); every pose that
## reacts to a choice - presenting a module, flexing for a preset, the greeting -
## is an animation of the scene's own Reactions AnimationPlayer.

@onready var _reactions: AnimationPlayer = $Reactions


## v = cursor offset from the centre of the preview box, -1..1 on both axes (screen y grows downward).
func look_at_cursor(v: Vector2, delta: float) -> void:
	v = v.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
	set_head_look(-v.y * 0.35, v.x * 0.8, delta)


## A module was picked for `hand` (0 = right). Weapons are aimed, everything else is presented.
func react_to_module(hand: int, category: String) -> void:
	var kind: String = "aim" if category == "WEAPON" else "show"
	_reactions.play("%s_%s" % [kind, "r" if hand == 0 else "l"])


## A whole preset / saved build was applied.
func react_to_loadout() -> void:
	_reactions.play("flex")
