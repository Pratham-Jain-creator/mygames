class_name ScoreDisplay
extends Control
## The live equation: [ Base ] x [ Mult ] with the Total in the middle between the two boxes.
## Number tick-up is driven by the AnimationPlayer ("tick" animates `progress`
## from 0 to 1); this script only interpolates between the from / to values.

@export var progress := 1.0:
	set(v):
		progress = v
		if is_node_ready():
			_apply()

var _from_chips := 0.0
var _to_chips := 0.0
var _from_mult := 1.0
var _to_mult := 1.0
var _shown_chips := 0.0
var _shown_mult := 1.0
var _last_step := -1
var _tick_count := 0

@onready var _sub_label: Label = %SubLabel
@onready var _base_label: Label = %BaseLabel
@onready var _mult_label: Label = %MultLabel
@onready var _total_label: Label = %TotalLabel
@onready var _note_label: Label = %NoteLabel
@onready var _anim: AnimationPlayer = $AnimationPlayer


var _pop_player: AnimationPlayer   # own player: the number pop must survive the next set_static()


func _ready() -> void:
	# The pop animation is authored in the scene; a second player runs it so that the
	# main player (tick / pulses / set_static's stop) never cuts it short.
	_pop_player = AnimationPlayer.new()
	add_child(_pop_player)
	var lib := AnimationLibrary.new()
	lib.add_animation(&"pop_total", _anim.get_animation(&"pop_total"))
	_pop_player.add_animation_library(&"", lib)
	set_static(0.0, 1.0, "SELECT 3 NODES")


func _apply() -> void:
	_shown_chips = lerpf(_from_chips, _to_chips, progress)
	_shown_mult = lerpf(_from_mult, _to_mult, progress)
	_base_label.text = str(int(round(_shown_chips)))
	_mult_label.text = _fmt(_shown_mult)
	_total_label.text = _big(int(floor(_shown_chips * maxf(1.0, _shown_mult))))
	var step := int(progress * 8.0)
	if step != _last_step and progress < 1.0:
		_last_step = step
		AudioService.play("tick", minf(2.8, 1.0 + 0.05 * _tick_count))


func _fmt(v: float) -> String:
	var s := "%.1f" % v
	return s.trim_suffix(".0")


func _big(v: int) -> String:
	var s := str(v)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


## Instantly show a state (selection preview).
func set_static(chips: float, mult: float, sub_name := "", note := "") -> void:
	_anim.stop()
	_from_chips = chips
	_to_chips = chips
	_from_mult = mult
	_to_mult = mult
	_last_step = -1
	progress = 1.0
	_apply()
	_sub_label.text = sub_name
	if note != "":
		_note_label.text = note


func begin_cascade(sub_name: String) -> void:
	_tick_count = 0
	_sub_label.text = sub_name


## Slot-machine style tick up to new base / mult values.
func animate_to(chips: float, mult: float, note := "", pulse_base := false, pulse_mult := false) -> void:
	_tick_count += 1
	_from_chips = _shown_chips
	_from_mult = _shown_mult
	_to_chips = chips
	_to_mult = mult
	_last_step = -1
	if note != "":
		_note_label.text = note
	progress = 0.0
	_anim.play(&"tick")
	if pulse_mult:
		_anim.queue(&"pulse_mult")
	elif pulse_base:
		_anim.queue(&"pulse_base")
	await _anim.animation_finished


## Only the multiplier changed (e.g. unmitigated damage). Shows a pulse.
func bump_mult(mult: float) -> void:
	_from_chips = _shown_chips
	_to_chips = _shown_chips
	_from_mult = _shown_mult
	_to_mult = mult
	progress = 1.0
	_apply()
	_anim.play(&"pulse_mult")


## Turn total: sound only now (the floating +N effect shows the number).
func pop_total() -> void:
	# The white total between the boxes is no longer shown; the floating +N effect carries it.
	AudioService.play("slam")
