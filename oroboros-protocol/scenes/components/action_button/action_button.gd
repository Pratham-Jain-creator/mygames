class_name ActionButton
extends InteractiveControl
## Heavy mechanical-keyboard style button used across every screen.

@export var text := "BUTTON":
	set(v):
		text = v
		if is_node_ready():
			_label.text = v
			_fit_label()
@export var accent := Color("66FCF1"):
	set(v):
		accent = v
		if is_node_ready():
			_bar.color = v
			if not skinned:
				return
			_skin_name = skin_for(v)
			_set_state("inactive" if disabled else "active")
## Uses the PNG skin from assets/buttons. Off by default: only the buttons the art was drawn for turn it on.
@export var skinned := false
@export var tip_title := ""
@export_multiline var tip_body := ""

@onready var _label: Label = %Label
@onready var _bar: ColorRect = %Bar

const SKIN_DIR := "res://assets/buttons/"
var _skin: NinePatchRect
var _skin_name := "cyan"
var _small := true
var _skin_cache := {}


## Maps the accent colour to the nearest button skin (cyan, amber, magenta, steel).
static func skin_for(c: Color) -> String:
	var opts := {
		"cyan": Color("66FCF1"), "amber": Color("FFB400"), "magenta": Color("FF00FF"), "steel": Color("5C6670"),
		"red": Color("FF003C"), "green": Color("00FA9A")}
	var best := "cyan"
	var bd := 99.0
	for k in opts:
		var o: Color = opts[k]
		var d := absf(o.r - c.r) + absf(o.g - c.g) + absf(o.b - c.b)
		if d < bd:
			bd = d
			best = k
	if best == "red":
		return "magenta"
	if best == "green":
		return "cyan"
	return best


func _tex(state: String) -> Texture2D:
	var kind := "small" if _small else "action"
	var path := SKIN_DIR + "btn_%s_inactive.png" % kind if state == "inactive" else SKIN_DIR + "btn_%s_%s_%s.png" % [kind, _skin_name, state]
	if not _skin_cache.has(path):
		_skin_cache[path] = load(path)
	return _skin_cache[path]


func _set_state(state: String) -> void:
	if not skinned:
		return
	if _skin != null:
		_skin.texture = _tex(state)
		_layout_skin()


func play_anim(anim_name: StringName) -> void:
	super(anim_name)
	if not skinned:
		return
	match anim_name:
		&"hover_in": _set_state("hover")
		&"press": _set_state("pressed")
		&"hover_out", &"release", &"enabled", &"RESET": _set_state("active")
		&"disabled": _set_state("inactive")


func _ready() -> void:
	super()
	_label.text = text
	_bar.color = accent
	if not skinned:
		return
	_small = custom_minimum_size.y < 56.0
	_skin = NinePatchRect.new()
	_skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skin.patch_margin_left = 70 if not _small else 60
	_skin.patch_margin_right = _skin.patch_margin_left
	_skin.patch_margin_top = 60 if not _small else 50
	_skin.patch_margin_bottom = _skin.patch_margin_top
	var vis := get_node("Visual")
	vis.add_child(_skin)
	vis.move_child(_skin, 0)
	vis.get_node("Face").visible = false
	_bar.visible = false
	_skin_name = skin_for(accent)
	_set_state("inactive" if disabled else "active")
	vis.resized.connect(_layout_skin)
	vis.resized.connect(_fit_label)
	_layout_skin()
	_label.offset_left = PAD
	_label.offset_right = -PAD
	_fit_label.call_deferred()


const PAD := 28.0


## Keeps the text inside the frame: the font shrinks until the text fits between the padded corners.
func _fit_label() -> void:
	if not skinned or _skin == null:
		return
	var avail := maxf(10.0, size.x - PAD * 2.0)
	var fs := 20
	var font := _label.get_theme_font("font")
	while fs > 12 and font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		fs -= 1
	_label.add_theme_font_size_override("font_size", fs)


## The skin is scaled to the button height so its corners keep their proportions;
## only the flat middle stretches with the width.
func _layout_skin() -> void:
	if _skin == null or _skin.texture == null:
		return
	var src := _skin.texture.get_size()
	var host: Control = _skin.get_parent()
	var k := maxf(0.01, host.size.y / src.y)
	_skin.scale = Vector2(k, k)
	_skin.size = Vector2(host.size.x / k, src.y)
	_skin.position = Vector2.ZERO


func set_tip(title: String, body: String) -> void:
	tip_title = title
	tip_body = body


func get_tip_data() -> Dictionary:
	if tip_title == "" and tip_body == "":
		return {}
	return {"title": tip_title, "body": tip_body, "color": accent}
