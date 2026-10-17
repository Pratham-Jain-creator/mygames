class_name LoadoutScreen
extends CanvasLayer
## The inventory screen, opened with the inventory button anywhere (laid out like the Equipment and Backpack windows of
## the UI sheet). LEFT: what you wear: armor, the three charm slots (grafts marked in red), the canteen, the sword form
## and every active bonus. RIGHT: what you CARRY this run (ash, materials, blueprints), which is lost if you die until
## you extract it. Read-only: the workbench in the base is where you change your loadout.

## Readable names for the stats of RunData, and how to show them.
const STAT_LINES: Array = [
	["damage", "SWORD DAMAGE", "pct"], ["attack_speed", "SWING SPEED", "pct"], ["reach", "SWORD REACH", "pct"], ["elite_dmg", "DAMAGE TO ELITES / BOSSES", "pct"],
	["move", "MOVEMENT SPEED", "pct"], ["taken", "DAMAGE TAKEN", "pct"], ["max_hp", "MAXIMUM HEALTH", "flat"], ["max_hp_pct", "MAXIMUM HEALTH", "pct"],
	["lifesteal", "HEALED FROM DAMAGE DEALT", "pct"], ["kill_heal", "HEALTH PER KILL", "pct"], ["heal", "CANTEEN HEALING", "pct"],
	["canteen_max", "CANTEEN CHARGES", "flat"], ["iframes", "DASH INVULNERABILITY", "pct"], ["dash_cd", "DASH COOLDOWN", "pct"],
	["ash", "ASH GAINED", "pct"], ["drop_mats", "EXTRA MATERIALS FROM ELITES", "flat"], ["time_rate", "FLOOR TIMER SPEED", "pct"],
	["enemy_hp", "ENEMY HEALTH", "pct"], ["regen", "HEALTH PER SECOND", "flat"],
]
## Stats where a NEGATIVE number is good news.
const LOWER_IS_BETTER: Array[String] = ["taken", "dash_cd"]

var _player: Node
var _open: bool = false
var _equipment: VBoxContainer
var _backpack: VBoxContainer
var _root: Control


func setup(player: Node) -> void:
	_player = player


