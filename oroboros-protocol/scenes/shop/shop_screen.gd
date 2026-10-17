extends BaseScreen
const MoneyIcon := preload("res://scripts/logic/money_icon.gd")
## The Black Market: a server-rack of listings. Tap/click a row to inspect it in
## the Inspector, then press the action button (BUY / SELL / USE).

const LISTING := preload("res://scenes/components/shop_listing/shop_listing.tscn")

var _sel_key := ""
var _rows: Array = []        # every ShopListing currently on screen

@onready var _sub: Label = %SubLabel
@onready var _money: Label = %MoneyLabel
@onready var _listings_box: VBoxContainer = %ListingsBox
@onready var _rig_box: VBoxContainer = %RigBox
@onready var _kind: Label = %DetailKind
@onready var _name: Label = %DetailName
@onready var _body: RichTextLabel = %DetailBody
@onready var _action: ActionButton = %DetailAction
@onready var _reroll: ActionButton = %RerollButton
@onready var _purge: ActionButton = %PurgeButton
@onready var _deck_btn: ActionButton = %DeckButton
@onready var _leave: ActionButton = %LeaveButton
@onready var _anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	super()
	RunState.shop_rerolls = 0
	RunState.shop_free_reroll_used = false
	RunState.begin_shop_visit()
	RunState.shop_listings = ShopGenerator.generate()
	var pops := DaemonLogic.fire("shop_enter")
	for p in pops:
		show_toast("ADWARE installed free software", Enums.COL_DAEMON)
	_sub.text = "NETWORK %d  //  SERVER %d CLEARED  //  UNREGISTERED VENDORS, NO REFUNDS" % [
		RunState.network if RunState.server_index > 0 else maxi(RunState.network - 1, 1),
		RunState.server_index if RunState.server_index > 0 else 3]
	_action.activated.connect(func(_s): _on_action())
	_reroll.activated.connect(func(_s): _on_reroll())
	_purge.activated.connect(func(_s): _on_purge())
	_deck_btn.activated.connect(func(_s): open_deck_tracker())
	_leave.activated.connect(func(_s): _on_leave())
	_deck_btn.set_tip("TAILBYTES", "Inspect every Node you own, including modified ones.")
	EventBus.money_changed.connect(func(_v): _rebuild())
	EventBus.daemons_changed.connect(_rebuild)
	EventBus.consumables_changed.connect(_rebuild)
	_rebuild()
	_anim.play(&"intro")


