class_name InteractiveControl
extends Control
## Base class of every hoverable / clickable widget (cards, buttons, shop rows...).
##
## Behaviour (shared so every widget feels identical on PC and Android):
##  * hover  -> tooltip with the description (PC only)
##  * click / tap -> `activated`
##  * long-press (touch, or hold the mouse) -> tooltip, selection is suppressed
##
## Visuals are NEVER tweened from code. Subclass scenes own an AnimationPlayer with
## conventionally named animations; this class only *plays* them by name:
##   hover_in, hover_out, press, release, disabled, enabled
## A child Control named "Visual" is what those animations move/scale, so the
## widget's layout rectangle (inside Containers) is never disturbed.

signal activated(source: InteractiveControl)
signal hover_changed(source: InteractiveControl, hovered: bool)
signal long_pressed(source: InteractiveControl)

const LONG_PRESS_SEC := 0.4

var is_hovered := false
var is_pressed := false
var disabled := false:
	set(v):
		if disabled == v:
			return
		disabled = v
		if is_inside_tree():
			play_anim(&"disabled" if v else &"enabled")
var anim: AnimationPlayer
var visual: Control

var _press_timer: Timer
var _long_fired := false

## Card surface effect: a soft gloss sweep, shown only when `glossy`. See shaders/idle_sheen.gdshader.
const IDLE_SHADER := preload("res://shaders/idle_sheen.gdshader")
var _idle_rect: ColorRect
var _idle_on := false
var _idle_tint := Color.WHITE
var _idle_strength := 1.0
var _idle_gloss := false


static func is_touch_ui() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
	visual = get_node_or_null("Visual") as Control
	_press_timer = Timer.new()
	_press_timer.one_shot = true
	_press_timer.wait_time = LONG_PRESS_SEC
	_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_press_timer)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_update_pivot)
	if visual:
		visual.resized.connect(_update_pivot)
	_update_pivot()
	if disabled:
		play_anim(&"disabled")
	if _idle_on:
		_apply_idle()


func _exit_tree() -> void:
	if is_hovered or is_pressed:
		var tip := get_node_or_null("/root/TooltipService")
		if tip:
			tip.hide_for(self)


## Override: return {title, body, color} to show a tooltip, or {} for none.
func get_tip_data() -> Dictionary:
	return {}


## Override hooks ------------------------------------------------------------
func _on_activated() -> void:
	pass


func _on_denied() -> void:
	pass


func _hover_animation(hovered: bool) -> void:
	play_anim(&"hover_in" if hovered else &"hover_out")


# ---------------------------------------------------------------------------
func play_anim(anim_name: StringName) -> void:
	if anim != null and anim.has_animation(anim_name):
		anim.play(anim_name)


func reset_visual() -> void:
	if anim != null and anim.has_animation(&"RESET"):
		anim.play(&"RESET")
		anim.seek(0.0, true)
		anim.stop()


func _update_pivot() -> void:
	if visual:
		visual.pivot_offset = visual.size * 0.5


## Mouse-over descriptions are OFF everywhere; press-and-hold still shows them.
## Set to true on a control (or change this default) to bring hover tooltips back.
var hover_tooltip := false


func _on_mouse_entered() -> void:
	is_hovered = true
	hover_changed.emit(self, true)
	if is_touch_ui():
		return
	if not disabled:
		_hover_animation(true)
	if hover_tooltip:
		_show_tooltip()


func _on_mouse_exited() -> void:
	is_hovered = false
	hover_changed.emit(self, false)
	if is_touch_ui():
		return
	if not disabled and not is_pressed:
		_hover_animation(false)
	TooltipService.hide_for(self)


func _show_tooltip() -> void:
	var data := get_tip_data()
	if not data.is_empty():
		TooltipService.show_for(self, data)


func _on_long_press_timeout() -> void:
	if is_pressed:
		_long_fired = true
		_show_tooltip()
		long_pressed.emit(self)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		is_pressed = true
		_long_fired = false
		_press_timer.start()
		if not disabled:
			play_anim(&"press")
		accept_event()
		return
	if not is_pressed:
		return
	is_pressed = false
	_press_timer.stop()
	accept_event()
	if _long_fired:
		TooltipService.hide_for(self)
		_play_release()
		return
	if disabled:
		AudioService.play("deny")
		_on_denied()
		return
	_play_release()
	if Rect2(Vector2.ZERO, size).has_point(mb.position):
		AudioService.play("click")
		activated.emit(self)
		_on_activated()


func _play_release() -> void:
	if anim == null or disabled:
		return
	if anim.has_animation(&"release"):
		anim.play(&"release")
		if is_hovered and not is_touch_ui() and anim.has_animation(&"hover_in"):
			anim.queue(&"hover_in")
	else:
		_hover_animation(is_hovered and not is_touch_ui())


# ---------------------------------------------------------------- idle effect
## Turns the card surface effect on / off (scanlines; `glossy` adds the light sweep).
## Safe to call before the node is ready.
func set_idle(on: bool, tint := Color.WHITE, strength := 1.0, glossy := false) -> void:
	_idle_on = on
	_idle_gloss = glossy
	_idle_tint = tint
	_idle_strength = strength
	if is_node_ready():
		_apply_idle()


func _apply_idle() -> void:
	# Only glossy (modified) cards get the effect; everything else stays clean.
	if not _idle_on or not _idle_gloss:
		if _idle_rect != null:
			_idle_rect.visible = false
		return
	if _idle_rect == null:
		_idle_rect = ColorRect.new()
		_idle_rect.color = Color.WHITE
		_idle_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_idle_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var m := ShaderMaterial.new()
		m.shader = IDLE_SHADER
		m.set_shader_parameter("phase", randf() * 30.0)
		m.set_shader_parameter("period", randf_range(5.5, 8.0))
		_idle_rect.material = m
		var host: Control = visual if visual != null else self
		host.add_child(_idle_rect)
		_idle_rect.resized.connect(_sync_idle_size)
		_sync_idle_size.call_deferred()
	_idle_rect.visible = true
	var mat := _idle_rect.material as ShaderMaterial
	mat.set_shader_parameter("tint", _idle_tint)
	mat.set_shader_parameter("strength", _idle_strength)
	mat.set_shader_parameter("gloss", 1.0 if _idle_gloss else 0.0)


func _sync_idle_size() -> void:
	if _idle_rect != null:
		(_idle_rect.material as ShaderMaterial).set_shader_parameter("rect_size", _idle_rect.size)
