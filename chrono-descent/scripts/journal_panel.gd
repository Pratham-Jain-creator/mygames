extends CanvasLayer
## The journal's reading panel: the story of the dungeon. Opened by journal.gd, closed with the same
## INTERACT key that opened it (Square / E), or the standard BACK key (Circle / Esc). The player is
## frozen while it is open.

const FONT: Font = preload("res://assets/sprites/dungeon_set/pixel_bars_free/addons/pixel_bars/font/pixel_ui_font.fnt")
## Ignore the very first moments so the key press that opened it can't close it again.
const CLOSE_GRACE: float = 0.3
## After closing, the player stays frozen this long. Otherwise the same press that closed the panel is
## still "just pressed" for the player, who is standing next to the journal and would open it again.
const UNFREEZE_DELAY: float = 0.25

const TITLE := "[center][font_size=24][color=#e8d9a8]THE JOURNAL OF THE LAST DESCENDER[/color][/font_size][/center]"
const ENTRIES: Array[String] = [
	"[color=#d9c9a0]I.   There is a master of this place: CHRONOS, the Warden of Hours. He waits in the deepest level, the hundredth floor, and the dungeon bends to his will. End him, and the dungeon dies with him.[/color]",
	"[color=#d9c9a0]II.  The dungeon is alive. It never rests and it never keeps its shape. You will have about fifteen minutes on each floor before it changes.[/color]",
	"[color=#d9c9a0]III. When it changes, only two places survive: the hall where you arrived, and the hall where the stairs lead down. Every other room collapses and is built anew. Do not be caught between them.[/color]",
	"[color=#c1121f][outline_size=4][outline_color=#2a0000]IV.  DEATH IS PERMANENT. Those who fall below do not return. Only their journal remains.[/outline_color][/outline_size][/color]",
]
const CLOSING := "[center][color=#8a7a6a]Take the stairs when you are ready.[/color][/center]"

var _age: float = 0.0
var _hint: Label
var _closing: bool = false


func _ready() -> void:
	layer = 40
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.06, 0.08, 0.98)
	style.border_color = Color(0.55, 0.40, 0.30)
	style.set_border_width_all(4)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(860, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_override("normal_font", FONT)
	text.add_theme_font_size_override("normal_font_size", 16)
	text.text = TITLE + "\n\n" + "\n\n".join(ENTRIES) + "\n\n" + CLOSING
	box.add_child(text)

	_hint = Label.new()
	_hint.add_theme_font_override("font", FONT)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.62, 0.55))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)

	if is_instance_valid(GameManager.player):
		GameManager.player.set_input_locked(true)


func _process(delta: float) -> void:
	if _closing:
		return
	_age += delta
	_hint.text = "%s  CLOSE" % InputHints.get_action_hint(&"interact")
	if _age < CLOSE_GRACE:
		return
	for action in [&"interact", &"ui_cancel"]:
		if Input.is_action_just_pressed(action):
			_close()
			return


func _close() -> void:
	_closing = true
	visible = false # gone at once, but the player stays frozen a moment longer (see UNFREEZE_DELAY)
	await get_tree().create_timer(UNFREEZE_DELAY).timeout
	if is_instance_valid(GameManager.player):
		GameManager.player.set_input_locked(false)
	queue_free()