# ------------------------------------------------------------------ build
func _rebuild() -> void:
	if not is_node_ready():
		return
	MoneyIcon.apply(_money, "Ø%d" % RunState.money)
	_rows.clear()
	_free_children(_listings_box)
	_free_children(_rig_box)

	_section(_listings_box, "DAEMONS  //  %d / %d SLOTS" % [RunState.daemons.size(), RunState.get_max_daemons()])
	for i in RunState.shop_listings.size():
		var l: Dictionary = RunState.shop_listings[i]
		if l.kind == Enums.ItemKind.DAEMON:
			_add_listing(l, i)
	_section(_listings_box, "SOFTWARE  //  %d / %d SLOTS" % [RunState.consumables.size(), RunState.get_max_consumables()])
	for i in RunState.shop_listings.size():
		var l: Dictionary = RunState.shop_listings[i]
		if l.kind in [Enums.ItemKind.EXECUTABLE, Enums.ItemKind.FIRMWARE, Enums.ItemKind.CORRUPTION]:
			_add_listing(l, i)
	_section(_listings_box, "ROOT ACCESS  //  PERMANENT  //  FIXED FOR NETWORK %d" % RunState.network)
	for i in RunState.shop_listings.size():
		var l: Dictionary = RunState.shop_listings[i]
		if l.kind == Enums.ItemKind.ROOT_ACCESS:
			_add_listing(l, i)

	_section(_rig_box, "INSTALLED DAEMONS (leftmost scores first)")
	for inst in RunState.daemons:
		var def := DaemonDB.get_def(inst.id)
		var row := _new_row(_rig_box, true)
		row.setup("DAEMON", def.name, "SELL Ø%d" % RunState.sell_value(inst), Enums.COL_DAEMON,
			{"title": def.name, "body": def.desc, "color": Enums.COL_DAEMON})
		row.payload = {"type": "daemon", "inst": inst, "key": "daemon:%d" % int(inst.uid)}
	if RunState.daemons.is_empty():
		_section(_rig_box, "  none installed")
	_section(_rig_box, "SOFTWARE")
	for i in RunState.consumables.size():
		var item: Dictionary = RunState.consumables[i]
		var info := ItemDB.get_item(item.kind, item.id)
		var col: Color = Enums.KIND_COLORS[item.kind]
		var row := _new_row(_rig_box, true)
		row.setup(Enums.KIND_NAMES[item.kind], info.name, "USE", col, {"title": info.name, "body": info.desc, "color": col})
		row.payload = {"type": "consumable", "item": item, "key": "cons:%d:%s" % [i, item.id]}
	if RunState.consumables.is_empty():
		_section(_rig_box, "  none held")
	if not RunState.vouchers.is_empty():
		_section(_rig_box, "ROOT ACCESS OWNED")
		for v in RunState.vouchers:
			var vi: Dictionary = ItemDB.ROOT_ACCESS[v]
			var row := _new_row(_rig_box, true)
			row.setup("ROOT", vi.name, "", Enums.COL_COOLANT, {"title": vi.name, "body": vi.desc, "color": Enums.COL_COOLANT})
			row.payload = {"type": "voucher", "key": "voucher:%s" % v}

	var rc := RunState.reroll_cost()
	_reroll.text = "RESTOCK  %s" % ("FREE" if rc == 0 else "Ø%d" % rc)
	_reroll.set_tip("RESTOCK", "Roll new Daemons and software. Voucher stock stays. Cost grows by Ø1 each time.")
	var pc := RunState.purge_cost()
	_purge.text = "PURGE NODE  Ø%d" % pc
	_purge.set_tip("PURGE NODE", "Permanently delete one Node from your Tailbytes (min %d). Thinner Tailbytes draw your good Nodes more often.%s" % [
		RunState.MIN_DECK_SIZE, "" if RunState.has_daemon("delete_key") else " Fee rises by Ø1 per purge."])
	_leave.text = "LEAVE MARKET"
	_restore_selection()


func _free_children(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


func _section(parent: Node, text: String) -> void:
	# Header: label plus a thin rule, so the rack reads as clear groups.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Enums.COL_DATA)
	box.add_child(l)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(Enums.COL_DATA, 0.35)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)


func _new_row(parent: Node, compact: bool) -> ShopListing:
	var row: ShopListing = LISTING.instantiate()
	row.compact = compact
	parent.add_child(row)
	row.activated.connect(_on_row_activated)
	_rows.append(row)
	return row


func _add_listing(l: Dictionary, index: int) -> void:
	var info := ItemDB.get_item(l.kind, l.id)
	var cost := ShopGenerator.cost_of(l)
	var col: Color = Enums.KIND_COLORS[l.kind]
	var kind_text: String = Enums.KIND_NAMES[l.kind]
	if l.kind == Enums.ItemKind.DAEMON:
		kind_text += "  //  " + Enums.RARITY_NAMES[info.rarity]
	var row := _new_row(_listings_box, false)
	row.setup(kind_text, info.name, "Ø%d" % cost, col, {"title": info.name, "body": info.desc, "color": col}, RunState.money >= cost)
	row.payload = {"type": "listing", "ref": l, "key": "listing:%d" % index}  # unique per slot: two identical items must not share a key
	if l.sold:
		row.set_sold(true)


# -------------------------------------------------------------- selection
func _on_row_activated(src: InteractiveControl) -> void:
	var row := src as ShopListing
	_sel_key = row.payload.get("key", "")
	for r in _rows:
		(r as ShopListing).set_selected(r == row)
	_show_detail(row.payload)


func _restore_selection() -> void:
	for r in _rows:
		if r.payload.get("key", "") == _sel_key and _sel_key != "":
			r.set_selected(true)
			_show_detail(r.payload)
			return
	_sel_key = ""
	_show_detail({})


