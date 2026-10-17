extends Control
## The boss bar and the cinematic dressing of a boss fight. It is a full-screen overlay that the HUD adds; it
## listens to nothing itself, the HUD forwards GameManager's boss signals to the four public functions:
##   show_boss(title, subtitle, color)       the entrance: letterbox bars, vignette, flash, the bar slides in
##   set_health(current, maximum, pieces)    the shared health pool (a trailing "ghost" shows what was just lost)
##   announce(text)                          a line of big text ("THE QUEEN SPLITS!")
##   hide_boss(defeated)                     victory (flash, "DEFEATED") or the fight being called off
## Everything is built in code, so a new boss only needs a title, a subtitle and a colour.

const FONT: Font = preload("res://assets/sprites/dungeon_set/pixel_bars_free/addons/pixel_bars/font/pixel_ui_font.fnt")
## Portraits shown on the bar, by boss title: [sheet, region of the sheet]. Loaded when needed, so a sheet that
## has not been imported yet only means no portrait.
const PORTRAITS: Dictionary = {
	"SLIME QUEEN": ["res://assets/sprites/enemies/boss/slime_queen_boss.png", Rect2(24, 28, 80, 84)],
	"ANCIENT GOLEM": ["res://assets/sprites/enemies/boss/boss_golem_spritesheet.png", Rect2(24, 44, 112, 116)],
}
const BAR_WIDTH: float = 460.0
const BAR_HEIGHT: float = 16.0
const PANEL_HEIGHT: float = 74.0
const LETTERBOX: float = 54.0
## How long the letterbox bars stay during the entrance (the player is held still for the same time).
const ENTRANCE_HOLD: float = 1.5
const GOLD := Color(0.95, 0.8, 0.42)

var _accent: Color = Color(0.78, 0.45, 1.0)
var _ratio: float = 1.0
var _active: bool = false

var _vignette: TextureRect
var _letter_top: ColorRect
var _letter_bottom: ColorRect
var _flash: ColorRect
var _panel: Control
var _back: ColorRect
var _ghost: ColorRect
var _fill: ColorRect
var _shine: ColorRect
var _portrait: TextureRect
var _name_label: Label
var _sub_label: Label
var _pieces_label: Label
var _announce_label: Label
var _ghost_tween: Tween
var _fill_tween: Tween
var _entrance_tween: Tween
var _announce_tween: Tween
var _letter_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


# ------------------------------------------------------------------ public API

