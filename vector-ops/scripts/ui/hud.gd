class_name Hud
extends CanvasLayer
## Owns the screens: the start menu (scenes/ui/menu.tscn), the pause menu
## (scenes/ui/pause_menu.tscn), the lobby, and the in-game HUD
## (scenes/ui/hud.tscn, script hud_view.gd). Only the lobby is still built here.
## The lobby art comes from the PNGs in res://assets/images/UI/
## (authored at 2x, so it is shown at half size).
##
## Gamepad: all bindings are in the Input Map (Project Settings). Menus use
## Godot's own ui_* actions; this script only remembers which device was used
## last and gives the first button the focus when the pad is used.

const UI := "res://assets/images/UI/"
const MENU_SCENE := preload("res://scenes/ui/menu.tscn")
const PAUSE_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const C_TEXT := Color("dce9f0")
const C_TEAL := Color("40d9c4")
const C_DARK := Color("06141a")

var menu: Control
var pause_menu: Control
var lobby_panel: Control
var game_root: Control

var lobby_label: Label
var start_btn: Button
var spinner: TextureRect


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS # the pause menu needs this node alive while paused
	menu = MENU_SCENE.instantiate()
	menu.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(menu)
	_build_lobby()
	game_root = HUD_SCENE.instantiate()
	game_root.process_mode = Node.PROCESS_MODE_PAUSABLE # no warning beeps etc. while paused
	add_child(game_root)
	pause_menu = PAUSE_SCENE.instantiate()
	add_child(pause_menu) # last child = drawn on top of everything


# --- texture helpers ---------------------------------------------------------

func _tex(p: String) -> Texture2D:
	return load(UI + p) as Texture2D


func _sbt(p: String, m: float = 16.0, cm: Vector4 = Vector4(12, 8, 12, 8)) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _tex(p)
	sb.set_texture_margin_all(m)
	sb.content_margin_left = cm.x
	sb.content_margin_top = cm.y
	sb.content_margin_right = cm.z
	sb.content_margin_bottom = cm.w
	return sb


## Menu label: no outline, themed colours.
func _ml(text: String, size: int = 14, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _tbtn(kind: String, text: String, size: Vector2, col: Color = C_TEXT, fsize: int = 15, margin: float = 20.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var cm := Vector4(18, 4, 10, 4)
	b.add_theme_stylebox_override("normal", _sbt("buttons/btn_%s_normal.png" % kind, margin, cm))
	b.add_theme_stylebox_override("hover", _sbt("buttons/btn_%s_hover.png" % kind, margin, cm))
	b.add_theme_stylebox_override("pressed", _sbt("buttons/btn_%s_pressed.png" % kind, margin, cm))
	b.add_theme_stylebox_override("focus", _sbt("buttons/btn_%s_hover.png" % kind, margin, cm)) # pad focus = hover look
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, col)
	b.add_theme_font_size_override("font_size", fsize)
	return b


func _hdiv(path: String = "panels/divider_solid.png") -> TextureRect:
	var t := TextureRect.new()
	t.texture = _tex(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(0, 1)
	return t


func _centered(panel: Control) -> Control:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(panel)
	add_child(cc)
	return cc


# --- lobby -------------------------------------------------------------------------

func _build_lobby() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sbt("panels/panel_dialog.png", 20, Vector4(30, 26, 30, 26)))
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	spinner = TextureRect.new()
	spinner.texture = _tex("readout/spinner_ring.png")
	spinner.custom_minimum_size = Vector2(36, 36)
	spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spinner.pivot_offset = Vector2(18, 18)
	top.add_child(spinner)
	top.add_child(_ml("LOBBY", 24, C_TEAL))
	v.add_child(top)
	v.add_child(_hdiv())
	lobby_label = _ml("", 14, C_TEXT)
	v.add_child(lobby_label)
	start_btn = _tbtn("play", "START MATCH\nFirst to 3 rounds", Vector2(0, 66), C_DARK, 15, 24.0)
	start_btn.pressed.connect(func() -> void: GameState.request_start())
	v.add_child(start_btn)
	lobby_panel = _centered(panel)


# --- per-frame update -------------------------------------------------------

func _process(delta: float) -> void:
	var phase: int = GameState.phase
	menu.visible = not GameState.in_session
	lobby_panel.visible = GameState.in_session and phase == GameState.Phase.LOBBY
	game_root.visible = GameState.in_session and phase != GameState.Phase.LOBBY
	if lobby_panel.visible:
		lobby_label.text = GameState.lobby_text
		start_btn.visible = multiplayer.is_server()
		spinner.rotation += delta * 3.0
	_focus_for_pad()


## Which device was used last (the controller-only aim assist keys off this).
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		GameState.using_pad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.4: # ignore stick drift
			GameState.using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		GameState.using_pad = false
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (event as InputEventMouseMotion).relative.length() > 0.5:
		GameState.using_pad = false # real mouse-look only: the cursor jump when the pause menu frees it must not count


## With a pad and nothing focused on a menu screen, focus the first button so the
## d-pad / stick (ui_up...) and Cross (ui_accept) work through Godot's own UI input.
func _focus_for_pad() -> void:
	if not GameState.using_pad or get_viewport().gui_get_focus_owner() != null:
		return
	var screen: Control = pause_menu if pause_menu.visible else (menu if menu.visible else (lobby_panel if lobby_panel.visible else null))
	if screen == null:
		return
	for n in screen.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and not b.disabled:
			b.focus_mode = Control.FOCUS_ALL
			b.grab_focus()
			return