func _show_detail(p: Dictionary) -> void:
	_action.disabled = true
	_action.text = "-"
	if p.is_empty():
		_kind.text = "INSPECTOR"
		_kind.add_theme_color_override("font_color", Enums.COL_DIM)
		_name.text = "Select a listing"
		_body.text = Fmt.rich("Tap or click any row on the rack to inspect it. Hover shows a quick description; selecting shows the full spec and unlocks the action button.")
		return
	match p.type:
		"listing":
			var l: Dictionary = p.ref
			var info := ItemDB.get_item(l.kind, l.id)
			var cost := ShopGenerator.cost_of(l)
			var col: Color = Enums.KIND_COLORS[l.kind]
			_kind.text = Enums.KIND_NAMES[l.kind] + (("  //  " + Enums.RARITY_NAMES[info.rarity]) if l.kind == Enums.ItemKind.DAEMON else "")
			_kind.add_theme_color_override("font_color", col)
			_name.text = info.name
			var extra := ""
			if l.kind == Enums.ItemKind.FIRMWARE and RunState.has_daemon("scalper"):
				extra = "\n\n[color=#FF00FF]Scalper: costs double, levels up twice.[/color]"
			_body.text = Fmt.rich(String(info.desc) + extra)
			if l.sold:
				_action.text = "SOLD"
			elif RunState.money < cost:
				_action.text = "NEED Ø%d" % cost
			elif l.kind == Enums.ItemKind.DAEMON and not RunState.can_add_daemon():
				_action.text = "NO FREE DAEMON SLOT"
			elif (l.kind == Enums.ItemKind.EXECUTABLE or l.kind == Enums.ItemKind.CORRUPTION) and not RunState.has_consumable_space():
				_action.text = "SOFTWARE SLOTS FULL"
			else:
				_action.text = "BUY  Ø%d" % cost
				_action.disabled = false
		"daemon":
			var inst: Dictionary = p.inst
			var def := DaemonDB.get_def(inst.id)
			_kind.text = "INSTALLED DAEMON  //  " + Enums.RARITY_NAMES[def.rarity]
			_kind.add_theme_color_override("font_color", Enums.COL_DAEMON)
			_name.text = def.name
			_body.text = Fmt.rich(String(def.desc))
			_action.text = "SELL  +Ø%d" % RunState.sell_value(inst)
			_action.disabled = false
		"consumable":
			var item: Dictionary = p.item
			var info := ItemDB.get_item(item.kind, item.id)
			_kind.text = "HELD  //  " + Enums.KIND_NAMES[item.kind]
			_kind.add_theme_color_override("font_color", Enums.KIND_COLORS[item.kind])
			_name.text = info.name
			_body.text = Fmt.rich(String(info.desc))
			_action.text = "USE"
			_action.disabled = false
		"voucher":
			var v := String(p.key).trim_prefix("voucher:")
			var vi: Dictionary = ItemDB.ROOT_ACCESS[v]
			_kind.text = "ROOT ACCESS  //  OWNED"
			_kind.add_theme_color_override("font_color", Enums.COL_COOLANT)
			_name.text = vi.name
			_body.text = Fmt.rich(String(vi.desc))
			_action.text = "ACTIVE"


# ----------------------------------------------------------------- actions
func _find_selected_row_payload() -> Dictionary:
	for r in _rows:
		if r.payload.get("key", "") == _sel_key:
			return r.payload
	return {}


func _on_action() -> void:
	var p := _find_selected_row_payload()
	if p.is_empty():
		return
	match p.type:
		"listing":
			_buy(p.ref)
		"daemon":
			var v := RunState.sell_daemon(p.inst)
			show_toast("SOLD FOR Ø%d" % v, Enums.COL_MONEY)
			AudioService.play("buy", 0.8)
			_sel_key = ""
		"consumable":
			await use_consumable(p.item)
			_sel_key = ""
			_rebuild()


