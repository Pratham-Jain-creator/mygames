class_name NodeFace
extends Control
## The generic Node card body: outline shape, gradient fill, texture, border,
## halo, divider and value pips - all drawn in code from NodeStyle. One script
## serves every Node kind (Siphon / Glitch / Patch / Firewall) and the
## face-down cover (unknown = true). Set `kind`, `accent`, `value` and
## `selected`; it redraws itself.

const PIPS := 14
const BG_TOP := Color(0.075, 0.095, 0.125)
const BG_BOT := Color(0.035, 0.045, 0.06)

@export var unknown := false:
	set(v):
		unknown = v
		_rebuild()
var kind: int = Enums.NodeType.DATA
var accent: Color = Color.WHITE
var value := 0:
	set(v):
		value = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()

var divider := false:    # Glitch cards: thin line above the damage read-out
	set(v):
		divider = v
		queue_redraw()
var queue_order := 0:    # > 0 while selected: draws the QUEUE tab above the card
	set(v):
		queue_order = v
		queue_redraw()

var _poly := PackedVector2Array()
var _tex_dots := PackedVector2Array()
var _tex_lines: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild)
	_rebuild()


## One call sets the whole look.
func configure(k: int, col: Color, is_unknown: bool) -> void:
	var changed := k != kind or is_unknown != unknown
	kind = k
	accent = col
	unknown = is_unknown
	if not changed:
		queue_redraw()


func _shape_kind() -> int:
	return -1 if unknown else kind


func _rebuild() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	_poly = NodeStyle.shape(_shape_kind(), size)
	_tex_dots = PackedVector2Array()
	_tex_lines = []
	var tex: StringName = NodeStyle.TEX_NONE if unknown else NodeStyle.texture(kind)
	if tex != NodeStyle.TEX_NONE and NodeStyle.card_tex(kind, false) == null:
		_build_texture(tex)
	queue_redraw()


func _build_texture(tex: StringName) -> void:
	var w := size.x
	var h := size.y
	# Texture only fills the top 72% of the card, clipped to the outline.
	var band := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.72), Vector2(0, h * 0.72)])
	var clips := Geometry2D.intersect_polygons(_poly, band)
	if clips.is_empty():
		return
	var clip: PackedVector2Array = clips[0]
	var segs: Array = []
	match tex:
		NodeStyle.TEX_DOTS:
			var y := 8.0
			while y < h * 0.72:
				var x := 8.0
				while x < w:
					var p := Vector2(x, y)
					if Geometry2D.is_point_in_polygon(p, clip):
						_tex_dots.append(p)
					x += 11.0
				y += 11.0
			return
		NodeStyle.TEX_DIAG, NodeStyle.TEX_HATCH:
			var k := -h
			while k < w:
				segs.append([Vector2(k, h), Vector2(k + h, 0)])
				if tex == NodeStyle.TEX_HATCH:
					segs.append([Vector2(k, 0), Vector2(k + h, h)])
				k += 13.0
		NodeStyle.TEX_GRID:
			var gx := 0.0
			while gx < w:
				segs.append([Vector2(gx, 0), Vector2(gx, h)])
				gx += 14.0
			var gy := 0.0
			while gy < h:
				segs.append([Vector2(0, gy), Vector2(w, gy)])
				gy += 14.0
	for sg in segs:
		for piece in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([sg[0], sg[1]]), clip):
			_tex_lines.append(piece)


