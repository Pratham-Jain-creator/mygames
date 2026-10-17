@tool
extends Marker2D
class_name RoomSlot

## A spot in a room that the AI director can fill with something.
## Rooms never contain role-specific logic; they only advertise slots.

enum Kind { ENEMY, LOOT, SHRINE, OBJECTIVE, HAZARD, DECOR, EFFECT }
enum Placement { GROUND, ELEVATED, AIR }
## Biggest thing that fits here.
## SMALL ~1x2 tiles (grunt, prop), MEDIUM ~3x3 (elite, chest, shrine), LARGE ~6x6+ (mini-boss, portal).
enum Footprint { SMALL, MEDIUM, LARGE }

# Editor gizmo colours, in Kind order.
const KIND_COLORS = [
	Color.RED, Color.GOLD, Color.CYAN, Color.MAGENTA,
	Color.ORANGE, Color.GRAY, Color.LIGHT_GREEN,
]

@export var kind: Kind = Kind.ENEMY:
	set(value):
		kind = value
		queue_redraw()
@export var placement: Placement = Placement.GROUND
@export var footprint: Footprint = Footprint.SMALL
## Optional filters, e.g. &"ranged_ok", &"boss", &"near_door".
@export var tags: Array[StringName] = []
## Raise for prime spots, lower for filler spots.
@export var weight: float = 1.0

## Set by the director once something has been spawned here.
var used: bool = false


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_circle(Vector2.ZERO, 5.0, KIND_COLORS[kind])
