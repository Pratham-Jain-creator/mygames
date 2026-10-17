class_name OverlapRow
extends Container
## One-line row. Children sit side by side with `gap`; when they would be wider
## than `max_width` they overlap evenly instead, so the row never grows past the
## screen. Later children draw on top (NodeCard raises its z_index on hover /
## select so the card you point at always comes to the front).

@export var gap := 10.0            # smallest space between cards before they start to overlap
@export var max_gap := 48.0        # biggest space between cards when there is spare width
@export var max_width := 1180.0


func _get_minimum_size() -> Vector2:
	var n := 0
	var cw := 0.0
	var ch := 0.0
	for c in get_children():
		if c is Control and c.visible:
			n += 1
			var m: Vector2 = c.get_combined_minimum_size()
			cw = maxf(cw, m.x)
			ch = maxf(ch, m.y)
	if n == 0:
		return Vector2(0, 0)
	return Vector2(max_width, ch)      # the row always spans max_width so spare room can become spacing


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout()
	elif what == NOTIFICATION_CHILD_ORDER_CHANGED:
		update_minimum_size()


func _layout() -> void:
	var kids: Array = []
	for c in get_children():
		if c is Control and c.visible:
			kids.append(c)
	var n := kids.size()
	if n == 0:
		return
	var cw: float = kids[0].get_combined_minimum_size().x
	var width := maxf(size.x, 0.0)
	var step := cw + gap
	var span := n * cw + (n - 1) * gap
	if span > width and n > 1:
		step = (width - cw) / float(n - 1)        # not enough room: overlap evenly
		span = width
	else:
		# Spare room: spread it as spacing. The two side margins end up about twice as big
		# as the gap between cards (leftover / (n + 3) per gap).
		var left := width - n * cw
		var g := clampf(left / float(n + 3), gap, max_gap)
		step = cw + g
		span = n * cw + (n - 1) * g
	var x0 := maxf(0.0, (width - span) * 0.5)
	for i in n:
		var c: Control = kids[i]
		fit_child_in_rect(c, Rect2(Vector2(x0 + i * step, 0), c.get_combined_minimum_size()))
