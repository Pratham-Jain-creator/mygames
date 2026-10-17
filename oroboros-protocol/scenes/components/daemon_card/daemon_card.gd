class_name DaemonCard
extends InteractiveControl
## An installed Daemon, drawn like an expansion card plugged into the motherboard.
## An empty slot is a DaemonCard with no instance bound.

var inst: Dictionary = {}
var slot_index := 0
## Optional gate set by the owning screen (e.g. no reordering mid-turn).
var drag_allowed := Callable()

@onready var _edge: ColorRect = %Edge
@onready var _frame: Control = %Frame   # DaemonFrame (daemon_frame.gd), duck-typed
@onready var _name_label: Label = %NameLabel
@onready var _rarity_label: Label = %RarityLabel
@onready var _state_label: Label = %StateLabel


func _ready() -> void:
	super()
	set_empty(slot_index)


func set_empty(index: int) -> void:
	inst = {}
	set_idle(false)
	slot_index = index
	_name_label.text = "[ SLOT %d ]" % (index + 1)
	_name_label.add_theme_color_override("font_color", Enums.COL_DIM)
	_rarity_label.text = "EMPTY"
	_rarity_label.add_theme_color_override("font_color", Enums.COL_DIM)
	_state_label.text = ""
	_edge.color = Enums.COL_DIM
	_frame.empty = true


func bind(d: Dictionary) -> void:
	inst = d
	var def := DaemonDB.get_def(d.id)
	_name_label.text = def.name
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_rarity_label.text = Enums.RARITY_NAMES[def.rarity]
	_rarity_label.add_theme_color_override("font_color", Enums.RARITY_COLORS[def.rarity])
	_edge.color = Enums.COL_DAEMON
	_frame.rarity = def.rarity
	_frame.empty = false
	set_idle(true, Enums.COL_DAEMON, 0.9)
	refresh_state()


func refresh_state() -> void:
	if inst.is_empty():
		return
	var s: Dictionary = inst.s
	var n: float = s.get("n", 0.0)
	match inst.id:
		"masochist", "trojan":
			_state_label.text = "+%s OC" % DaemonLogic._fmt(n)
		"overwritten_file":
			_state_label.text = "+%d Base +%s OC" % [int(n * 2.0), DaemonLogic._fmt(minf(5.0, 0.25 * n))]
		"spyware":
			_state_label.text = "x%s" % DaemonLogic._fmt(1.0 + 0.1 * n)
		"obelisk":
			_state_label.text = "x%s" % DaemonLogic._fmt(1.0 + 0.2 * n)
		"rust":
			_state_label.text = "%s BW" % DaemonLogic._fmt(n)
		"iron_ledger":
			_state_label.text = "+%d Base" % int(n * 2.0)
		"ledger_of_souls":
			_state_label.text = "+%d Base" % int(minf(12.0, n) * 3.0)
		"compound_interest", "scar_tissue":
			_state_label.text = "+%s OC" % DaemonLogic._fmt(n)
		"streak_counter":
			_state_label.text = "+%s OC" % DaemonLogic._fmt(minf(3.0, 0.5 * n))
		"crypto_miner":
			_state_label.text = "sell Ø%d" % RunState.field_sell_value(inst)
		_:
			_state_label.text = ""


# ------------------------------------------------------- drag & drop reorder
func _get_drag_data(_at: Vector2) -> Variant:
	if inst.is_empty():
		return null
	if drag_allowed.is_valid() and not drag_allowed.call():
		return null
	# The press becomes a drag: cancel click / long-press handling.
	is_pressed = false
	_press_timer.stop()
	TooltipService.hide_for(self)
	_hover_animation(false)
	var def := DaemonDB.get_def(inst.id)
	var box := PanelContainer.new()
	var l := Label.new()
	l.text = "  %s  " % def.name
	l.add_theme_color_override("font_color", Enums.COL_DAEMON)
	box.add_child(l)
	box.modulate.a = 0.9
	set_drag_preview(box)
	AudioService.play("tick", 1.1)
	return {"daemon_drag": slot_index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("daemon_drag")):
		return false
	var to := mini(slot_index, RunState.daemons.size() - 1)
	return int(data.daemon_drag) != to


func _drop_data(_at: Vector2, data: Variant) -> void:
	if RunState.move_daemon(int(data.daemon_drag), slot_index):
		AudioService.play("click", 0.9)


func flash() -> void:
	play_anim(&"flash")


func pop_in() -> void:
	play_anim(&"pop_in")


func get_tip_data() -> Dictionary:
	if inst.is_empty():
		return {"title": "EMPTY DAEMON SLOT", "body": "Buy Daemons in the Black Market. Order matters: they score left to right, so put +Overclock before xOverclock.", "color": Enums.COL_DIM}
	var def := DaemonDB.get_def(inst.id)
	return {
		"title": "%s  [%s]" % [def.name, Enums.RARITY_NAMES[def.rarity]],
		"body": "%s\n\n[color=#FFD866]Sell mid-run: Ø%d (half price). Click the Daemon, then press SELL.[/color]" % [def.desc, RunState.field_sell_value(inst)],
		"color": Enums.COL_DAEMON,
	}
