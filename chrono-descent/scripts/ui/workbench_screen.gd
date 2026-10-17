class_name WorkbenchScreen
extends CanvasLayer
## The Biomechanical Workbench in the base (laid out like the Crafting window of the UI sheet). Three tabs:
##   CRAFT    categories on the left, recipes in the middle, the selected recipe's ingredients and a CRAFT button on the
##            right. Armor needs its blueprint; everything needs materials and ASH, which is the workbench's fuel.
##   LOADOUT  wear an armor set, put forged charms into the armor's three slots, repair fractured charms.
##   STASH    what you have banked: materials, ash, blueprints.
## Everything here uses the STASH (what you extracted), never what you are carrying.

const TABS: Array = [["craft", "CRAFT"], ["loadout", "LOADOUT"], ["stash", "STASH"]]
const CATEGORIES: Array = [["armor", "ARMOR"], ["charm", "CHARMS"], ["echo", "SUPPLIES"]]

var _player: Node
var _open: bool = false
var _tab: String = "craft"
var _category: String = "charm"
var _selected: StringName = &""
var _content: Control
var _tab_row: HBoxContainer
var _footer: Label
var _first_focus: Control
## True at the Chrono-Sanctuary's bench: you can swap armor and charms, but not craft.
var _loadout_only: bool = false


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
	var parts := UIKit.window("BIOMECHANICAL WORKBENCH", Vector2(1090, 590))
	parts["root"].position = Vector2(31, 28)
	add_child(parts["root"])
	var body: VBoxContainer = parts["body"]
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	body.add_child(_tab_row)
	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.custom_minimum_size = Vector2(1060, 430)
	body.add_child(_content)
	_footer = UIKit.label("", 12, UIKit.DIM)
	body.add_child(_footer)
	Run.changed.connect(func() -> void:
		if _open:
			_rebuild(false))


func is_open() -> bool:
	return _open


func open(loadout_only: bool = false) -> void:
	if _open:
		return
	_open = true
	_loadout_only = loadout_only
	if loadout_only:
		_tab = "loadout"
	visible = true
	if is_instance_valid(_player):
		_player.set_input_locked(true)
	_rebuild(true)


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if is_instance_valid(_player):
		_player.set_input_locked(false)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("roll"):
		get_viewport().set_input_as_handled()
		close()
		return
	if not _loadout_only and (event.is_action_pressed("hotbar_next") or event.is_action_pressed("hotbar_prev")):
		var order: Array[String] = ["craft", "loadout", "stash"]
		var step := 1 if event.is_action_pressed("hotbar_next") else -1
		_set_tab(order[posmod(order.find(_tab) + step, order.size())])
		get_viewport().set_input_as_handled()
		return
	UIKit.ensure_focus(self, get_viewport())
	if UIKit.press_focused(event, get_viewport()):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open:
		UIKit.ensure_focus(self, get_viewport())


# ------------------------------------------------------------------ building

func _rebuild(focus_first: bool) -> void:
	# remember which button had focus (by its position) so a rebuild never throws a controller player back to the top
	var kept_index := -1
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _content.is_ancestor_of(focused):
		kept_index = _content.find_children("*", "Button", true, false).find(focused)
	UIKit.clear(_tab_row)
	for tab: Array in TABS:
		if _loadout_only and tab[0] != "loadout":
			continue
		var b := UIKit.button(tab[1])
		b.custom_minimum_size = Vector2(150, 34)
		if tab[0] == _tab:
			b.add_theme_stylebox_override("normal", UIKit.box(Color(0.24, 0.18, 0.11), UIKit.GOLD_BRIGHT, 2, 8))
		b.pressed.connect(_set_tab.bind(String(tab[0])))
		_tab_row.add_child(b)
	_tab_row.add_child(UIKit.label("   ASH (FUEL): %d" % Run.stash_ash, 16, UIKit.GOLD_BRIGHT))
	UIKit.clear(_content)
	_first_focus = null
	match _tab:
		"craft":
			_build_craft()
		"loadout":
			_build_loadout()
		_:
			_build_stash()
	_footer.text = "%s  CLOSE" % InputHints.get_action_hint(&"inventory")
	if focus_first and _first_focus != null:
		_first_focus.call_deferred("grab_focus")
	elif kept_index >= 0:
		var buttons := _content.find_children("*", "Button", true, false)
		if not buttons.is_empty():
			(buttons[mini(kept_index, buttons.size() - 1)] as Control).call_deferred("grab_focus")


