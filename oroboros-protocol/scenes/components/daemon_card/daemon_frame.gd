extends Control
## Generic Daemon card frame, drawn in code from the painted PNGs in assets/daemons/.
## One script serves every rarity and the empty slot:
##   * 9-slice stretching (corner brackets, side notches and the top/bottom diamond keep their
##     size; only the straight runs stretch) so the frame fits any card size.
##   * `fx` (0..1, animated by the card's "flash" animation) turns on the *_active glow art
##     plus a diagonal glitter sweep and diagonal dashes when the Daemon triggers.

const SETS := ["common", "uncommon", "rare", "epic", "legendary"]   # index = Enums rarity
const TEX := {
	"common": [preload("res://assets/daemons/daemon_common_idle.png"), preload("res://assets/daemons/daemon_common_active.png")],
	"uncommon": [preload("res://assets/daemons/daemon_uncommon_idle.png"), preload("res://assets/daemons/daemon_uncommon_active.png")],
	"rare": [preload("res://assets/daemons/daemon_rare_idle.png"), preload("res://assets/daemons/daemon_rare_active.png")],
	"epic": [preload("res://assets/daemons/daemon_epic_idle.png"), preload("res://assets/daemons/daemon_epic_active.png")],
	"legendary": [preload("res://assets/daemons/daemon_legendary_idle.png"), preload("res://assets/daemons/daemon_legendary_active.png")],
}
# 9-slice cut lines inside the 440x580 art (fixed bands 0,2,4 keep their size; 1 and 3 stretch).
const XS := [0.0, 114.0, 180.0, 260.0, 326.0, 440.0]
# Header band (0..128) and footer band (372..580) keep their size; the middle stretches around the side notch.
const YS := [0.0, 128.0, 214.0, 274.0, 372.0, 580.0]
const PAD := Vector4(34, 36, 32, 35)    # glow margin around the body: left, top, right, bottom
const K := 0.22                          # art px -> screen px for the fixed bands
const BODY_COL := Color(0.062, 0.075, 0.098)

var rarity := 0:
	set(v):
		rarity = clampi(v, 0, SETS.size() - 1)
		queue_redraw()
var empty := true:
	set(v):
		empty = v
		queue_redraw()
## 0 = idle. The "flash" animation drives this from 0 to 1.
var fx := 0.0:
	set(v):
		fx = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _body_poly() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var c := 9.0
	return PackedVector2Array([Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h - c),
		Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c)])


func _draw() -> void:
	var poly := _body_poly()
	var art_set: String = SETS[rarity]
	var idle: Texture2D = TEX[art_set][0]
	var active: Texture2D = TEX[art_set][1]
	# The frame art now carries its own background (header / body / footer bands).
	var tint := Color(0.5, 0.52, 0.58, 1.0) if empty else Color.WHITE
	_slice(idle, tint)
	if empty or fx <= 0.001 or fx >= 0.999:
		return
	# --- triggered: active glow + diagonal glitter + diagonal dashes
	var pulse := sin(PI * fx)
	_slice(active, Color(1, 1, 1, pulse))
	var w := size.x
	var h := size.y
	var travel := w + h + 60.0
	var head := -30.0 + fx * travel
	# glitter band (45 degrees, runs bottom-left to top-right)
	var bw := 26.0
	var band := PackedVector2Array([Vector2(head, h), Vector2(head + bw, h), Vector2(head + bw + h, 0), Vector2(head + h, 0)])
	for piece in Geometry2D.intersect_polygons(band, poly):
		draw_colored_polygon(piece, Color(1, 1, 1, 0.38 * pulse))
	# dashes trailing behind the glitter
	for i in 3:
		var x0 := head - 40.0 - i * 16.0
		var seg := PackedVector2Array([Vector2(x0, h), Vector2(x0 + h, 0)])
		for piece in Geometry2D.intersect_polyline_with_polygon(seg, poly):
			if piece.size() >= 2:
				draw_dashed_line(piece[0], piece[1], Color(1, 1, 1, (0.85 - i * 0.22) * pulse), 2.0, 6.0)


func _slice(tex: Texture2D, mod: Color) -> void:
	var rect := Rect2(Vector2(-PAD.x, -PAD.y) * K, Vector2(size.x + (PAD.x + PAD.z) * K, size.y + (PAD.y + PAD.w) * K))
	var fixed_w: float = (XS[1] - XS[0] + XS[3] - XS[2] + XS[5] - XS[4]) * K
	var fixed_h: float = (YS[1] - YS[0] + YS[3] - YS[2] + YS[5] - YS[4]) * K
	var stretch_w := maxf(0.0, rect.size.x - fixed_w)
	var stretch_h := maxf(0.0, rect.size.y - fixed_h)
	var sw1: float = XS[2] - XS[1]
	var sw3: float = XS[4] - XS[3]
	var sh1: float = YS[2] - YS[1]
	var sh3: float = YS[4] - YS[3]
	var dw: Array = []
	var dh: Array = []
	for i in 5:
		var sw: float = XS[i + 1] - XS[i]
		var sh: float = YS[i + 1] - YS[i]
		if i == 1:
			dw.append(stretch_w * sw1 / (sw1 + sw3))
			dh.append(stretch_h * sh1 / (sh1 + sh3))
		elif i == 3:
			dw.append(stretch_w * sw3 / (sw1 + sw3))
			dh.append(stretch_h * sh3 / (sh1 + sh3))
		else:
			dw.append(sw * K)
			dh.append(sh * K)
	var y := rect.position.y
	for j in 5:
		var x := rect.position.x
		for i in 5:
			var src := Rect2(XS[i], YS[j], XS[i + 1] - XS[i], YS[j + 1] - YS[j])
			draw_texture_rect_region(tex, Rect2(x, y, dw[i], dh[j]), src, mod)
			x += dw[i]
		y += dh[j]