func _buy(l: Dictionary) -> void:
	if l.sold:
		return
	var cost := ShopGenerator.cost_of(l)
	if RunState.money < cost:
		show_toast("NOT ENOUGH NULLCOIN", Enums.COL_ICE)
		AudioService.play("deny")
		return
	match l.kind:
		Enums.ItemKind.DAEMON:
			if not RunState.can_add_daemon():
				show_toast("NO FREE DAEMON SLOT - SELL ONE FIRST", Enums.COL_ICE)
				return
			RunState.money -= cost
			RunState.add_daemon(l.id)
			if RunState.has_daemon("black_market"):
				var junk := NodeData.new(Enums.NodeType.ICE, randi_range(6, 12))
				RunState.deck.add_node(junk)
				EventBus.deck_changed.emit()
			RunState.stats["daemons_bought"] = int(RunState.stats.get("daemons_bought", 0)) + 1
			show_toast("DAEMON INSTALLED: %s" % DaemonDB.get_def(l.id).name, Enums.COL_DAEMON)
		Enums.ItemKind.EXECUTABLE, Enums.ItemKind.CORRUPTION:
			if not RunState.has_consumable_space():
				show_toast("SOFTWARE SLOTS FULL - USE ONE FIRST", Enums.COL_ICE)
				return
			RunState.money -= cost
			RunState.add_consumable(l.kind, l.id)
			show_toast("ACQUIRED: %s" % ItemDB.get_item(l.kind, l.id).name, Enums.COL_DATA)
		Enums.ItemKind.FIRMWARE:
			RunState.money -= cost
			var times := 2 if RunState.has_daemon("scalper") else 1
			if RunState.has_daemon("hotfix") and not RunState.shop_hotfix_used:
				RunState.shop_hotfix_used = true
				times += 1
			RunState.level_up_sub(l.id, times)
			show_toast("%s LEVEL +%d" % [SubroutineDB.name_of(l.id).to_upper(), times], Enums.COL_BREACH)
		Enums.ItemKind.ROOT_ACCESS:
			RunState.money -= cost
			RunState.add_voucher(l.id)
			show_toast("ROOT ACCESS GRANTED: %s" % ItemDB.ROOT_ACCESS[l.id].name, Enums.COL_COOLANT)
	l.sold = true
	AudioService.play("buy")
	PostFX.glitch_small()
	_rebuild()


func _on_leave() -> void:
	var bonus := RunState.leave_shop()
	if bonus > 0:
		show_toast("LAYAWAY: +Ø%d" % bonus, Enums.COL_MONEY)
	SceneManager.go(SceneManager.NETWORK_MAP)


func _on_reroll() -> void:
	var cost := RunState.reroll_cost()
	if RunState.money < cost:
		show_toast("NOT ENOUGH NULLCOIN", Enums.COL_ICE)
		AudioService.play("deny")
		return
	if cost == 0:
		RunState.shop_free_reroll_used = true
	else:
		RunState.money -= cost
		RunState.shop_rerolls += 1
	RunState.shop_listings = ShopGenerator.reroll(RunState.shop_listings)
	_sel_key = ""
	AudioService.play("slam", 1.3)
	_rebuild()
	_anim.play(&"intro")


func _on_purge() -> void:
	var cost := RunState.purge_cost()
	if RunState.deck.size() <= RunState.MIN_DECK_SIZE:
		show_toast("TAILBYTES AT MINIMUM SIZE (%d)" % RunState.MIN_DECK_SIZE, Enums.COL_ICE)
		return
	if RunState.money < cost:
		show_toast("NOT ENOUGH NULLCOIN", Enums.COL_ICE)
		AudioService.play("deny")
		return
	var targets: Array = await deck_viewer.pick("PURGE: SELECT A NODE TO DELETE FOREVER (Ø%d)" % cost, 1, 1)
	if targets.is_empty():
		return
	if RunState.delete_node(targets[0]):
		RunState.money -= cost
		RunState.on_purged()
		RunState.purge_count += 1
		show_toast("NODE PURGED: %s" % targets[0].label(), Enums.COL_ICE)
		AudioService.play("break")
		_rebuild()
