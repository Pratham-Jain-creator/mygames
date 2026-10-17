extends Node2D
## One radar pin (scenes/ui/minimap_blip.tscn): a dot plus a heading tick.

const FRIEND := Color(0.3, 0.6, 1.0)
const ENEMY := Color(1.0, 0.3, 0.2)

@onready var _dot: Polygon2D = $Dot
@onready var _heading: Polygon2D = $Heading


func set_team(friendly: bool) -> void:
	var c: Color = FRIEND if friendly else ENEMY
	_dot.color = c
	_heading.color = c


## Screen-space heading in radians (0 = pointing up).
func set_heading(rad: float) -> void:
	_heading.rotation = rad


## Pinned to the rim: the player is beyond radar range, so show bearing only.
func set_edge(on: bool) -> void:
	_heading.visible = not on
	modulate.a = 0.7 if on else 1.0
