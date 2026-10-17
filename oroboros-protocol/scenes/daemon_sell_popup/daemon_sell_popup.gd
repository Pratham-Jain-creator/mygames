extends PanelContainer
## Small "sell this Daemon" bubble that appears beside a Daemon card when it is clicked.
## Duck-typed on purpose (no class_name). The owner screen calls `open_for` and listens
## to `sell_requested`.

signal sell_requested
signal closed

var _uid := -1
var _desc_panel: PanelContainer = null
var _desc_label: RichTextLabel = null
const DESC_WIDTH := 250.0

@onready var _name_label: Label = %NameLabel
@onready var _sell_button: ActionButton = %SellButton
@onready var _note: Label = %Note
@onready var _anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	z_index = 50   # overlays always draw above raised (selected / hovered) Node cards
	visible = false
	_sell_button.activated.connect(func(_s): sell_requested.emit())


func is_open() -> bool:
	return visible


func current_uid() -> int:
	return _uid


func open_for(card: Control, uid: int, daemon_name: String, price: int, desc := "", rarity_text := "") -> void:
	_uid = uid
	_name_label.text = daemon_name.to_upper()
	_sell_button.text = "SELL  Ø%d" % price
	_note.text = "half price"
	visible = true
	reset_size()
	# Wait one frame so the container reports its real size, then sit beside the card.
	await get_tree().process_frame
	if not visible:
		return
	var vp := get_viewport_rect().size
	var r := card.get_global_rect()
	# SELL sits on the right of the card (left if there is no room); the description takes
	# the opposite side so both are readable at once.
	var sell_right := r.end.x + 8.0 + size.x <= vp.x - 6.0
	var x := r.end.x + 8.0 if sell_right else r.position.x - size.x - 8.0
	var y := r.position.y + (r.size.y - size.y) * 0.5
	y = clampf(y, 6.0, vp.y - size.y - 6.0)
	global_position = Vector2(maxf(6.0, x), y)
	_show_desc(r, vp, not sell_right, daemon_name, desc, rarity_text)
	_anim.play(&"open")


## Description bubble on the opposite side of the SELL bubble.
func _show_desc(card_rect: Rect2, vp: Vector2, on_right: bool, daemon_name: String, desc: String, rarity_text: String) -> void:
	if desc == "":
		_hide_desc()
		return
	if _desc_panel == null:
		_desc_panel = PanelContainer.new()
		_desc_panel.z_index = 50
		_desc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.06, 0.09, 0.97)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.9, 0.1, 0.8, 1)
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		_desc_panel.add_theme_stylebox_override("panel", sb)
		_desc_label = RichTextLabel.new()
		_desc_label.bbcode_enabled = true
		_desc_label.fit_content = true
		_desc_label.scroll_active = false
		_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_desc_label.custom_minimum_size = Vector2(DESC_WIDTH, 0)
		_desc_label.add_theme_font_size_override("normal_font_size", 14)
		_desc_label.add_theme_font_size_override("bold_font_size", 15)
		_desc_panel.add_child(_desc_label)
		get_parent().add_child(_desc_panel)
	var head := daemon_name.to_upper()
	if rarity_text != "":
		head += "  [%s]" % rarity_text
	_desc_label.text = "[b][color=#E619CC]%s[/color][/b]\n%s" % [head, desc]
	_desc_panel.visible = true
	_desc_panel.reset_size()
	await get_tree().process_frame
	if not visible or _desc_panel == null:
		return
	var w := _desc_panel.size.x
	var dx := card_rect.end.x + 8.0 if on_right else card_rect.position.x - w - 8.0
	var dy := card_rect.position.y + (card_rect.size.y - _desc_panel.size.y) * 0.5
	dy = clampf(dy, 6.0, vp.y - _desc_panel.size.y - 6.0)
	_desc_panel.global_position = Vector2(clampf(dx, 6.0, vp.x - w - 6.0), dy)


func _hide_desc() -> void:
	if _desc_panel != null:
		_desc_panel.visible = false


func close() -> void:
	if not visible:
		return
	visible = false
	_hide_desc()
	_uid = -1
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		# A press anywhere outside the bubble dismisses it (the press still goes through).
		if not get_global_rect().has_point(event.global_position):
			close()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
