extends Control
## Plays TutorialScript on top of the real Server screen. The bot panel explains,
## a pulsing frame spotlights the control to use, and every other control is
## blocked (the screen asks `allows()` before acting and reports via `notify()`).
## All motion lives in the scene's AnimationPlayers; this script only plays names.

const SCRIPT_DATA := preload("res://scripts/data/tutorial_script.gd")
const NUDGE_TEXTS := [
	"Not that one! Use the highlighted control.",
	"Follow the highlight, operator.",
	"Nice try. The glowing control is the one.",
]

var screen: Control              # the ServerScreen (duck typed: avoids a scene cycle)
var steps: Array = []
var idx := -1
var step: Dictionary = {}
var expect := "next"
var running := false

var _target: Control = null
var _nudge_i := 0

## Focus layer: dims everything except the bot panel (reading steps) or the bot panel
## plus the control to use (action steps). Built in code, drawn by tutorial_dim.gdshader.
const DIM_SHADER := preload("res://shaders/tutorial_dim.gdshader")
const DIM_ALPHA := 0.88
const SPOT_PAD := 8.0
var _dim: ColorRect
var _dim_mat: ShaderMaterial
var _dim_now := 0.0
var _dim_goal := 0.0
var _holes_now: Array = [Rect2(), Rect2(), Rect2()]

@onready var _panel: PanelContainer = %BotPanel
@onready var _text: RichTextLabel = %Text
@onready var _step_label: Label = %StepLabel
@onready var _next: ActionButton = %NextButton
@onready var _exit: ActionButton = %ExitButton
@onready var _spot: Panel = %Spot
@onready var _bot_anim: AnimationPlayer = $BotAnimator
@onready var _panel_anim: AnimationPlayer = $PanelAnimator


func _ready() -> void:
	z_index = 50   # overlays always draw above raised (selected / hovered) Node cards
	steps = SCRIPT_DATA.steps()
	_next.activated.connect(func(_s): _on_next())
	_exit.activated.connect(func(_s): finish(false))
	_panel_anim.animation_finished.connect(_on_panel_anim_finished)
	_next.set_tip("NEXT", "Continue. You can also press Space or Enter.")
	_exit.set_tip("EXIT TUTORIAL", "Leave the tutorial and return to the main menu.")
	_panel.visible = false
	_spot.visible = false
	_dim = ColorRect.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = DIM_SHADER
	_dim.material = _dim_mat
	_dim.color = Color.WHITE
	add_child(_dim)
	move_child(_dim, 0)   # under the spotlight frame and the bot panel
	_dim_mat.set_shader_parameter("dim", 0.0)


func setup(p_screen: Control) -> void:
	screen = p_screen


func start() -> void:
	running = true
	idx = -1
	_advance()


# ------------------------------------------------------------------ flow
func _advance() -> void:
	idx += 1
	if idx >= steps.size():
		finish(true)
		return
	_begin_step()


func _begin_step() -> void:
	step = steps[idx]
	expect = String(step.get("expect", "next"))
	match String(step.get("do", "")):
		"deal":
			screen.tut_deal()
		"level_skirmish":
			RunState.level_up_sub("skirmish")
			screen.tut_refresh_subs("skirmish")
	_target = _find_target()
	var hide_panel: bool = bool(step.get("hide", false))
	_panel.visible = not hide_panel
	# NEXT never moves or disappears (misclicks); it is just greyed out on "your move" steps.
	_next.visible = true
	_next.disabled = expect != "next"
	# No tooltip while greyed out; the real tip only appears when NEXT is usable.
	if expect == "next":
		_next.set_tip("NEXT", "Continue. You can also press Space or Enter.")
	else:
		_next.set_tip("", "")
	_step_label.text = "STEP %d / %d%s" % [idx + 1, steps.size(), "   |   YOUR MOVE" if expect != "next" else ""]
	var sv: ServerState = RunState.server
	var body := String(step.get("text", "")).format({
		"score": Fmt.big(sv.score) if sv != null else "0",
		"quota": Fmt.big(sv.quota) if sv != null else "0",
		"health": str(RunState.health),
	})
	_text.text = Fmt.rich(body)
	_text.visible_ratio = 0.0
	if not hide_panel:
		_panel.reset_size()
		_panel_anim.play(&"panel_in")
		var secs := clampf(body.length() * 0.011, 0.5, 2.6)
		_panel_anim.queue(&"type")
		_panel_anim.speed_scale = 1.0
		_type_secs = secs
		_bot_anim.play(&"talk")
		AudioService.play("tick", 1.2)
	_update_spot()


var _type_secs := 1.0


func _on_panel_anim_finished(anim_name: StringName) -> void:
	if anim_name == &"type":
		_bot_anim.play(&"idle")


func _process(_dt: float) -> void:
	if not running:
		return
	# Typewriter speed: the "type" animation is 1s long, scaled to the text length.
	if _panel_anim.current_animation == "type":
		_panel_anim.speed_scale = 1.0 / _type_secs
	elif _panel_anim.speed_scale != 1.0:
		_panel_anim.speed_scale = 1.0
	if _panel.visible:
		_place_panel()
	_update_spot()
	_update_dim(_dt)


