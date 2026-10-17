class_name WeaponState
extends RefCounted
## The currently equipped Breach Protocol.
## strength = Base Strength (never decreases); ceiling = Target Ceiling.

const UNLIMITED := 99

var node: NodeData
var strength: int = 0
var ceiling: int = UNLIMITED
var duct_ready := true
var hardened := 0        # Hardened Core: ceiling gained from Perfect Blocks (max 3)
var first_bonus := 0     # Spare Plating: ceiling saved on the first hit


func _init(p_node: NodeData, p_strength: int) -> void:
	node = p_node
	strength = p_strength


func ceiling_text() -> String:
	return "INF" if ceiling >= 90 else str(ceiling)
