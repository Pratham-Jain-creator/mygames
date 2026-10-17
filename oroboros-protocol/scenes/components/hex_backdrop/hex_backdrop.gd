class_name HexBackdrop
extends Control
## Faint cascading hex codes + a waveform graph that react to the current
## Bandwidth multiplier (`intensity` 0..1). Purely decorative information density.

@export var column_count := 22
@export var base_alpha := 0.07
## Faint game emblem behind everything. Kept very low so it never competes with UI.
@export var emblem_alpha := 0.09
## Colour of the falling hex numbers and of the waveform (the Server screen turns them red).
@export var tint := Color(0.4, 0.99, 0.945)
@export var wave_tint := Color(1.0, 0.706, 0.0)
@export var speed_scale := 1.0   # fall speed multiplier (Sentinel Servers are faster)
@export var font_size := 14
const EMBLEM_PATH := "res://assets/gameIcon/ouroboros_dragon_icon.png"
var _emblem: Texture2D

var intensity := 0.0:
	set(v):
		intensity = clampf(v, 0.0, 1.0)
var _cols: Array = []
var _time := 0.0
var _accum := 0.0
const REDRAW_STEP := 1.0 / 20.0   # decorative: 20 fps is plenty and saves a lot of CPU


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(EMBLEM_PATH):
		_emblem = load(EMBLEM_PATH)
	set_columns(column_count)


## (Re)builds the falling columns. Sentinel Servers use more of them.
func set_columns(n: int) -> void:
	column_count = n
	_cols.clear()
	for i in column_count:
		_cols.append({
			"x": float(i) / column_count,
			"y": randf(),
			"speed": randf_range(0.03, 0.12),
			"len": randi_range(4, 9),
			"seed": randi(),
			"txt": [],
		})
		_rebuild_text(_cols[i])


func _rebuild_text(c: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = c.seed
	var t: Array = []
	for k in int(c.len):
		t.append("%02X" % rng.randi_range(0, 255))
	c.txt = t


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta * (1.0 + intensity * 3.0)
	for c in _cols:
		c.y += c.speed * speed_scale * delta * (1.0 + intensity * 4.0)
		if c.y > 1.2:
			c.y = -0.3
			c.seed = randi()
			_rebuild_text(c)
	_accum += delta
	if _accum >= REDRAW_STEP:
		_accum = 0.0
		queue_redraw()


func _draw() -> void:
	if _emblem != null:
		# slow 'breathing' fade (~14s cycle), a touch brighter with high Overclock
		var breathe := 0.75 + 0.25 * sin(_time * 0.45)
		var a_e := (emblem_alpha + intensity * 0.04) * breathe
		var d := minf(size.x, size.y) * 0.95
		var r := Rect2((size - Vector2(d, d)) * 0.5, Vector2(d, d))
		draw_texture_rect(_emblem, r, false, Color(1, 1, 1, a_e))
	var font := ThemeDB.fallback_font
	var fs := font_size
	var a := base_alpha + intensity * 0.12
	for c in _cols:
		for k in int(c.len):
			var y: float = (c.y - k * 0.03) * size.y
			if y < -fs or y > size.y + fs:
				continue   # off-screen glyphs are not drawn
			var txt: String = c.txt[k]
			var fade := 1.0 - float(k) / float(c.len)
			draw_string(font, Vector2(c.x * size.x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tint.r, tint.g, tint.b, a * fade))
	# waveform along the lower edge
	var pts := PackedVector2Array()
	var amp := 10.0 + intensity * 40.0
	var base_y := size.y * 0.93
	for i in 48:
		var t := float(i) / 47.0
		pts.append(Vector2(t * size.x, base_y + sin(t * 18.0 + _time * 2.0) * amp * 0.5 + sin(t * 41.0 - _time * 3.0) * amp * 0.3))
	draw_polyline(pts, Color(wave_tint.r, wave_tint.g, wave_tint.b, 0.05 + intensity * 0.12), 2.0, true)