func _find_target() -> Control:
	var key := String(step.get("target", "none"))
	if key == "none" or key == "":
		return null
	if key == "card":
		var spec: Array = step.get("card", [])
		if spec.size() == 2:
			return screen.tut_card(int(spec[0]), int(spec[1]))
		return null
	return screen.tut_target(key)


func _update_spot() -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		_spot.visible = false
		return
	var r := _target.get_global_rect()
	_spot.visible = true
	_spot.global_position = r.position - Vector2(6, 6)
	_spot.size = r.size + Vector2(12, 12)


## Which rectangles stay bright this step. Empty = no dimming at all.
func _focus_rects() -> Array:
	var rects: Array = []
	var hide_panel: bool = bool(step.get("hide", false))
	# Watching an animation, or using an overlay window (tracker / subroutines): no dimming.
	if hide_panel or expect == "turn_done" or expect == "deck_close" or expect == "subs_close":
		return rects
	if _panel.visible:
		rects.append(_panel.get_global_rect().grow(SPOT_PAD))
	# The thing the bot is pointing at is always lit too (reading steps and action steps).
	# A step can also keep a whole area lit (`lit`), e.g. the entire room so the player sees
	# every Node they are choosing among; the pulsing frame still marks the one to click.
	var lit: Control = screen.tut_target(String(step.get("lit", ""))) if step.has("lit") else null
	if lit != null and is_instance_valid(lit) and lit.is_visible_in_tree():
		rects.append(lit.get_global_rect().grow(SPOT_PAD))
	elif _target != null and is_instance_valid(_target) and _target.is_visible_in_tree():
		rects.append(_target.get_global_rect().grow(SPOT_PAD))
	# Keep the "not that one!" toast readable.
	var t: Node = screen.get("toast") if screen != null else null
	var tp: Control = t.get_node_or_null("Panel") as Control if t != null else null
	if tp != null and tp.modulate.a > 0.05:
		rects.append(tp.get_global_rect().grow(SPOT_PAD))
	return rects


func _update_dim(dt: float) -> void:
	var goal := _focus_rects()
	_dim_goal = DIM_ALPHA if not goal.is_empty() else 0.0
	_dim_now = move_toward(_dim_now, _dim_goal, dt * 3.5)
	var k := clampf(dt * 16.0, 0.0, 1.0)
	for i in 3:
		var want := Rect2()
		if i < goal.size():
			want = goal[i]
		var cur: Rect2 = _holes_now[i]
		if want.size.x <= 0.0:
			cur = Rect2()
		elif cur.size.x <= 0.0:
			cur = want
		else:
			cur = Rect2(cur.position.lerp(want.position, k), cur.size.lerp(want.size, k))
		_holes_now[i] = cur
		_dim_mat.set_shader_parameter("hole%d" % i, Vector4(cur.position.x, cur.position.y, cur.size.x, cur.size.y))
	_dim_mat.set_shader_parameter("dim", _dim_now)
	_dim_mat.set_shader_parameter("area_size", _dim.size)


func _place_panel() -> void:
	var vp := get_viewport_rect().size
	_panel.pivot_offset = _panel.size * 0.5
	var dock := String(step.get("dock", ""))
	if dock == "":
		var low := _target != null and is_instance_valid(_target) and _target.get_global_rect().get_center().y < 300.0
		dock = "bottom" if (low or _target == null) else "top"
	var y := 8.0 if dock == "top" else vp.y - _panel.size.y - 8.0
	_panel.position = Vector2((vp.x - _panel.size.x) * 0.5, y)


# ---------------------------------------------------------- player input
func _on_next() -> void:
	if expect == "next":
		AudioService.play("click")
		_advance()


## Called first by the screen for key presses. Space / Enter act as NEXT.
func handle_key(event: InputEvent) -> bool:
	if not running:
		return false
	if expect == "next" and (event.is_action_pressed("execute_turn") or event.is_action_pressed("ui_accept")):
		_on_next()
		get_viewport().set_input_as_handled()
		return true
	return false


## The screen asks before performing an action. Returns false (and scolds) when the
## current step is not waiting for exactly this.
func allows(action: StringName, arg: Variant = null) -> bool:
	if not running:
		return true
	if String(action) == expect:
		if action == &"card":
			if arg != null and _card_matches(arg):
				return true
		else:
			return true
	nudge()
	return false


func _card_matches(card: Variant) -> bool:
	var spec: Array = step.get("card", [])
	if spec.size() != 2 or card.data == null:
		return false
	return card.data.type == int(spec[0]) and card.data.base_value == int(spec[1])


func nudge() -> void:
	_panel_anim.play(&"nudge")
	AudioService.play("deny")
	if expect == "next":
		screen.show_toast("Press NEXT to continue", Enums.COL_DAEMON)
	else:
		screen.show_toast(NUDGE_TEXTS[_nudge_i % NUDGE_TEXTS.size()], Enums.COL_DAEMON)
		_nudge_i += 1


## The screen reports that an allowed action happened.
func notify(action: StringName, _arg: Variant = null) -> void:
	if not running:
		return
	if String(action) == expect:
		_advance()


func finish(completed: bool) -> void:
	running = false
	if completed:
		MetaSave.set_value("tutorial", "done", true)
	RunState.tutorial = false
	RunState.active = false
	SceneManager.go(SceneManager.MAIN_MENU)