func _set_tab(tab: String) -> void:
	_tab = tab
	_rebuild(true)


func _column(width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0)
	col.add_theme_constant_override("separation", 6)
	return col


func _remember_focus(b: Control) -> void:
	if _first_focus == null:
		_first_focus = b


## A wide button with a title, a smaller line below and a status word on the right.
func _list_button(title: String, subtitle: String, title_color: Color, status: String, status_color: Color, width: float) -> Button:
	var b := UIKit.button("")
	b.custom_minimum_size = Vector2(width, 50)
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.set_anchors_preset(Control.PRESET_FULL_RECT)
	left.offset_left = 10
	left.offset_top = 5
	left.add_theme_constant_override("separation", 1)
	var title_label := UIKit.label(title.to_upper(), 16, title_color)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.custom_minimum_size = Vector2(width - 160.0, 0)
	left.add_child(title_label)
	var sub_label := UIKit.label(subtitle, 12, UIKit.DIM)
	sub_label.clip_text = true
	sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_label.custom_minimum_size = Vector2(width - 24.0, 0)
	left.add_child(sub_label)
	b.add_child(left)
	var right := UIKit.label(status, 12, status_color, HORIZONTAL_ALIGNMENT_RIGHT)
	right.set_anchors_preset(Control.PRESET_FULL_RECT)
	right.offset_right = -10
	right.offset_top = 6
	b.add_child(right)
	return b


# ------------------------------------------------------------------ CRAFT

func _build_craft() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.add_child(row)
	var categories := _column(170)
	row.add_child(categories)
	for cat: Array in CATEGORIES:
		var b := UIKit.button(cat[1])
		b.custom_minimum_size = Vector2(170, 46)
		if cat[0] == _category:
			b.add_theme_stylebox_override("normal", UIKit.box(Color(0.24, 0.18, 0.11), UIKit.GOLD_BRIGHT, 2, 8))
		b.pressed.connect(func() -> void:
			_category = String(cat[0])
			_selected = &""
			_rebuild(true))
		categories.add_child(b)
		_remember_focus(b)
	var detail_holder := VBoxContainer.new()
	detail_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_holder.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var list := _column(400)
	scroll.add_child(list)
	var recipes: Array = RunData.RECIPES.filter(func(r: Dictionary) -> bool: return r["type"] == _category)
	for recipe: Dictionary in recipes:
		var info := RunData.recipe_info(recipe)
		var reason := Run.why_not(recipe)
		var status := "READY" if reason == "" else reason
		var color := UIKit.GOOD if reason == "" else (UIKit.DIM if reason == "ALREADY OWNED" else UIKit.BAD)
		var b := _list_button(String(info["name"]), LoadoutScreen.stats_text(info["stats"]) if info.has("stats") and not (info["stats"] as Dictionary).is_empty() else String(info["desc"]), info["color"], status, color, 396)
		b.pressed.connect(func() -> void:
			_selected = recipe["id"]
			_rebuild(false)
			_refocus_selected())
		b.focus_entered.connect(func() -> void:
			if _selected != recipe["id"]:
				_selected = recipe["id"]
				_fill_detail(detail_holder))
		b.set_meta("recipe_id", recipe["id"])
		list.add_child(b)
		_remember_focus(b)
	row.add_child(detail_holder)
	if _selected == &"" and not recipes.is_empty():
		_selected = recipes[0]["id"]
	_fill_detail(detail_holder)


func _refocus_selected() -> void:
	for node in _content.find_children("*", "Button", true, false):
		if node.has_meta("recipe_id") and node.get_meta("recipe_id") == _selected:
			node.call_deferred("grab_focus")
			return


