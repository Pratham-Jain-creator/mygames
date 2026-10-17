class_name LedBlock
extends Control
## One of the physical LED indicators of the Rig Health bar.

var is_on := true

@onready var _lit: ColorRect = %Lit
@onready var _anim: AnimationPlayer = $AnimationPlayer


func set_color(c: Color) -> void:
	_lit.color = c


## Snap to a state without animation (used when rebuilding the bar).
func snap(on: bool) -> void:
	is_on = on
	_anim.play(&"on" if on else &"dim")
	# Jump to the last frame and let the animation finish there. (stop() would reset to the
	# FIRST frame, which is the opposite look: dim for "on", lit for "dim".)
	_anim.seek(_anim.current_animation_length, true)
	_anim.stop(true)


func light_up() -> void:
	if is_on:
		return
	is_on = true
	_anim.play(&"on")


func shatter() -> void:
	if not is_on:
		return
	is_on = false
	_anim.play(&"shatter")
