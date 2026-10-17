extends PanelContainer
## One hand's loadout card (scenes/ui/hand_card.tscn).
## Shows the equipped module (icon, name, cost), the queue of modules a cycle
## will bring up next, and reacts to Q / E: a quick flash when the module
## changes, a red key badge when there is not enough Flux to switch.

const Glyphs := preload("res://scripts/ui/weapon_glyphs.gd")
const DENIED := Color(0.9, 0.3, 0.3)
const TITLES := ["RIGHT HAND // %s", "LEFT HAND // %s"]
const FIRE := [&"fire", &"fire_left"]
const ACTIONS := ["rotate_right", "rotate_left"]

## 0 = right hand (LMB / E), 1 = left hand (RMB / Q) - same as the game's hand index.
@export_enum("Right hand:0", "Left hand:1") var hand: int = 0

@onready var _title: Label = %HandTitle
@onready var _badge: PanelContainer = %CycleKeyBadge
@onready var _key: Label = %KeyLabel
@onready var _active_panel: PanelContainer = %ActiveSlotPanel
@onready var _icon_frame: PanelContainer = %IconFrame
@onready var _icon: TextureRect = %WeaponIcon
@onready var _glyph: Polygon2D = %FallbackGlyph
@onready var _veil: ProgressBar = %CooldownVeil
@onready var _name: Label = %ActiveName
@onready var _meta: Label = %ActiveMeta
@onready var _queue: HBoxContainer = %QueueHBox

const GREY := Color(0.38, 0.4, 0.42)

var _grey: float = 0.0
var _slot_style: StyleBoxFlat
var _badge_style: StyleBoxFlat
var _last_slot: int = -2
var _last_id: String = "?"
var _flash_tween: Tween
var _deny_tween: Tween


func _ready() -> void:
	_slot_style = _active_panel.get_theme_stylebox("panel") as StyleBoxFlat
	_badge_style = _badge.get_theme_stylebox("panel") as StyleBoxFlat


## Called every frame by the HUD while a local player exists.
func refresh(lp: Node, free_switch: bool) -> void:
	var f: FluxComponent = lp.flux
	var slots: Array = lp.slot_ids[hand]
	var cur: int = f.slot_of(hand)
	var id: String = ""
	if cur >= 0 and cur < slots.size():
		id = String(slots[cur])

	if cur != _last_slot or id != _last_id:
		var first: bool = _last_slot == -2
		_last_slot = cur
		_last_id = id
		_show_module(id)
		if not first:
			_flash()
	_update_queue(slots, cur)
	_title.text = TITLES[hand] % ControlHints.key(FIRE[hand])
	_key.text = "%s  %s" % [ControlHints.key(ACTIONS[hand]), "FREE" if free_switch else "CYCLE"]

	# arm hit = hand disabled; held button = brighter card
	var off: bool = f.hand_off(hand)
	_active_panel.self_modulate = Color(1.0, 0.45, 0.45) if off else (Color(1.25, 1.25, 1.25) if lp.cmd.fire_held[hand] else Color.WHITE)
	# grey veil over the icon: full right after use, wipes away as the cooldown runs out
	var mod: Module = lp.active_module(hand)
	var target: float = 1.0 if off else (mod.cooldown_ratio() if mod != null else 0.0)
	# the wipe follows the timer exactly; the icon colour fades toward grey / back smoothly
	_veil.value = target * 100.0
	_grey = move_toward(_grey, target, get_process_delta_time() * 6.0)
	var tint: Color = Color.WHITE.lerp(GREY, _grey)
	_icon.modulate = tint
	_glyph.modulate = tint
	if off:
		_meta.text = "ARM DISABLED"
	elif id != "":
		_meta.text = Loadout.hud_meta_of(id)

	# not enough Flux to cycle
	if GameState.phase == GameState.Phase.LIVE and not f.ejected and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_action_just_pressed(ACTIONS[hand]) and f.active_flux < FluxComponent.SWITCH_COST \
			and _queue_count(slots) > 0:
		_deny()


func _show_module(id: String) -> void:
	var col: Color = Loadout.color_of(id)
	if id == "":
		_name.text = "EMPTY"
		_meta.text = "NO MODULE"
	else:
		_name.text = Loadout.get_data(id).display_name.to_upper()
		_meta.text = Loadout.hud_meta_of(id)
	_meta.add_theme_color_override("font_color", col)
	_slot_style.border_color = col
	_badge_style.bg_color = col
	_glyph.color = Color(col.r, col.g, col.b, 0.9)
	_glyph.polygon = Glyphs.shape_of(id)
	var tex: Texture2D = Glyphs.texture_of(id)
	_icon.texture = tex
	_glyph.visible = tex == null


func _queue_count(slots: Array) -> int:
	var n: int = 0
	for s in slots:
		if String(s) != "":
			n += 1
	return n - 1


func _update_queue(slots: Array, cur: int) -> void:
	# the modules a cycle brings up next, in rotation order (empty slots are skipped)
	var upcoming: Array = []
	for i in range(1, slots.size()):
		var s: int = (cur + i) % slots.size()
		if String(slots[s]) != "":
			upcoming.append(s)
	for i in _queue.get_child_count():
		var pill: PanelContainer = _queue.get_child(i)
		var lab: Label = pill.get_node("Label")
		if i < upcoming.size():
			var s: int = upcoming[i]
			var id: String = String(slots[s])
			lab.text = "%d. %s" % [s + 1, Loadout.get_data(id).display_name]
			lab.add_theme_color_override("font_color", Loadout.color_of(id).lerp(Color.WHITE, 0.35))
			pill.modulate = Color.WHITE
		else:
			lab.text = "--"
			lab.add_theme_color_override("font_color", Color(0.35, 0.45, 0.5))
			pill.modulate = Color(1, 1, 1, 0.45)


func _flash() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_active_panel.modulate = Color(1.4, 1.4, 1.4, 1.0)
	_icon_frame.scale = Vector2(0.85, 0.85)
	_flash_tween = create_tween().set_parallel(true)
	_flash_tween.tween_property(_active_panel, "modulate", Color.WHITE, 0.12)
	_flash_tween.tween_property(_icon_frame, "scale", Vector2.ONE, 0.12)


func _deny() -> void:
	if _deny_tween != null:
		_deny_tween.kill()
	_badge.modulate = DENIED
	_deny_tween = create_tween()
	_deny_tween.tween_interval(0.12)
	_deny_tween.tween_property(_badge, "modulate", Color.WHITE, 0.25)
