extends Control
## The run panel under the health bar: ash, canteen flasks, the three charm slots, the memory echo, the sword form and
## any active buffs. Drawn in code (small icons), redrawn whenever the Run state changes.

const FONT: Font = preload("res://assets/fonts/PixelOperator8.ttf")
const GOLD := Color(0.93, 0.8, 0.45)
const DIM := Color(0.5, 0.45, 0.4)
const SLOT_SIZE: float = 30.0

var _player: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Run.changed.connect(queue_redraw)
	Run.ash_changed.connect(func(_a: int) -> void: queue_redraw())
	Run.canteen_changed.connect(queue_redraw)


## `player` provides the selected quick item (canteen / echo).
func bind(player: Node) -> void:
	_player = player
	if player != null and player.has_signal("quick_changed") and not player.quick_changed.is_connected(queue_redraw):
		player.quick_changed.connect(queue_redraw)


func _process(_delta: float) -> void:
	# the blood debt and the buff timers tick on their own
	if Run.blood_debt > 0 or not Run.timed_buffs.is_empty():
		queue_redraw()


func _text(pos: Vector2, text: String, color: Color = Color.WHITE, size: int = 16) -> void:
	draw_string_outline(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.9))
	draw_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw() -> void:
	var y := 0.0
	# --- ash
	var diamond := PackedVector2Array([Vector2(8, y), Vector2(16, y + 9), Vector2(8, y + 18), Vector2(0, y + 9)])
	draw_colored_polygon(diamond, Color(0.82, 0.8, 0.76))
	draw_circle(Vector2(6, y + 6), 2.0, Color(1, 1, 1, 0.8))
	_text(Vector2(24, y + 15), "%d" % Run.ash, Color(0.9, 0.88, 0.84))
	y += 28.0
	# --- canteen flasks
	var selected_canteen: bool = _player == null or not _player.has_method("selected_quick") or _player.selected_quick() == &"canteen"
	if selected_canteen:
		draw_rect(Rect2(-4, y - 3, 28.0 * float(maxi(Run.canteen_max(), 1)) + 6.0, 26.0), Color(0.93, 0.8, 0.45, 0.22))
		draw_rect(Rect2(-4, y - 3, 28.0 * float(maxi(Run.canteen_max(), 1)) + 6.0, 26.0), GOLD, false, 1.0)
	for i in Run.canteen_max():
		_draw_flask(Vector2(2.0 + 28.0 * float(i), y), i < Run.canteen)
	if Run.instant_canteen:
		_text(Vector2(28.0 * float(Run.canteen_max()) + 10.0, y + 15), "INSTANT", Color(0.6, 0.85, 1.0), 12)
	y += 32.0
	# --- charm slots
	for i in Run.SLOT_COUNT:
		_draw_slot(Vector2(2.0 + (SLOT_SIZE + 6.0) * float(i), y), i)
	if Run.echoes > 0:
		var echo_selected: bool = _player != null and _player.has_method("selected_quick") and _player.selected_quick() == &"echo"
		var origin := Vector2(2.0 + (SLOT_SIZE + 6.0) * 3.0 + 10.0, y)
		if echo_selected:
			draw_rect(Rect2(origin + Vector2(-4, -3), Vector2(86, 26)), Color(0.6, 0.85, 1.0, 0.2))
			draw_rect(Rect2(origin + Vector2(-4, -3), Vector2(86, 26)), Color(0.6, 0.85, 1.0), false, 1.0)
		draw_circle(origin + Vector2(9, 11), 7.0, Color(0.6, 0.85, 1.0, 0.9))
		draw_circle(origin + Vector2(7, 8), 2.0, Color(1, 1, 1, 0.9))
		_text(origin + Vector2(22, 16), "ECHO x%d" % Run.echoes, Color(0.7, 0.9, 1.0), 12)
	y += SLOT_SIZE + 10.0
	# --- sword form and module
	var form: Dictionary = RunData.FORMS[Run.form]
	var line := "WEAPON: %s" % String(form["name"]).to_upper()
	if Run.module != &"":
		line += "  +  %s" % String(RunData.MODULES[Run.module]["name"]).to_upper()
	_text(Vector2(0, y + 12), line, Color(0.8, 0.78, 0.7), 12)
	y += 20.0
	# --- states
	if Run.blood_debt > 0:
		_text(Vector2(0, y + 12), "BLOOD DEBT %d" % Run.blood_debt, Color(0.95, 0.3, 0.3), 12)
		y += 18.0
	if Run.shield:
		_text(Vector2(0, y + 12), "FORLORN SHIELD", Color(0.6, 0.85, 1.0), 12)
		y += 18.0
	for buff: Dictionary in Run.floor_buffs:
		_text(Vector2(0, y + 12), String(buff["name"]).to_upper(), Color(0.7, 0.95, 0.7), 12)
		y += 18.0
	for buff: Dictionary in Run.timed_buffs:
		_text(Vector2(0, y + 12), "%s  %d:%02d" % [String(buff["name"]).to_upper(), int(buff["left"]) / 60, int(buff["left"]) % 60], Color(0.7, 0.95, 0.7), 12)
		y += 18.0


func _draw_flask(pos: Vector2, full: bool) -> void:
	var glass := Color(0.75, 0.85, 0.9) if full else DIM
	var body := PackedVector2Array([pos + Vector2(6, 0), pos + Vector2(14, 0), pos + Vector2(14, 6), pos + Vector2(20, 18), pos + Vector2(0, 18), pos + Vector2(6, 6)])
	if full:
		draw_colored_polygon(PackedVector2Array([pos + Vector2(4.5, 10), pos + Vector2(15.5, 10), pos + Vector2(20, 18), pos + Vector2(0, 18)]), Color(0.4, 0.9, 0.55))
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, glass, 1.5)


func _draw_slot(pos: Vector2, index: int) -> void:
	var rect := Rect2(pos, Vector2(SLOT_SIZE, SLOT_SIZE))
	draw_rect(rect, Color(0.07, 0.05, 0.05, 0.85))
	var info := Run.slot_info(index)
	if info.is_empty():
		draw_rect(rect, Color(0.3, 0.26, 0.22), false, 1.0)
		return
	var border := GOLD
	if info["kind"] == "graft":
		border = Color(0.9, 0.25, 0.3)
	elif info["kind"] == "temp":
		border = Color(0.5, 0.85, 1.0)
	draw_rect(rect, border, false, 2.0)
	var color: Color = info["def"]["color"]
	if info["fractured"]:
		color = color.darkened(0.6)
	var center := pos + rect.size * 0.5
	draw_circle(center, 8.0, color)
	draw_circle(center + Vector2(-2.5, -2.5), 2.5, Color(1, 1, 1, 0.55))
	if info["kind"] == "graft":
		draw_line(center + Vector2(-9, 9), center + Vector2(9, -9), Color(0.9, 0.2, 0.25, 0.9), 2.0)
	if info["fractured"]:
		draw_line(pos + Vector2(4, 4), pos + rect.size - Vector2(4, 4), Color(1, 0.3, 0.3), 2.0)
		draw_line(pos + Vector2(rect.size.x - 4, 4), pos + Vector2(4, rect.size.y - 4), Color(1, 0.3, 0.3), 2.0)
