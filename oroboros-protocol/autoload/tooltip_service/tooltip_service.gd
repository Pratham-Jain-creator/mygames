extends CanvasLayer
## Autoload: the single shared tooltip. Controls ask for it through
## InteractiveControl (hover on PC, long-press on touch devices).
## data = {title: String, body: String (BBCode ok), color: Color}

@onready var panel: PanelContainer = %Panel
@onready var accent: ColorRect = %Accent
@onready var title_label: Label = %TitleLabel
@onready var body_label: RichTextLabel = %BodyLabel
@onready var anim: AnimationPlayer = $AnimationPlayer

var _owner: Control = null
var _ticket := 0


func show_for(target: Control, data: Dictionary) -> void:
	if data.is_empty():
		return
	_owner = target
	_ticket += 1
	var ticket := _ticket
	var col: Color = data.get("color", Enums.COL_DATA)
	title_label.text = String(data.get("title", ""))
	title_label.visible = title_label.text != ""
	title_label.add_theme_color_override("font_color", col)
	body_label.text = Fmt.rich(String(data.get("body", "")))
	accent.color = col
	anim.stop()
	panel.modulate.a = 0.0
	panel.visible = true
	panel.reset_size()
	await get_tree().process_frame
	await get_tree().process_frame
	if ticket != _ticket or not is_instance_valid(_owner):
		return
	panel.reset_size()
	_place()
	anim.play(&"show")


func hide_for(target: Control) -> void:
	if _owner == target:
		hide_now()


func hide_now() -> void:
	_ticket += 1
	_owner = null
	if panel.visible:
		anim.play(&"hide")


func _place() -> void:
	var r: Rect2 = _owner.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _owner.size)
	var vp := get_viewport().get_visible_rect().size
	var sz := panel.size
	var pos := Vector2(r.get_center().x - sz.x * 0.5, r.position.y - sz.y - 10.0)
	if pos.y < 8.0:
		pos.y = r.end.y + 10.0
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - sz.y - 8.0))
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - sz.x - 8.0))
	panel.position = pos