func _ready() -> void:
	layer = 20
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.7)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var left := UIKit.window("EQUIPMENT", Vector2(540, 560))
	left["root"].position = Vector2(36, 44)
	_root.add_child(left["root"])
	_equipment = left["body"]
	var right := UIKit.window("BACKPACK", Vector2(520, 560))
	right["root"].position = Vector2(596, 44)
	_root.add_child(right["root"])
	_backpack = right["body"]
	var hint := UIKit.label("", 12, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	hint.name = "Hint"
	hint.position = Vector2(36, 616)
	hint.size = Vector2(1080, 20)
	_root.add_child(hint)
	Run.changed.connect(func() -> void:
		if _open:
			refresh())


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	if is_instance_valid(_player):
		_player.set_input_locked(true)
	(_root.get_node("Hint") as Label).text = "%s  CLOSE" % InputHints.get_action_hint(&"inventory")
	refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if is_instance_valid(_player):
		_player.set_input_locked(false)


func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


# ------------------------------------------------------------------ content

func refresh() -> void:
	_fill_equipment()
	_fill_backpack()


func _row(icon: Control, title: String, title_color: Color, lines: Array, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.box(UIKit.BG_DEEP, accent, 2, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	icon.custom_minimum_size = Vector2(48, 48)
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 1)
	row.add_child(text)
	text.add_child(UIKit.label(title, 16, title_color))
	for line: Array in lines:
		var l := UIKit.label(String(line[0]), 12, line[1])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(l)
	return panel


func _fill_equipment() -> void:
	UIKit.clear(_equipment)
	var armor: Dictionary = RunData.ARMOR[Run.armor]
	_equipment.add_child(UIKit.label("ARMOR", 12, UIKit.DIM))
	_equipment.add_child(_row(UIKit.gem(armor["color"], 0), String(armor["name"]).to_upper(), UIKit.GOLD_BRIGHT, [[armor["desc"], UIKit.TEXT], [stats_text(armor["stats"]), UIKit.GOOD]], UIKit.BORDER))
	_equipment.add_child(UIKit.label("CHARMS", 12, UIKit.DIM))
	for i in Run.SLOT_COUNT:
		var info := Run.slot_info(i)
		if info.is_empty():
			_equipment.add_child(_row(UIKit.gem(Color(0.3, 0.26, 0.22), 1, true), "EMPTY SLOT", UIKit.DIM, [["Charms are slotted at the workbench in the base. Grafts found in the dungeon go into free slots.", UIKit.DIM]], Color(0.22, 0.18, 0.14)))
			continue
		var def: Dictionary = info["def"]
		var lines: Array = [[def["desc"], UIKit.TEXT]]
		var accent := UIKit.GOLD
		var tag := ""
		if info["kind"] == "graft":
			lines.append(["CURSE: %s" % def["curse"], UIKit.BAD])
			lines.append(["Locked until you die or visit a Cleansing Pool.", UIKit.DIM])
			accent = UIKit.CURSED
			tag = "  (GRAFT)"
		elif info["kind"] == "temp":
			lines.append(["Only for this run.", UIKit.DIM])
			accent = UIKit.RARE
			tag = "  (THIS RUN)"
		if info["fractured"]:
			lines.append(["FRACTURED: repair it at the workbench.", UIKit.BAD])
			tag = "  (FRACTURED)"
		_equipment.add_child(_row(UIKit.gem(def["color"], 1, info["fractured"], info["fractured"]), String(def["name"]).to_upper() + tag, UIKit.GOLD_BRIGHT, lines, accent))
	var form: Dictionary = RunData.FORMS[Run.form]
	var sword_lines: Array = [["%s: %s" % [String(form["name"]).to_upper(), form["desc"]], UIKit.TEXT]]
	if Run.module != &"":
		sword_lines.append(["MODULE: %s" % RunData.MODULES[Run.module]["desc"], UIKit.GOOD])
	_equipment.add_child(UIKit.label("WEAPON AND CANTEEN", 12, UIKit.DIM))
	_equipment.add_child(_row(UIKit.gem(Color(0.75, 0.78, 0.85), 3), "THE PRISONER'S SWORD", UIKit.GOLD_BRIGHT, sword_lines, UIKit.BORDER))
	_equipment.add_child(_row(UIKit.gem(Color(0.4, 0.9, 0.55), 1), "CANTEEN  %d / %d" % [Run.canteen, Run.canteen_max()], UIKit.GOLD_BRIGHT, [["Refilled at a safe room's extraction terminal or by a boon.", UIKit.DIM]], UIKit.BORDER))
	var stats := UIKit.label("", 12, UIKit.GOOD)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.text = "BONUSES:  " + (_total_stats_text() if _total_stats_text() != "" else "none yet")
	_equipment.add_child(stats)


func _fill_backpack() -> void:
	UIKit.clear(_backpack)
	var ash_row := HBoxContainer.new()
	ash_row.add_theme_constant_override("separation", 10)
	ash_row.add_child(UIKit.gem(Color(0.82, 0.8, 0.76), 0))
	var ash_box := VBoxContainer.new()
	ash_box.add_child(UIKit.label("ASH  %d" % Run.ash, 24, UIKit.GOLD_BRIGHT))
	ash_box.add_child(UIKit.label("fuel for the workbench; lost on death", 12, UIKit.DIM))
	ash_row.add_child(ash_box)
	_backpack.add_child(ash_row)
	_backpack.add_child(UIKit.label("CARRIED MATERIALS  (lost on death until extracted)", 12, UIKit.DIM))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_backpack.add_child(grid)
	var ids: Array = Run.carried.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return RunData.MATERIALS[a]["tier"] < RunData.MATERIALS[b]["tier"])
	for id: StringName in ids:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(112, 84)
		cell.add_theme_stylebox_override("panel", UIKit.slot_style(RunData.material_color(id).darkened(0.25)))
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(col)
		var gem := UIKit.gem(RunData.material_color(id), 0)
		gem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(gem)
		col.add_child(UIKit.label("x%d" % Run.carried[id], 16, UIKit.GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(UIKit.label(RunData.material_name(id).to_upper(), 8, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		grid.add_child(cell)
	if ids.is_empty():
		_backpack.add_child(UIKit.label("Nothing yet. Elites, bosses and cursed rooms drop materials.", 12, UIKit.DIM))
	_backpack.add_child(UIKit.label("BLUEPRINTS CARRIED", 12, UIKit.DIM))
	if Run.carried_blueprints.is_empty():
		_backpack.add_child(UIKit.label("none", 12, UIKit.DIM))
	for bp: StringName in Run.carried_blueprints:
		var info: Dictionary = RunData.BLUEPRINTS[bp]
		_backpack.add_child(UIKit.label("%s  (extract to keep it)" % String(info["name"]).to_upper(), 12, UIKit.LEGEND))
	if Run.echoes > 0:
		_backpack.add_child(UIKit.label("MEMORY ECHO x%d  (reveals a floor's map)" % Run.echoes, 12, Color(0.6, 0.85, 1.0)))
	if Run.blood_debt > 0:
		_backpack.add_child(UIKit.label("BLOOD DEBT %d: healing repays it before you recover" % Run.blood_debt, 12, UIKit.BAD))


# ------------------------------------------------------------------ stat text

static func stats_text(stats: Dictionary) -> String:
	var parts: Array[String] = []
	for entry: Array in STAT_LINES:
		if stats.has(entry[0]):
			parts.append(format_stat(String(entry[0]), float(stats[entry[0]])))
	return ", ".join(parts) if not parts.is_empty() else "no bonuses"


func _total_stats_text() -> String:
	var parts: Array[String] = []
	for entry: Array in STAT_LINES:
		var value := Run.stat(StringName(entry[0]))
		if absf(value) > 0.0001:
			parts.append(format_stat(String(entry[0]), value))
	return ", ".join(parts)


static func format_stat(key: String, value: float) -> String:
	for entry: Array in STAT_LINES:
		if entry[0] == key:
			var number := "%+d%%" % int(round(value * 100.0)) if entry[2] == "pct" else "%+d" % int(round(value))
			return "%s %s" % [number, entry[1]]
	return key
