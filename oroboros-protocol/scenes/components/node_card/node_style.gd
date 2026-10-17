class_name NodeStyle
extends RefCounted
## ONE place that describes how each Node kind looks. NodeFace (the card body)
## and NodeIcon (the glyph) both read from here, so a new kind or a new look is
## a few lines in this file - never a hand-built scene.
## Design reference: assets/nodes/Node.dc.html (shapes, textures, icons, roles).

const TEX_NONE := &"none"
const TEX_DOTS := &"dots"
const TEX_DIAG := &"diag"
const TEX_GRID := &"grid"
const TEX_HATCH := &"hatch"

const ROLES := {
	Enums.NodeType.DATA: "MINE",
	Enums.NodeType.ICE: "VIRUS",
	Enums.NodeType.COOLANT: "HEAL",
	Enums.NodeType.BREACH: "GUARD",
}
const TEXTURES := {
	Enums.NodeType.DATA: TEX_DOTS,
	Enums.NodeType.ICE: TEX_DIAG,
	Enums.NodeType.COOLANT: TEX_GRID,
	Enums.NodeType.BREACH: TEX_HATCH,
}


# ------------------------------------------------------------ PNG art (assets/nodes)
## The card frames / icons / pips are painted PNGs; everything ON the card (numbers,
## names, effect text, QUEUE tab, pips) is placed by script. Mapping game kind -> art set:
## Siphon -> siphon, Glitch (enum ICE) -> glitch, Patch -> patch, Firewall (enum BREACH) -> ice.
const ART_BODY := Vector2(480, 680)   # solid card area inside the 576x776 frame PNG
const ART_PAD := 48.0                 # glow margin around the body in the PNG
const ART_SETS := {
	Enums.NodeType.DATA: "siphon",
	Enums.NodeType.ICE: "glitch",
	Enums.NodeType.COOLANT: "patch",
	Enums.NodeType.BREACH: "ice",
}
const CARD_TEX := {
	"siphon": [preload("res://assets/nodes/card_siphon.png"), preload("res://assets/nodes/card_siphon_selected.png")],
	"glitch": [preload("res://assets/nodes/card_glitch.png"), preload("res://assets/nodes/card_glitch_selected.png")],
	"patch": [preload("res://assets/nodes/card_patch.png"), preload("res://assets/nodes/card_patch_selected.png")],
	"ice": [preload("res://assets/nodes/card_ice.png"), preload("res://assets/nodes/card_ice_selected.png")],
}
const ICON_TEX := {
	"siphon": preload("res://assets/nodes/icon_siphon.png"),
	"glitch": preload("res://assets/nodes/icon_glitch.png"),
	"patch": preload("res://assets/nodes/icon_patch.png"),
	"ice": preload("res://assets/nodes/icon_ice.png"),
}
const PIP_TEX := {
	"siphon": [preload("res://assets/nodes/pip_siphon_off.png"), preload("res://assets/nodes/pip_siphon_lit.png")],
	"glitch": [preload("res://assets/nodes/pip_glitch_off.png"), preload("res://assets/nodes/pip_glitch_lit.png")],
	"patch": [preload("res://assets/nodes/pip_patch_off.png"), preload("res://assets/nodes/pip_patch_lit.png")],
	"ice": [preload("res://assets/nodes/pip_ice_off.png"), preload("res://assets/nodes/pip_ice_lit.png")],
}


static func card_tex(kind: int, selected: bool) -> Texture2D:
	var set_name: String = ART_SETS.get(kind, "")
	if set_name == "":
		return null
	return CARD_TEX[set_name][1 if selected else 0]


static func icon_tex(kind: int) -> Texture2D:
	var set_name: String = ART_SETS.get(kind, "")
	return ICON_TEX[set_name] if set_name != "" else null


## state: 0 = unlit, 1 = lit
static func pip_tex(kind: int, lit: bool) -> Texture2D:
	var set_name: String = ART_SETS.get(kind, "")
	return PIP_TEX[set_name][1 if lit else 0] if set_name != "" else null


static func role(kind: int) -> String:
	return ROLES.get(kind, "???")


static func texture(kind: int) -> StringName:
	return TEXTURES.get(kind, TEX_NONE)


