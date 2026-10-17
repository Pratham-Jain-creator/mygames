class_name LedHealthBar
extends Control
## Rig Health as discrete physical LED blocks that shatter / light up.

const LED_SCENE := preload("res://scenes/components/led_block/led_block.tscn")

var _blocks: Array[LedBlock] = []

@onready var _grid: GridContainer = %Grid


func set_health(current: int, maximum: int, animate := true) -> void:
	if _blocks.size() != maximum:
		_rebuild(maximum)
		animate = false
	current = clampi(current, 0, maximum)
	for i in _blocks.size():
		var on := i < current
		if animate:
			if on:
				_blocks[i].light_up()
			else:
				_blocks[i].shatter()
		else:
			_blocks[i].snap(on)


func _rebuild(maximum: int) -> void:
	for b in _blocks:
		if is_instance_valid(b):
			b.get_parent().remove_child(b)
			b.queue_free()
	_blocks.clear()
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for i in maximum:
		var b: LedBlock = LED_SCENE.instantiate()
		_grid.add_child(b)
		_blocks.append(b)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
