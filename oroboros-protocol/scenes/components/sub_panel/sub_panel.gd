extends Control
## Overlay listing every Subroutine with what it scores RIGHT NOW (Firmware Update
## levels included). Reads SubroutineDB + RunState on every open / refresh, so
## upgrades bought in the Black Market always show up.

signal closed
signal close_requested

const COL_HEAD := Color("5B6470")
const COL_NORMAL := Color("C5C6C7")
const COL_UPGRADED := Color("FFB400")
const COL_FLASH := Color("66FCF1")

@onready var _grid: GridContainer = %Grid
@onready var _close: ActionButton = %CloseButton
@onready var _note: RichTextLabel = %NoteLabel
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _flash_id := ""


func _ready() -> void:
	z_index = 50   # overlays always draw above raised (selected / hovered) Node cards
	_close.activated.connect(func(_s): close_requested.emit())


func open_view() -> void:
	refresh()
	_anim.play(&"show")


func close_view() -> void:
	if not visible:
		return
	_anim.play(&"hide")
	TooltipService.hide_now()
	closed.emit()


## `flash_id`: highlight one row (used by the tutorial after a Firmware Update).
func refresh(flash_id := "") -> void:
	_flash_id = flash_id
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for h in ["SUBROUTINE", "NODES", "BASE BYTES", "OVERCLOCK", "FIRMWARE", "PLAYED"]:
		_cell(h, COL_HEAD, 15)
	var ids: Array = SubroutineDB.ORDER.duplicate()
	ids.append("fragment")
	var void_boss := RunState.server != null and RunState.is_boss("void")
	for id: String in ids:
		var def: Dictionary = SubroutineDB.SUBS[id]
		var lvl: int = int(RunState.sub_levels.get(id, 0))
		var col := COL_NORMAL
		if lvl > 0:
			col = COL_UPGRADED
		if id == flash_id:
			col = COL_FLASH
		var base := 0 if void_boss else SubroutineDB.base_for(id, lvl)
		_cell(String(def.name).to_upper(), col, 19)
		_cell(String(def.text), COL_NORMAL, 16, true)
		_cell("+%d" % base, col, 19)
		_cell("+%d" % SubroutineDB.mult_for(id, lvl), col, 19)
		if id == "fragment":
			_cell("-", COL_HEAD, 16)
		else:
			var fw := "LV %d" % lvl
			if lvl > 0:
				fw += "  (+%d / +%d per level)" % [int(def.lvl_base), int(def.lvl_mult)]
			if id == flash_id:
				fw += "  UPGRADED!"
			_cell(fw, col if lvl > 0 else COL_HEAD, 16)
		_cell(str(int(RunState.sub_play_counts.get(id, 0))), COL_HEAD, 16)
	_note.text = Fmt.rich("BYTES SIPHONED = Base Bytes x Overclock.\nBase Bytes = Subroutine Base + Node values + Daemon Base.  Overclock = 1 + Glitch hits taken + Subroutine Overclock + Daemon Overclock.\nFirmware Updates (Black Market) raise a Subroutine permanently. Amber = upgraded.")
	if void_boss:
		_note.text += "\nTHE VOID: Subroutine Base Bytes is 0 during this Server."


func _cell(text: String, color: Color, size: int, rich := false) -> void:
	if rich:
		# BBCode cell: Node-type words (Siphon / Glitch / Firewall / Patch) in their own colours.
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.scroll_active = false
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
		r.text = Fmt.rich(text)
		r.add_theme_color_override("default_color", color)
		r.add_theme_font_size_override("normal_font_size", size)
		r.add_theme_font_size_override("bold_font_size", size)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(r)
		return
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(l)
