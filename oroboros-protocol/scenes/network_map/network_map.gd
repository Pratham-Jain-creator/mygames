extends BaseScreen
const MoneyIcon := preload("res://scripts/logic/money_icon.gd")
## Shows the 3 Servers of the current Network and lets the player review their
## rig (deck, Daemons, consumables) before connecting.

const SERVER_CARD := preload("res://scenes/components/server_card/server_card.tscn")
const DAEMON_CARD := preload("res://scenes/components/daemon_card/daemon_card.tscn")
const LISTING := preload("res://scenes/components/shop_listing/shop_listing.tscn")

@onready var _title: Label = %TitleLabel
@onready var _money: Label = %MoneyLabel
@onready var _cards: HBoxContainer = %Cards
@onready var _rig: Label = %RigLabel
@onready var _deck_btn: ActionButton = %DeckButton
@onready var _connect: ActionButton = %ConnectButton
@onready var _daemon_rack: HBoxContainer = %DaemonRack
@onready var _consumables: VBoxContainer = %ConsumableBox
@onready var _anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	super()
	_title.text = "NETWORK %d / %d" % [RunState.network, RunState.FINAL_NETWORK]
	MoneyIcon.apply(_money, "Ø%d" % RunState.money)
	EventBus.money_changed.connect(func(v): MoneyIcon.apply(_money, "Ø%d" % v))
	var boss: String = RunState.boss_for(RunState.network)
	for k in 3:
		var card: ServerCard = SERVER_CARD.instantiate()
		_cards.add_child(card)
		var state := ServerCard.State.LOCKED
		if k < RunState.server_index:
			state = ServerCard.State.CLEARED
		elif k == RunState.server_index:
			state = ServerCard.State.CURRENT
		card.show_server(RunState.network, k, boss if k == 2 else "", state)
		# Clicking the Server you can enter = pressing CONNECT. Other cards never connect.
		card.activated.connect(_on_server_card.bind(state))
	_deck_btn.activated.connect(func(_s): open_deck_tracker())
	_connect.activated.connect(func(_s): SceneManager.go(SceneManager.SERVER))
	_connect.set_tip("CONNECT", "Jump into the next Server. There is no turn limit: reach the Threshold before your Tailbytes run out. Clearing within %d turns pays a FAST-CLEAR bonus." % ServerLogic.bonus_turn_limit())
	EventBus.daemons_changed.connect(_build_rig)
	EventBus.consumables_changed.connect(_build_rig)
	EventBus.deck_changed.connect(_build_rig)
	_build_rig()
	_anim.play(&"intro")


func _on_server_card(_src: InteractiveControl, state: int) -> void:
	match state:
		ServerCard.State.CURRENT:
			SceneManager.go(SceneManager.SERVER)
		ServerCard.State.CLEARED:
			show_toast("SERVER ALREADY CLEARED", Enums.COL_DIM)
		_:
			show_toast("LOCKED: CLEAR THE PREVIOUS SERVER FIRST", Enums.COL_DIM)


func _build_rig() -> void:
	_rig.text = "INTEGRITY  %d / %d   |   TAILBYTES %d NODES   |   STASH SLOTS %d   |   EJECTS %d" % [
		RunState.health, RunState.get_max_health(), RunState.deck.size(),
		RunState.get_stash_capacity(), RunState.get_flee_limit()]
	for c in _daemon_rack.get_children():
		c.queue_free()
	for i in RunState.MAX_DAEMONS:
		var dc: DaemonCard = DAEMON_CARD.instantiate()
		dc.slot_index = i
		_daemon_rack.add_child(dc)
		if i < RunState.daemons.size():
			dc.bind(RunState.daemons[i])
	for c in _consumables.get_children():
		c.queue_free()
	for i in RunState.get_max_consumables():
		var row: ShopListing = LISTING.instantiate()
		row.compact = true
		_consumables.add_child(row)
		if i < RunState.consumables.size():
			var item: Dictionary = RunState.consumables[i]
			var info := ItemDB.get_item(item.kind, item.id)
			var col: Color = Enums.KIND_COLORS[item.kind]
			row.setup(Enums.KIND_NAMES[item.kind], info.name, "USE", col,
				{"title": info.name, "body": info.desc, "color": col})
			row.activated.connect(func(_s): await use_consumable(item))
		else:
			row.set_empty("[ EMPTY SLOT ]")