func _fill_detail(holder: VBoxContainer) -> void:
	UIKit.clear(holder)
	var recipe := RunData.recipe_for(_selected)
	if recipe.is_empty():
		holder.add_child(UIKit.label("Choose something to craft.", 16, UIKit.DIM))
		return
	var info := RunData.recipe_info(recipe)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UIKit.gem(info["color"], 0 if recipe["type"] == "armor" else 1))
	var titles := VBoxContainer.new()
	titles.add_child(UIKit.label(String(info["name"]).to_upper(), 24, UIKit.GOLD_BRIGHT))
	titles.add_child(UIKit.label(String(recipe["type"]).to_upper(), 12, UIKit.DIM))
	head.add_child(titles)
	holder.add_child(head)
	var desc := UIKit.label(String(info["desc"]), 16, UIKit.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(desc)
	if info.has("stats") and not (info["stats"] as Dictionary).is_empty():
		var stats := UIKit.label(LoadoutScreen.stats_text(info["stats"]), 12, UIKit.GOOD)
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		holder.add_child(stats)
	holder.add_child(UIKit.label("INGREDIENTS", 12, UIKit.DIM))
	for id: StringName in recipe["cost"]:
		var have := int(Run.stash.get(id, 0))
		var need := int(recipe["cost"][id])
		holder.add_child(_ingredient_row(RunData.material_color(id), RunData.material_name(id), have, need))
	holder.add_child(_ingredient_row(Color(0.82, 0.8, 0.76), "Ash (fuel)", Run.stash_ash, int(recipe["ash"])))
	if recipe["type"] == "armor":
		var bp: StringName = info["blueprint"]
		var known := Run.blueprints.has(bp)
		holder.add_child(UIKit.label("REQUIRES: %s  %s" % [String(RunData.BLUEPRINTS[bp]["name"]).to_upper(), "(known)" if known else "(found in the dungeon: bosses, hidden rooms)"], 12, UIKit.GOOD if known else UIKit.BAD))
	var reason := Run.why_not(recipe)
	var craft := UIKit.button("CRAFT" if reason == "" else reason, 24)
	craft.custom_minimum_size = Vector2(320, 52)
	craft.disabled = reason != ""
	craft.pressed.connect(func() -> void:
		if Run.craft(recipe["id"]):
			GameManager.toast_requested.emit("CRAFTED %s" % String(info["name"]).to_upper(), null, UIKit.GOOD)
			Audio.play(preload("res://assets/sounds/power_up.wav"), -6.0, 1.1))
	holder.add_child(craft)


func _ingredient_row(color: Color, label_text: String, have: int, need: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var gem := UIKit.gem(color, 0)
	gem.custom_minimum_size = Vector2(26, 26)
	row.add_child(gem)
	var name_label := UIKit.label(label_text.to_upper(), 16, UIKit.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(UIKit.label("%d / %d" % [have, need], 16, UIKit.GOOD if have >= need else UIKit.BAD, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


# ------------------------------------------------------------------ LOADOUT

func _build_loadout() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.add_child(row)
	# armor
	var armor_col := _column(330)
	row.add_child(armor_col)
	armor_col.add_child(UIKit.label("ARMOR SETS", 12, UIKit.DIM))
	for id: StringName in Run.owned_armor:
		var info: Dictionary = RunData.ARMOR[id]
		var worn: bool = id == Run.armor
		var b := _list_button(String(info["name"]), LoadoutScreen.stats_text(info["stats"]), info["color"], "WORN" if worn else "WEAR", UIKit.GOOD if worn else UIKit.GOLD, 326)
		b.pressed.connect(func() -> void: Run.equip_armor(id))
		armor_col.add_child(b)
		_remember_focus(b)
	# forged charms
	var charm_col := _column(360)
	row.add_child(charm_col)
	charm_col.add_child(UIKit.label("FORGED CHARMS", 12, UIKit.DIM))
	if Run.forged.is_empty():
		charm_col.add_child(UIKit.label("Craft charms in the CRAFT tab.", 12, UIKit.DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	charm_col.add_child(scroll)
	var list := _column(350)
	scroll.add_child(list)
	for i in Run.forged.size():
		var entry: Dictionary = Run.forged[i]
		var def: Dictionary = RunData.CHARMS[entry["id"]]
		var slotted := Run.is_slotted(i)
		var fractured := bool(entry["fractured"])
		var status := "FRACTURED: REPAIR" if fractured else ("REMOVE" if slotted else "SLOT IT")
		var b := _list_button(String(def["name"]), String(def["desc"]), def["color"], status, UIKit.BAD if fractured else (UIKit.GOLD if not slotted else UIKit.GOOD), 346)
		var index := i
		b.pressed.connect(func() -> void: _charm_pressed(index))
		list.add_child(b)
		_remember_focus(b)
	# slots
	var slot_col := _column(330)
	row.add_child(slot_col)
	slot_col.add_child(UIKit.label("CHARM SLOTS (3 PER ARMOR)", 12, UIKit.DIM))
	for i in Run.SLOT_COUNT:
		var info := Run.slot_info(i)
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(326, 70)
		var accent: Color = UIKit.CURSED if (not info.is_empty() and info["kind"] == "graft") else UIKit.BORDER
		panel.add_theme_stylebox_override("panel", UIKit.slot_style(accent))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		panel.add_child(line)
		if info.is_empty():
			line.add_child(UIKit.gem(Color(0.3, 0.26, 0.22), 1, true))
			line.add_child(UIKit.label("EMPTY", 16, UIKit.DIM))
		else:
			line.add_child(UIKit.gem(info["def"]["color"], 1, info["fractured"], info["fractured"]))
			var t := VBoxContainer.new()
			t.add_child(UIKit.label(String(info["def"]["name"]).to_upper(), 16, UIKit.GOLD_BRIGHT))
			var d := UIKit.label(String(info["def"]["desc"]), 12, UIKit.TEXT)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size = Vector2(230, 0)
			t.add_child(d)
			line.add_child(t)
		slot_col.add_child(panel)


func _charm_pressed(index: int) -> void:
	var entry: Dictionary = Run.forged[index]
	if bool(entry["fractured"]):
		if Run.repair(index):
			GameManager.toast_requested.emit("REPAIRED", null, UIKit.GOOD)
		else:
			var cost := Run.repair_cost(index)
			GameManager.toast_requested.emit("REPAIR NEEDS 1 %s AND %d ASH" % [RunData.material_name(cost["material"]).to_upper(), cost["ash"]], null, UIKit.BAD)
		return
	if Run.is_slotted(index):
		for i in Run.SLOT_COUNT:
			var slot = Run.slots[i]
			if slot != null and slot["kind"] == "forged" and int(slot["ref"]) == index:
				Run.clear_slot(i)
		return
	var free := Run.free_slot()
	if free < 0:
		GameManager.toast_requested.emit("ALL THREE SLOTS ARE FULL", null, UIKit.BAD)
		return
	Run.slot_forged(index, free)


# ------------------------------------------------------------------ STASH

func _build_stash() -> void:
	var col := _column(1040)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.add_child(col)
	col.add_child(UIKit.label("BANKED MATERIALS  (kept if you die)", 12, UIKit.DIM))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for id: StringName in RunData.MATERIALS:
		var count := int(Run.stash.get(id, 0))
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(124, 96)
		cell.add_theme_stylebox_override("panel", UIKit.slot_style(RunData.material_color(id).darkened(0.3) if count > 0 else Color(0.2, 0.17, 0.13)))
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(v)
		var gem := UIKit.gem(RunData.material_color(id), 0, count == 0)
		gem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(gem)
		v.add_child(UIKit.label("x%d" % count, 16, UIKit.GOLD_BRIGHT if count > 0 else UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UIKit.label(RunData.material_name(id).to_upper(), 8, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		grid.add_child(cell)
	col.add_child(UIKit.label("BLUEPRINTS KNOWN", 12, UIKit.DIM))
	if Run.blueprints.is_empty():
		col.add_child(UIKit.label("none yet: bosses drop one the first time you beat them.", 12, UIKit.DIM))
	for bp: StringName in Run.blueprints:
		col.add_child(UIKit.label(String(RunData.BLUEPRINTS[bp]["name"]).to_upper(), 16, UIKit.LEGEND))
	col.add_child(UIKit.label("MEMORY ECHOES: %d" % Run.echoes, 16, Color(0.6, 0.85, 1.0)))
	var back := UIKit.button("BACK TO THE CRAFT TAB")
	back.pressed.connect(_set_tab.bind("craft"))
	col.add_child(back)
	_remember_focus(back)