func _draw() -> void:
	var art: Texture2D = null if unknown else NodeStyle.card_tex(kind, selected)
	if art == null:
		_draw_procedural()      # face-down cover (and any kind without PNG art)
		return
	var k := size.x / NodeStyle.ART_BODY.x
	var w := size.x
	var h := size.y
	var col := accent
	draw_texture_rect(art, Rect2(Vector2(-NodeStyle.ART_PAD, -NodeStyle.ART_PAD) * k, art.get_size() * k), false)
	if selected and queue_order > 0:
		# QUEUE tab sitting on top of the card (text is the OrderLabel above it)
		var cx := w * 0.5
		var tab := PackedVector2Array([Vector2(cx - 46, 1), Vector2(cx - 37, -15), Vector2(cx + 37, -15), Vector2(cx + 46, 1)])
		draw_colored_polygon(tab, col)
	# role tag box (text is the RoleLabel)
	var rb := Rect2(w - 66, 14, 54, 17)
	draw_rect(rb, Color(col, 0.10))
	draw_rect(rb, Color(col, 0.75), false, 1.0)
	# value visualiser: vertical pip column on the right, lit from the bottom up.
	# 14 slots normally; above 14 (Encrypted) one pip per point, pitch shrinks to stay in the column.
	var lit := maxi(value, 0)
	var total := maxi(PIPS, lit)
	var pitch := minf(5.8, 82.0 / total)
	var ps := 0.31 * pitch / 5.8                      # pip texture scale
	var off_tex := NodeStyle.pip_tex(kind, false)
	var on_tex := NodeStyle.pip_tex(kind, true)
	var px := w - 26.0
	var bottom := 156.0
	for i in total:
		var t := on_tex if i < lit else off_tex
		var c := Vector2(px, bottom - i * pitch)
		var sz := t.get_size() * ps
		draw_texture_rect(t, Rect2(c - sz * 0.5, sz), false)
	if divider:
		var ly := 187.0
		draw_line(Vector2(26, ly), Vector2(w - 26, ly), Color(col, 0.6), 1.5)
		draw_rect(Rect2(24, ly - 2, 4, 4), Color(col, 0.9))
		draw_rect(Rect2(w - 28, ly - 2, 4, 4), Color(col, 0.9))


func _draw_procedural() -> void:
	if _poly.size() < 3:
		return
	var w := size.x
	var h := size.y
	var col: Color = Enums.COL_DIM if unknown else accent
	var closed := _poly.duplicate()
	closed.append(_poly[0])

	# halo behind the card
	var halo_a := 0.2 if selected else 0.07
	for i in 3:
		draw_polyline(closed, Color(col, halo_a * (1.0 - i * 0.3)), 12.0 - i * 4.0, true)

	# fill: dark gradient with a faint accent tint, brighter at the top
	var cols := PackedColorArray()
	for p in _poly:
		var t := clampf(p.y / h, 0.0, 1.0)
		var base := BG_TOP.lerp(BG_BOT, t)
		cols.append(base.lerp(col, (0.16 if selected else 0.10) * (1.0 - t * 0.7)))
	draw_polygon(_poly, cols)

	# texture
	var tcol := Color(col, 0.16)
	for p in _tex_dots:
		draw_circle(p, 1.0, tcol)
	var lcol := Color(col, 0.09)
	for piece in _tex_lines:
		draw_polyline(piece, lcol, 1.0)

	# border: bright at the top, fading toward the bottom; solid when selected
	var bcols := PackedColorArray()
	for p in closed:
		var t2 := clampf(p.y / h, 0.0, 1.0)
		bcols.append(Color(col, 1.0 if selected else lerpf(0.95, 0.5, t2)))
	draw_polyline_colors(closed, bcols, 3.0 if selected else 2.0, true)

	if selected and queue_order > 0 and not unknown:
		# QUEUE tab sitting on top of the card (text is the OrderLabel above it)
		var cx := w * 0.5
		var tab := PackedVector2Array([Vector2(cx - 44, 1), Vector2(cx - 35, -15), Vector2(cx + 35, -15), Vector2(cx + 44, 1)])
		draw_colored_polygon(tab, col)
	if unknown:
		return
	# value pips (lit count = value) replace the old divider line
	# Always one row: 14 pips normally; above 14 (e.g. Encrypted) there is one pip per point
	# and they get thinner so the whole row still fits.
	var lit := maxi(value, 0)
	var total := maxi(PIPS, lit)
	var gap := 3.0 if total <= PIPS else maxf(1.0, 3.0 * float(PIPS) / total)
	var avail := w - 32.0
	var pw := (avail - (total - 1) * gap) / total
	for i in total:
		var r := Rect2(16 + i * (pw + gap), h - 38, pw, 4)
		draw_rect(r, Color(col, 0.95) if i < lit else Color(col, 0.16))
