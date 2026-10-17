class_name ShopListing
extends InteractiveControl
const MoneyIcon := preload("res://scripts/logic/money_icon.gd")
## A wide "rack row" used for Black Market stock, owned Daemons and
## consumables. Selecting a row shows its details in the shop's detail pane.

@export var compact := false

var payload: Dictionary = {}     # free-form data owned by the screen
var selected := false
var sold := false
var _tip: Dictionary = {}

@onready var _stripe: ColorRect = %Stripe
@onready var _frame: Panel = %Frame
@onready var _kind_label: Label = %KindLabel
@onready var _name_label: Label = %NameLabel
@onready var _price_label: Label = %PriceLabel
@onready var _desc_label: RichTextLabel = %DescLabel


func _ready() -> void:
	super()
	if compact:
		custom_minimum_size = Vector2(0, 40)
		_desc_label.visible = false
		_kind_label.visible = false
		_name_label.offset_top = 6.0
		_name_label.offset_bottom = 36.0
		_name_label.add_theme_font_size_override("font_size", 17)


func setup(kind_text: String, item_name: String, price_text: String, color: Color, tip: Dictionary, affordable := true) -> void:
	_kind_label.text = kind_text
	_kind_label.add_theme_color_override("font_color", color)
	_name_label.text = item_name
	MoneyIcon.apply(_price_label, price_text)
	_price_label.add_theme_color_override("font_color", Enums.COL_MONEY if affordable else Enums.COL_ICE)
	_stripe.color = color
	_frame.self_modulate = color
	_tip = tip
	set_idle(not tip.is_empty() and not sold, color, 0.8)
	# One-line summary on the row itself so players can compare stock at a glance.
	var rx := RegEx.create_from_string("\\[/?[^\\]]*\\]")
	_desc_label.text = Fmt.rich(rx.sub(String(tip.get("body", "")), "", true).replace("\n", " "))


func set_empty(text: String) -> void:
	setup("", text, "", Enums.COL_DIM, {})
	_name_label.add_theme_color_override("font_color", Enums.COL_DIM)


func set_selected(v: bool) -> void:
	if selected == v:
		return
	selected = v
	play_anim(&"select" if v else &"deselect")


func set_sold(v: bool) -> void:
	sold = v
	if v:
		set_idle(false)
		MoneyIcon.apply(_price_label, "SOLD")
		_price_label.add_theme_color_override("font_color", Enums.COL_DIM)
		play_anim(&"sold")


func get_tip_data() -> Dictionary:
	return _tip


# Installed-Daemon rows in the Black Market can be dragged to reorder.
func _get_drag_data(_at: Vector2) -> Variant:
	if payload.get("type", "") != "daemon":
		return null
	is_pressed = false
	_press_timer.stop()
	TooltipService.hide_for(self)
	_hover_animation(false)
	var box := PanelContainer.new()
	var l := Label.new()
	l.text = "  %s  " % _name_label.text
	l.add_theme_color_override("font_color", Enums.COL_DAEMON)
	box.add_child(l)
	set_drag_preview(box)
	AudioService.play("tick", 1.1)
	return {"daemon_drag": RunState.daemons.find(payload.inst)}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if payload.get("type", "") != "daemon" or not (data is Dictionary and data.has("daemon_drag")):
		return false
	return int(data.daemon_drag) != RunState.daemons.find(payload.inst)


func _drop_data(_at: Vector2, data: Variant) -> void:
	if RunState.move_daemon(int(data.daemon_drag), RunState.daemons.find(payload.inst)):
		AudioService.play("click", 0.9)
