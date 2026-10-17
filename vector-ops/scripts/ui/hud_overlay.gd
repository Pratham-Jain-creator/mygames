class_name HudOverlay
extends Control
## Scope, hit marker and directional damage indicators (draw-only).
## The spreading crosshair ticks live in hud.tscn (Crosshair).

var indicators: Array = [] # {pos: Vector3, t: float, blocked: bool}
var hit_t: float = 0.0
var hit_kill: bool = false
var hit_head: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_indicator(pos: Vector3, blocked: bool) -> void:
	indicators.append({"pos": pos, "t": 1.4, "blocked": blocked})


func show_hit(killed: bool, zone: String = "torso") -> void:
	hit_t = 0.18
	hit_kill = killed
	hit_head = zone == "head"


func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	for i in range(indicators.size() - 1, -1, -1):
		indicators[i]["t"] -= delta
		if indicators[i]["t"] <= 0.0:
			indicators.remove_at(i)
	queue_redraw()


func _draw_scope(c: Vector2) -> void:
	var vs: Vector2 = get_viewport_rect().size
	var r: float = minf(vs.x, vs.y) * 0.4
	var outer: float = vs.length()
	var n: int = 96
	for i in n:
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		draw_colored_polygon(PackedVector2Array([c + d0 * r, c + d0 * outer, c + d1 * outer, c + d1 * r]), Color.BLACK)
	draw_arc(c, r, 0.0, TAU, 96, Color(0.1, 0.1, 0.1), 3.0)
	# crosshair with a gap, plus a bright red aim dot where the round lands
	var gap: float = 10.0
	var line_col := Color(0.05, 0.05, 0.05, 0.9)
	draw_line(c + Vector2(-r, 0), c + Vector2(-gap, 0), line_col, 2.0)
	draw_line(c + Vector2(gap, 0), c + Vector2(r, 0), line_col, 2.0)
	draw_line(c + Vector2(0, -r), c + Vector2(0, -gap), line_col, 2.0)
	draw_line(c + Vector2(0, gap), c + Vector2(0, r), line_col, 2.0)
	draw_circle(c, 6.0, Color(1, 1, 1, 0.9))
	draw_circle(c, 4.0, Color(1, 0.1, 0.05))
	var f: Font = ThemeDB.fallback_font
	draw_string(f, c + Vector2(-r, r + 24.0), "Click: FIRE    Shift: cancel", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 16, Color(0.85, 0.9, 1.0))


func _draw() -> void:
	var c: Vector2 = get_viewport_rect().size / 2.0
	var lp: Node = GameState.get_local_player()
	if lp == null or lp.flux.ejected:
		return
	if lp.scoped:
		_draw_scope(c)
		return
	if hit_t > 0.0:
		var hc := Color(1, 0.2, 0.2) if hit_kill else (Color(1, 0.9, 0.2) if hit_head else Color.WHITE)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 8.0, c + d * 18.0, hc, 3.0)
	var yaw: float = lp.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var rot: float = Vector2.UP.angle() - fwd.angle()
	for ind in indicators:
		var to: Vector3 = ind["pos"] - lp.global_position
		var sd: Vector2 = Vector2(to.x, to.z).rotated(rot)
		if sd.length() < 0.01:
			continue
		sd = sd.normalized()
		var alpha: float = clampf(float(ind["t"]) / 0.6, 0.0, 1.0)
		var colr := Color(0.3, 0.85, 1.0, alpha) if ind["blocked"] else Color(1.0, 0.15, 0.1, alpha)
		var perp := Vector2(-sd.y, sd.x)
		var base: Vector2 = c + sd * 150.0
		draw_colored_polygon(PackedVector2Array([base + sd * 22.0, base + perp * 12.0, base - perp * 12.0]), colr)