## Card outline in local pixels for a card of size `s`. kind -1 = unknown (face-down).
static func shape(kind: int, s: Vector2) -> PackedVector2Array:
	var w := s.x
	var h := s.y
	var c := 14.0
	match kind:
		Enums.NodeType.DATA:       # Siphon: chamfered top-right + bottom-left
			return PackedVector2Array([Vector2(0, 0), Vector2(w - c, 0), Vector2(w, c),
				Vector2(w, h), Vector2(c, h), Vector2(0, h - c)])
		Enums.NodeType.ICE:        # Glitch: chamfered top-left + bottom-right, notch in the right edge
			var ny := h * 0.35
			return PackedVector2Array([Vector2(c, 0), Vector2(w, 0), Vector2(w, ny),
				Vector2(w - 8, ny + 8), Vector2(w, ny + 16), Vector2(w, h - c),
				Vector2(w - c, h), Vector2(0, h), Vector2(0, c)])
		Enums.NodeType.COOLANT:    # Patch: octagon
			var o := 18.0
			return PackedVector2Array([Vector2(o, 0), Vector2(w - o, 0), Vector2(w, o),
				Vector2(w, h - o), Vector2(w - o, h), Vector2(o, h), Vector2(0, h - o), Vector2(0, o)])
		Enums.NodeType.BREACH:     # Firewall: shield with a pointed base
			var k := 10.0
			return PackedVector2Array([Vector2(k, 0), Vector2(w - k, 0), Vector2(w, k),
				Vector2(w, h - 18), Vector2(w * 0.5 + 30, h - 3), Vector2(w * 0.5, h),
				Vector2(w * 0.5 - 30, h - 3), Vector2(0, h - 18), Vector2(0, k)])
		_:                         # unknown
			return PackedVector2Array([Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c),
				Vector2(w, h - c), Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c)])


# ---------------------------------------------------------------- icon paths
## Icons are polylines in a 120x120 box (same numbers as the SVG paths in the
## mockup). Each part: {pts, closed, fill (alpha), off (Vector2), col (optional), alpha}.
static func _bez(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, n := 12) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		out.append(u * u * u * p0 + 3 * u * u * t * c1 + 3 * u * t * t * c2 + t * t * t * p1)
	return out


static func _ellipse(c: Vector2, rx: float, ry: float, n := 28) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / n
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func _part(pts: PackedVector2Array, closed := false, fill := 0.0) -> Dictionary:
	return {"pts": pts, "closed": closed, "fill": fill, "off": Vector2.ZERO, "alpha": 1.0}


static func _db_ring(dy: float) -> PackedVector2Array:
	var out := PackedVector2Array([Vector2(28, 24 + dy), Vector2(28, 50 + dy)])
	out.append_array(_bez(Vector2(28, 50 + dy), Vector2(28, 55.5 + dy), Vector2(42.3, 60 + dy), Vector2(60, 60 + dy)))
	out.append_array(_bez(Vector2(60, 60 + dy), Vector2(77.7, 60 + dy), Vector2(92, 55.5 + dy), Vector2(92, 50 + dy)))
	out.append(Vector2(92, 24 + dy))
	return out


static func icon_parts(kind: int) -> Array:
	match kind:
		Enums.NodeType.DATA:       # database
			return [
				_part(_ellipse(Vector2(60, 24), 32, 10), true, 0.18),
				_part(_db_ring(0.0)), _part(_db_ring(26.0)),
				_part(PackedVector2Array([Vector2(60, 92), Vector2(60, 112)])),
				_part(PackedVector2Array([Vector2(46, 100), Vector2(60, 112), Vector2(74, 100)])),
			]
		Enums.NodeType.ICE:        # lightning bolt with a cyan ghost + glitch dashes
			var bolt := PackedVector2Array([Vector2(68, 12), Vector2(36, 66), Vector2(60, 66),
				Vector2(52, 108), Vector2(88, 50), Vector2(64, 50)])
			var ghost := _part(bolt, true)
			ghost["off"] = Vector2(-5, 3)
			ghost["col"] = Color("38e8ff")
			ghost["alpha"] = 0.55
			return [ghost, _part(bolt, true, 0.18),
				_part(PackedVector2Array([Vector2(10, 40), Vector2(32, 40)])),
				_part(PackedVector2Array([Vector2(88, 84), Vector2(110, 84)])),
				_part(PackedVector2Array([Vector2(94, 28), Vector2(110, 28)]))]
		Enums.NodeType.COOLANT:    # hexagon + plus
			return [
				_part(PackedVector2Array([Vector2(60, 8), Vector2(104, 33), Vector2(104, 83),
					Vector2(60, 108), Vector2(16, 83), Vector2(16, 33)]), true, 0.12),
				_part(PackedVector2Array([Vector2(52, 34), Vector2(68, 34), Vector2(68, 50), Vector2(84, 50),
					Vector2(84, 66), Vector2(68, 66), Vector2(68, 82), Vector2(52, 82), Vector2(52, 66),
					Vector2(36, 66), Vector2(36, 50), Vector2(52, 50)]), true),
			]
		Enums.NodeType.BREACH:     # Firewall: shield + diamond + cross
			var sh := PackedVector2Array([Vector2(60, 8), Vector2(104, 24), Vector2(104, 60)])
			sh.append_array(_bez(Vector2(104, 60), Vector2(104, 86), Vector2(86, 102), Vector2(60, 112)))
			sh.append_array(_bez(Vector2(60, 112), Vector2(34, 102), Vector2(16, 86), Vector2(16, 60)))
			sh.append(Vector2(16, 24))
			return [
				_part(sh, true, 0.12),
				_part(PackedVector2Array([Vector2(60, 34), Vector2(82, 60), Vector2(60, 86), Vector2(38, 60)]), true),
				_part(PackedVector2Array([Vector2(60, 34), Vector2(60, 86)])),
				_part(PackedVector2Array([Vector2(38, 60), Vector2(82, 60)])),
			]
	return []
