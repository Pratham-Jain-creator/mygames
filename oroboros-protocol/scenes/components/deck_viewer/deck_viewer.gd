class_name DeckViewer
extends Control
## Overlay listing the whole deck. Two modes:
##  * view: deck tracker (dimmed = already played this Server / in the room)
##  * pick: choose N nodes as the target of an Executable / Corruption / Purge
## `await viewer.pick(title, min, max)` returns the chosen Array[NodeData] (empty = cancelled).

signal closed(result: Array)

const COLUMNS := 10            # cards per row; their size is computed so the row fills the panel
const GAP := 8.0
const MIN_SCALE := 0.4
const MAX_SCALE := 0.8

var _picking := false
var _min := 0
var _max := 0
var _chosen: Array = []       # Array[NodeCard]
var _cards: Array = []

@onready var _title: Label = %TitleLabel
@onready var _info: Label = %InfoLabel
@onready var _grid: GridContainer = %Grid
@onready var _cancel: ActionButton = %CancelButton
@onready var _confirm: ActionButton = %ConfirmButton
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _scroll: ScrollContainer = $Panel/VBox/Scroll

var _drag_armed := false
var _drag_active := false
var _drag_start := Vector2.ZERO


func _ready() -> void:
	z_index = 50   # overlays always draw above raised (selected / hovered) Node cards
	_cancel.activated.connect(func(_s): _finish([]))
	_confirm.activated.connect(func(_s): _finish(_chosen.map(func(c): return c.data)))


## Cards swallow presses, so a finger / mouse drag that starts on a card would never reach
## the ScrollContainer. This turns a drag over the list into scrolling (the wheel already works).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_drag_armed = mb.pressed and _scroll.get_global_rect().has_point(mb.global_position)
		_drag_active = false
		_drag_start = mb.global_position
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _drag_armed and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if not _drag_active and mm.global_position.distance_to(_drag_start) > 10.0:
			_drag_active = true
			# The pressed card must not count this as a click or a long press.
			for c in _cards:
				c.is_pressed = false
			TooltipService.hide_now()
		if _drag_active:
			_scroll.scroll_vertical -= int(mm.relative.y)
			get_viewport().set_input_as_handled()


func open_view() -> void:
	_picking = false
	_title.text = "TAILBYTES TRACKER"
	_info.text = "Dimmed = already played or in the room. Press and hold a node for details."
	_confirm.visible = false
	_cancel.text = "CLOSE"
	_populate()
	_show()


func pick(title: String, min_n: int, max_n: int) -> Array:
	_picking = true
	_min = min_n
	_max = max_n
	_title.text = title
	_info.text = "Select %s node(s). Hover for details." % (str(max_n) if min_n == max_n else "%d to %d" % [min_n, max_n])
	_confirm.visible = true
	_confirm.disabled = true
	_cancel.text = "CANCEL"
	_populate()
	_show()
	var result: Array = await closed
	return result


func _show() -> void:
	_anim.play(&"show")


## Card scale that makes COLUMNS cards fill the panel width (flex-box style).
func _fit_scale() -> float:
	var avail := get_viewport_rect().size.x - 70.0 * 2.0 - 70.0     # panel margins + padding + scrollbar
	var w := (avail - (COLUMNS - 1) * GAP) / COLUMNS
	return clampf(w / NodeCardFactory.CARD_SIZE.x, MIN_SCALE, MAX_SCALE)


func _populate() -> void:
	var card_scale := _fit_scale()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	for c in _cards:
		NodeCardFactory.dispose(c)
	_cards.clear()
	_chosen.clear()
	var nodes: Array = RunState.deck.all_nodes.duplicate()
	nodes.sort_custom(func(a, b): return a.type < b.type or (a.type == b.type and a.eff_value < b.eff_value))
	var in_draw := {}
	for n in RunState.deck.draw_pile:
		in_draw[n] = true
	# Dimming only makes sense on the Server screen. RunState.server still holds the last
	# cleared Server in the Black Market / map, where the whole deck is back in play.
	var host := get_parent()
	var server_running := RunState.server != null and host != null and host.get("phase") != null
	for n: NodeData in nodes:
		var saved_face := n.face_down
		n.face_down = n.spent_hidden and server_running and not in_draw.has(n)
		n.eff_value = n.base_value if not server_running or not RunState.server.room.has(n) else n.eff_value
		var card := NodeCardFactory.spawn(_grid, n, card_scale)
		n.face_down = saved_face
		if not _picking and server_running and not in_draw.has(n) and not n.spent_hidden:
			card.modulate = Color(1, 1, 1, 0.35)
		card.activated.connect(_on_card_activated)
		_cards.append(card)


func _on_card_activated(card: InteractiveControl) -> void:
	if not _picking:
		return
	var nc := card as NodeCard
	if _chosen.has(nc):
		_chosen.erase(nc)
		nc.set_selected(false)
	else:
		if _chosen.size() >= _max:
			if _max == 1 and not _chosen.is_empty():
				var old: NodeCard = _chosen[0]
				old.set_selected(false)
				_chosen.clear()
			else:
				nc.deny()
				return
		_chosen.append(nc)
		nc.set_selected(true, _chosen.size())
	_confirm.disabled = _chosen.size() < _min or _chosen.size() > _max


func _finish(result: Array) -> void:
	_anim.play(&"hide")
	TooltipService.hide_now()
	closed.emit(result)
