extends StaticBody2D
## Iron portcullis that seals a doorway while a gauntlet is running. The collision is only
## active while the gate is closed, and the bars drop in / rise with a short animation.

const SFX_CLOSE := preload("res://assets/sounds/tap.wav")
const BAR_DARK := Color(0.24, 0.24, 0.30)
const BAR_LIGHT := Color(0.62, 0.62, 0.72)
const BAR_SPACING: float = 8.0
const MOVE_TIME: float = 0.45

## Size of the doorway being sealed, in pixels (96x16 for top/bottom doors, 16x64 for side doors).
@export var size_px: Vector2 = Vector2(96, 16)

var closed: bool = false
var _progress: float = 0.0 # 0 = bars raised (open), 1 = bars down (closed)

@onready var shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("gate")
	collision_layer = 1
	collision_mask = 0
	z_index = 3
	var rect := RectangleShape2D.new()
	rect.size = size_px
	shape.shape = rect
	shape.disabled = true


func close() -> void:
	if closed:
		return
	closed = true
	shape.set_deferred("disabled", false)
	Audio.play_2d(SFX_CLOSE, global_position, 0.0, 0.5)
	_animate_to(1.0)


func open() -> void:
	if not closed:
		return
	closed = false
	Audio.play_2d(SFX_CLOSE, global_position, -2.0, 0.9)
	_animate_to(0.0)
	await get_tree().create_timer(MOVE_TIME).timeout
	if not closed:
		shape.set_deferred("disabled", true)


func _animate_to(target: float) -> void:
	create_tween().tween_method(_set_progress, _progress, target, MOVE_TIME).set_trans(Tween.TRANS_BOUNCE if target > 0.5 else Tween.TRANS_SINE)


func _set_progress(value: float) -> void:
	_progress = value
	queue_redraw()


func _draw() -> void:
	if _progress <= 0.01:
		return
	var half := size_px * 0.5
	if size_px.x >= size_px.y:
		# Horizontal doorway: vertical bars dropping from the top edge.
		var x := -half.x + BAR_SPACING * 0.5
		while x < half.x:
			draw_rect(Rect2(x - 1.5, -half.y, 3.0, size_px.y * _progress), BAR_DARK)
			draw_rect(Rect2(x - 0.5, -half.y, 1.0, size_px.y * _progress), BAR_LIGHT)
			x += BAR_SPACING
		draw_rect(Rect2(-half.x, -2.0, size_px.x * _progress, 4.0), BAR_DARK)
	else:
		# Vertical doorway: horizontal bars sliding in from the left edge.
		var y := -half.y + BAR_SPACING * 0.5
		while y < half.y:
			draw_rect(Rect2(-half.x, y - 1.5, size_px.x * _progress, 3.0), BAR_DARK)
			draw_rect(Rect2(-half.x, y - 0.5, size_px.x * _progress, 1.0), BAR_LIGHT)
			y += BAR_SPACING
		draw_rect(Rect2(-2.0, -half.y, 4.0, size_px.y * _progress), BAR_DARK)
