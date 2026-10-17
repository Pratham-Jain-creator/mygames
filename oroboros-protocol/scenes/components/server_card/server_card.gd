class_name ServerCard
extends InteractiveControl
## One of the three Servers of a Network on the Network Map.

enum State { LOCKED, CURRENT, CLEARED }

var _boss_id := ""
var _kind := 0

@onready var _top_bar: ColorRect = %TopBar
@onready var _frame: Panel = %Frame
@onready var _num_label: Label = %NumLabel
@onready var _kind_label: Label = %KindLabel
@onready var _quota_label: Label = %QuotaLabel
@onready var _reward_label: Label = %RewardLabel
@onready var _boss_label: Label = %BossLabel
@onready var _state_label: Label = %StateLabel


func show_server(network: int, kind: int, boss_id: String, state: State) -> void:
	_kind = kind
	_boss_id = boss_id
	var col: Color = [Enums.COL_DATA, Enums.COL_BREACH, Enums.COL_ICE][kind]
	_top_bar.color = col
	_frame.self_modulate = col
	_num_label.text = "SERVER %d-%d" % [network, kind + 1]
	_kind_label.text = Progression.KIND_NAMES[kind]
	_kind_label.add_theme_color_override("font_color", col)
	_quota_label.text = _big(Progression.quota_for(network, kind))
	_reward_label.text = "REWARD  Ø%d" % Progression.KIND_REWARD[kind]
	_boss_label.text = ("%s\n%s" % [BossDB.name_of(boss_id).to_upper(), BossDB.desc_of(boss_id)]) if boss_id != "" else ""
	match state:
		State.CLEARED:
			_state_label.text = "CLEARED"
			_state_label.add_theme_color_override("font_color", Enums.COL_COOLANT)
			play_anim(&"dimmed")
		State.CURRENT:
			_state_label.text = "NEXT TARGET"
			_state_label.add_theme_color_override("font_color", Color.WHITE)
			play_anim(&"current")
		_:
			_state_label.text = "LOCKED"
			_state_label.add_theme_color_override("font_color", Enums.COL_DIM)
			play_anim(&"dimmed")


func _hover_animation(hovered: bool) -> void:
	if _state_label.text == "NEXT TARGET":
		return
	play_anim(&"hover_in" if hovered else &"hover_out")


func get_tip_data() -> Dictionary:
	if _boss_id != "":
		return {"title": BossDB.name_of(_boss_id).to_upper(), "body": "Sentinel modifier:\n" + BossDB.desc_of(_boss_id), "color": Enums.COL_ICE}
	var texts := [
		"The baseline threshold for this Network. Clear it to earn Nullcoin (Ø) and visit the Black Market.",
		"Threshold is 1.5x the Proxy Server.",
	]
	return {"title": Progression.KIND_NAMES[_kind], "body": texts[mini(_kind, 1)], "color": _top_bar.color}


func _big(v: int) -> String:
	var s := str(v)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
