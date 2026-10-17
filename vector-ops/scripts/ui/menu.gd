class_name Menu
extends Control
## Start screen (scenes/ui/menu.tscn). The layout, styles and the 3D character
## preview live in the scene. This script wires the slot buttons to the module
## picker, the presets and saved builds, shows the Flux readout, saves the
## profile (name + loadout) and starts the session.

const TEAM_COLOR := Color(0.25, 0.55, 1.0)

## Suggested loadouts: [right hand x4, left hand x4] of module ids ("" = empty).
const PRESETS := [
	{"name": "BRAWLER", "sel": [["kinetic", "edge", "boost", ""], ["aegis", "shift", "", ""]]},
	{"name": "SNIPER", "sel": [["bolt", "kinetic", "", ""], ["ghost", "shift", "", ""]]},
	{"name": "DEMOLITION", "sel": [["blast", "seeker", "", ""], ["bunker", "aegis", "", ""]]},
	{"name": "PHANTOM", "sel": [["kinetic", "seeker", "", ""], ["ghost", "shift", "boost", ""]]},
]

@onready var character: MenuCharacter = %Character

var slots: Array = [] # slots[hand][slot] = SlotButton (hand 0 = right / LMB)
var preset_buttons: Array = []
var _preset_normal: Array = [] # the scene's own "normal" style of each preset button


func _ready() -> void:
	slots = [
		[%SlotR1, %SlotR2, %SlotR3, %SlotR4],
		[%SlotL1, %SlotL2, %SlotL3, %SlotL4],
	]
	preset_buttons = [%BtnBrawler, %BtnSniper, %BtnDemolition, %BtnPhantom]

	for h in Loadout.HANDS:
		for s in Loadout.SLOTS_PER_HAND:
			var sb: SlotButton = slots[h][s]
			sb.set_module(GameState.local_loadout[h][s])
			sb.pressed.connect(func() -> void: %ModulePicker.open(h, s, selected_loadout()))
	%ModulePicker.chosen.connect(_on_module_chosen)

	for i in preset_buttons.size():
		var b: Button = preset_buttons[i]
		_preset_normal.append(b.get_theme_stylebox("normal"))
		b.pressed.connect(func() -> void: _apply_loadout(PRESETS[i]["sel"]))

	%Builds.save_requested.connect(func(n: String) -> void: %Builds.add_build(n, selected_loadout()))
	%Builds.load_requested.connect(_apply_loadout)

	%CallsignInput.text = GameState.local_name
	%CallsignInput.text_submitted.connect(func(_t: String) -> void: _persist())
	%CallsignInput.focus_exited.connect(_persist)
	%StatusLabel.text = ""
	GameState.connection_status.connect(func(m: String) -> void: %StatusLabel.text = m)

	for i in MapCatalog.count():
		%MapPicker.add_item(MapCatalog.label(i), i)
	%MapPicker.select(MapCatalog.clamp_index(GameState.local_map))
	%MapPicker.item_selected.connect(func(idx: int) -> void: GameState.local_map = idx)

	%BtnPlay.pressed.connect(func() -> void: %PlayDialog.visible = true)
	%BtnBots.pressed.connect(_on_bots_pressed)
	%BtnGuide.pressed.connect(func() -> void: %GuideDialog.visible = true)
	%BtnSettings.pressed.connect(func() -> void: %SettingsDialog.visible = true)
	%PlayDialog.host_requested.connect(_on_host_requested)
	%PlayDialog.join_requested.connect(_on_join_requested)

	character.set_team_color(TEAM_COLOR)
	character.update_motion(0.0) # idle pose
	_update_loadout_info()


func _process(delta: float) -> void:
	if visible:
		# the operator's head follows the cursor (offset from the centre of the preview box)
		var centre: Vector2 = %SubViewportContainer.get_global_rect().get_center()
		character.look_at_cursor((get_global_mouse_position() - centre) / (get_viewport_rect().size * 0.5), delta)
		_refresh_hints()


## Button names follow the device in use (keyboard / PlayStation / Xbox).
func _refresh_hints() -> void:
	%ControlsHint.text = ControlHints.summary()
	%RightSub.text = "%s  ·  rotate %s" % [ControlHints.key(&"fire"), ControlHints.key(&"rotate_right")]
	%LeftSub.text = "%s  ·  rotate %s" % [ControlHints.key(&"fire_left"), ControlHints.key(&"rotate_left")]


# --- loadout ---------------------------------------------------------------------

## The loadout currently shown in the slot buttons: [[4 ids], [4 ids]].
func selected_loadout() -> Array:
	var out: Array = []
	for h in Loadout.HANDS:
		var hand: Array = []
		for s in Loadout.SLOTS_PER_HAND:
			hand.append((slots[h][s] as SlotButton).module_id)
		out.append(hand)
	return out


func _on_module_chosen(hand: int, slot: int, id: String) -> void:
	(slots[hand][slot] as SlotButton).set_module(id)
	if id != "":
		character.react_to_module(hand, Loadout.category_of(id))
	_loadout_changed()


## Shows a whole loadout (preset or saved build) in the slot buttons.
func _apply_loadout(sel: Array) -> void:
	var clean: Array = Loadout.sanitize(sel)
	for h in Loadout.HANDS:
		for s in Loadout.SLOTS_PER_HAND:
			(slots[h][s] as SlotButton).set_module(clean[h][s])
	character.react_to_loadout()
	_loadout_changed()


func _loadout_changed() -> void:
	_update_loadout_info()
	_persist()


func _update_loadout_info() -> void:
	var sel := selected_loadout()
	var w: int = int(Loadout.total_weight(sel))
	var e: int = Loadout.empty_slots(sel)
	var mx: int = int(Loadout.max_flux(sel))
	%FluxValueLabel.text = str(mx)
	%FluxBar.value = mx
	%FormulaLabel.text = "100 - %d weight x 7 + %d empty x 3\n= %d  (min %d)" % [w, e, mx, int(Loadout.MIN_MAX_FLUX)]
	%Builds.set_active(sel)
	for i in preset_buttons.size():
		var b: Button = preset_buttons[i]
		var psel: Array = PRESETS[i]["sel"]
		b.text = "%s\nFlux %d" % [PRESETS[i]["name"], int(Loadout.max_flux(psel))]
		# the preset that matches the slots keeps its highlighted (hover) look
		var active: bool = sel == psel
		b.add_theme_stylebox_override("normal", b.get_theme_stylebox("hover") if active else _preset_normal[i])


# --- profile -------------------------------------------------------------------------

## Copies the menu state (loadout + callsign) into GameState and writes it to disk.
func _persist() -> void:
	GameState.local_loadout = selected_loadout()
	var n: String = %CallsignInput.text.strip_edges()
	GameState.local_name = n.substr(0, SaveData.NAME_MAX) if n != "" else "Operator"
	SaveData.save_all()


# --- starting a session ------------------------------------------------------------

## Play vs Bots goes straight into the match (no lobby step).
func _on_bots_pressed() -> void:
	_persist()
	GameState.solo_game()
	GameState.request_start()


func _on_host_requested() -> void:
	_persist()
	%PlayDialog.visible = false
	GameState.host_game()


func _on_join_requested(ip: String) -> void:
	_persist()
	%PlayDialog.visible = false
	GameState.join_game(ip)
