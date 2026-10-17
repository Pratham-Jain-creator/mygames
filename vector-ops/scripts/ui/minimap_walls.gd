extends Control
## Draws the arena's solid blocks on the radar. Fed by Minimap each frame.

const WALL_COLOR := Color(0.35, 0.45, 0.55, 0.55)

var _origin: Vector2 = Vector2.ZERO
var _yaw: float = 0.0
var _k: float = 1.0
var _rotate: bool = false


func set_view(origin: Vector3, yaw: float, k: float, rotate_map: bool) -> void:
	_origin = Vector2(origin.x, origin.z)
	_yaw = yaw
	_k = k
	_rotate = rotate_map
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	for r in MapBuilder.rects:
		var ctr: Vector2 = r[0]
		var sz: Vector2 = r[1]
		var pts := PackedVector2Array()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var d: Vector2 = ctr + corner * sz * 0.5 - _origin
			if _rotate:
				d = d.rotated(_yaw)
			pts.append(c + d * _k)
		draw_colored_polygon(pts, WALL_COLOR)