func show_boss(title: String, subtitle: String, color: Color) -> void:
	_accent = color
	_active = true
	visible = true
	_name_label.text = title
	_sub_label.text = subtitle
	_name_label.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35))
	_fill.color = color
	_shine.color = Color(1, 1, 1, 0.22)
	_back.color = Color(0.07, 0.03, 0.1, 0.95)
	var portrait_info: Variant = PORTRAITS.get(title)
	_portrait.visible = false
	if portrait_info != null and ResourceLoader.exists(portrait_info[0]):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(portrait_info[0]) as Texture2D
		atlas.region = portrait_info[1]
		_portrait.texture = atlas
		_portrait.visible = true
	_set_ratio(1.0, true)
	_pieces_label.text = ""
	_kill(_entrance_tween)
	_kill(_letter_tween)
	_kill(_flash_tween)
	_kill(_announce_tween)
	_announce_label.modulate.a = 0.0
	_announce_label.add_theme_color_override("font_color", Color.WHITE)
	# the panel slides in from above, the vignette creeps in, the world flashes
	_panel.modulate.a = 1.0
	_panel.position.y = -PANEL_HEIGHT - 20.0
	_vignette.modulate = Color(color.r * 0.6 + 0.4, color.g * 0.6 + 0.4, color.b * 0.6 + 0.4, 0.0)
	_entrance_tween = create_tween().set_parallel(true)
	_entrance_tween.tween_property(_panel, "position:y", 16.0, 0.7).set_delay(0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_entrance_tween.tween_property(_vignette, "modulate:a", 0.75, 1.4)
	_flash_screen(Color(1, 1, 1), 0.55, 0.5)
	_letterbox(true)
	_letter_tween = create_tween()
	_letter_tween.tween_interval(ENTRANCE_HOLD)
	_letter_tween.tween_callback(func() -> void: _letterbox(false))


func set_health(current: int, maximum: int, pieces: int) -> void:
	if not _active:
		return
	var ratio := clampf(float(current) / float(maxi(maximum, 1)), 0.0, 1.0)
	var lost := ratio < _ratio
	_set_ratio(ratio, false)
	if lost:
		_fill.color = Color.WHITE
		create_tween().tween_property(_fill, "color", _accent, 0.14)
	_pieces_label.text = "x%d" % pieces if pieces > 1 else ""


func announce(text: String) -> void:
	if not _active:
		return
	_kill(_announce_tween)
	_announce_label.text = text
	_announce_label.pivot_offset = _announce_label.size * 0.5
	_announce_label.scale = Vector2(1.5, 1.5)
	_announce_label.modulate.a = 0.0
	_announce_tween = create_tween().set_parallel(true)
	_announce_tween.tween_property(_announce_label, "modulate:a", 1.0, 0.15)
	_announce_tween.tween_property(_announce_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tween.chain().tween_interval(1.4)
	_announce_tween.chain().tween_property(_announce_label, "modulate:a", 0.0, 0.5)
	if text != "THE WAY DOWN OPENS":
		_flash_screen(_accent.lerp(Color.WHITE, 0.5), 0.3, 0.3)


func hide_boss(defeated: bool) -> void:
	if not _active:
		return
	_active = false
	_kill(_entrance_tween)
	_kill(_letter_tween)
	_kill(_announce_tween)
	if defeated:
		_set_ratio(0.0, false)
		_flash_screen(Color(1, 1, 1), 0.9, 0.7)
		_announce_label.text = "%s DEFEATED" % _name_label.text
		_announce_label.add_theme_color_override("font_color", GOLD)
		_announce_label.pivot_offset = _announce_label.size * 0.5
		_announce_label.scale = Vector2(1.6, 1.6)
		_announce_label.modulate.a = 0.0
		_letterbox(true)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_announce_label, "modulate:a", 1.0, 0.25)
		tween.tween_property(_announce_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain().tween_interval(2.0)
		tween.chain().tween_callback(func() -> void: _letterbox(false))
		tween.chain().tween_property(_announce_label, "modulate:a", 0.0, 0.8)
		tween.parallel().tween_property(_panel, "modulate:a", 0.0, 0.8)
		tween.parallel().tween_property(_vignette, "modulate:a", 0.0, 1.2)
		tween.chain().tween_callback(func() -> void:
			_announce_label.add_theme_color_override("font_color", Color.WHITE)
			if not _active:
				visible = false)
	else:
		_letterbox(false)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_panel, "modulate:a", 0.0, 0.4)
		tween.tween_property(_vignette, "modulate:a", 0.0, 0.5)
		tween.tween_property(_announce_label, "modulate:a", 0.0, 0.2)
		tween.chain().tween_callback(func() -> void:
			if not _active:
				visible = false)


# ------------------------------------------------------------------ the bar

## Sets how full the bar is. The fill follows quickly; the pale "ghost" behind it follows slowly, so the
## player can see how much each blow took.
func _set_ratio(ratio: float, instant: bool) -> void:
	var previous := _ratio
	_ratio = ratio
	var width := BAR_WIDTH * ratio
	_kill(_fill_tween)
	_kill(_ghost_tween)
	if instant:
		_fill.size.x = width
		_ghost.size.x = width
		_shine.size.x = width
		return
	_fill_tween = create_tween().set_parallel(true)
	_fill_tween.tween_property(_fill, "size:x", width, 0.12)
	_fill_tween.tween_property(_shine, "size:x", width, 0.12)
	if ratio < previous:
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(0.45)
		_ghost_tween.tween_property(_ghost, "size:x", width, 0.55).set_trans(Tween.TRANS_SINE)
	else:
		_ghost.size.x = width


func _letterbox(show_bars: bool) -> void:
	var tween := create_tween().set_parallel(true)
	var time := 0.45 if show_bars else 0.6
	var top_y := 0.0 if show_bars else -LETTERBOX
	var bottom_y := -LETTERBOX if show_bars else 0.0
	tween.tween_property(_letter_top, "position:y", top_y, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_letter_bottom, "position:y", size.y + bottom_y, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _flash_screen(color: Color, alpha: float, seconds: float) -> void:
	_kill(_flash_tween)
	_flash.color = Color(color.r, color.g, color.b, alpha)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, seconds)


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


# ------------------------------------------------------------------ building the widgets

func _build() -> void:
	# purple-black vignette around the screen edges
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.16, 0.0, 0.26, 0.9)])
	var vignette_tex := GradientTexture2D.new()
	vignette_tex.gradient = gradient
	vignette_tex.width = 256
	vignette_tex.height = 256
	vignette_tex.fill = GradientTexture2D.FILL_RADIAL
	vignette_tex.fill_from = Vector2(0.5, 0.5)
	vignette_tex.fill_to = Vector2(1.0, 0.5)
	_vignette = TextureRect.new()
	_vignette.texture = vignette_tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	_letter_top = _make_letterbox_bar(true)
	_letter_bottom = _make_letterbox_bar(false)

	# the panel: portrait, name, subtitle, bar
	var panel_width := 70.0 + BAR_WIDTH + 14.0
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -panel_width * 0.5
	_panel.offset_right = panel_width * 0.5
	_panel.offset_top = -PANEL_HEIGHT - 20.0
	_panel.offset_bottom = -20.0
	add_child(_panel)

	var frame := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.02, 0.07, 0.88)
	style.border_color = Color(0.55, 0.42, 0.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 6
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(frame)

	_portrait = TextureRect.new()
	_portrait.position = Vector2(8.0, 7.0)
	_portrait.size = Vector2(56.0, 60.0)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_portrait)

	_name_label = _make_label(22, Color.WHITE, Vector2(70.0, 5.0))
	_sub_label = _make_label(12, Color(0.72, 0.68, 0.8), Vector2(72.0, 30.0))
	_pieces_label = _make_label(16, GOLD, Vector2(70.0 + BAR_WIDTH - 60.0, 28.0))
	_pieces_label.size = Vector2(60.0, 18.0)
	_pieces_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel.add_child(_name_label)
	_panel.add_child(_sub_label)
	_panel.add_child(_pieces_label)

	_back = ColorRect.new()
	_back.position = Vector2(70.0, 50.0)
	_back.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_back)
	_ghost = ColorRect.new()
	_ghost.color = Color(1.0, 0.85, 0.85, 0.85)
	_ghost.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(_ghost)
	_fill = ColorRect.new()
	_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(_fill)
	_shine = ColorRect.new()
	_shine.size = Vector2(BAR_WIDTH, 4.0)
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(_shine)
	# a notch at half health: where the Queen splits
	var notch := ColorRect.new()
	notch.color = Color(1, 1, 1, 0.55)
	notch.position = Vector2(BAR_WIDTH * 0.5 - 1.0, -2.0)
	notch.size = Vector2(2.0, BAR_HEIGHT + 4.0)
	notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(notch)
	# bar frame lines
	for edge in [Rect2(-2, -2, BAR_WIDTH + 4, 2), Rect2(-2, BAR_HEIGHT, BAR_WIDTH + 4, 2), Rect2(-2, -2, 2, BAR_HEIGHT + 4), Rect2(BAR_WIDTH, -2, 2, BAR_HEIGHT + 4)]:
		var line := ColorRect.new()
		line.color = Color(0.55, 0.42, 0.22)
		line.position = edge.position
		line.size = edge.size
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back.add_child(line)

	_announce_label = _make_label(30, Color.WHITE, Vector2.ZERO)
	_announce_label.set_anchors_preset(Control.PRESET_CENTER)
	_announce_label.anchor_left = 0.0
	_announce_label.anchor_right = 1.0
	_announce_label.anchor_top = 0.5
	_announce_label.anchor_bottom = 0.5
	_announce_label.offset_left = 0.0
	_announce_label.offset_right = 0.0
	_announce_label.offset_top = 70.0
	_announce_label.offset_bottom = 110.0
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.modulate.a = 0.0
	add_child(_announce_label)


func _make_label(font_size: int, color: Color, pos: Vector2) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.position = pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_letterbox_bar(top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0.0, LETTERBOX)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# hidden: the top bar above the screen, the bottom one far below (_letterbox places it with the real size)
	bar.position.y = -LETTERBOX if top else 4000.0
	return bar
