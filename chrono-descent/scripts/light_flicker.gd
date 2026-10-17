class_name LightFlicker
extends PointLight2D
## Gentle flame flicker for torches and candles.
## Wobbles energy and size around the values set in the editor, and follows the
## fog-of-war fade of its parent (Terrain) so lights of unvisited rooms stay dark.

@export var flicker_amount: float = 0.2
@export var flicker_speed: float = 7.0
@export var scale_wobble: float = 0.06
## When true the light dims/brightens together with the parent's modulate alpha.
@export var follow_parent_fade: bool = true

var _base_energy: float = 1.0
var _base_scale: float = 1.0
var _t: float = 0.0


func _ready() -> void:
	_base_energy = energy
	_base_scale = texture_scale
	_t = randf() * 100.0


func _process(delta: float) -> void:
	_t += delta * flicker_speed
	var n := sin(_t) * 0.5 + sin(_t * 2.31 + 1.7) * 0.3 + sin(_t * 5.17 + 0.4) * 0.2
	var fade := 1.0
	if follow_parent_fade:
		var p := get_parent() as CanvasItem
		if p:
			fade = p.modulate.a
	energy = _base_energy * (1.0 + n * flicker_amount) * fade
	texture_scale = _base_scale * (1.0 + n * scale_wobble)
	visible = fade > 0.01
