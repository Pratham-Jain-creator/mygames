class_name Fmt
extends RefCounted
## Small text-formatting helpers shared by the UI.


## 1234567 -> "1,234,567"
static func big(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if v < 0 else "") + out


static func ceiling(v: int) -> String:
	return "INF" if v >= 90 else str(maxi(v, 0))


# ---------------------------------------------------------------- keyword colours
static var _tag_rx: RegEx
static var _kw_rx: Array = []


## Colours and bolds every mention of the four Node types (Siphon, Glitch, Firewall, Patch)
## in BBCode text with that Node type's own colour, so players learn them by colour.
## Text that is already inside a [color] span is left alone. Only use on BBCode-enabled labels.
static func rich(text: String) -> String:
	if text == "":
		return text
	if _tag_rx == null:
		_tag_rx = RegEx.create_from_string("\\[[^\\]]*\\]")
		var words := {
			Enums.NodeType.DATA: "siphons?",
			Enums.NodeType.ICE: "glitch(?:es)?",
			Enums.NodeType.BREACH: "firewalls?",
			Enums.NodeType.COOLANT: "patch(?:es)?",
		}
		for t in words:
			_kw_rx.append([RegEx.create_from_string("(?i)\\b(" + String(words[t]) + ")\\b"), Enums.TYPE_COLORS[t].to_html(false)])
	var out := ""
	var depth := 0
	var pos := 0
	for m in _tag_rx.search_all(text):
		out += _paint(text.substr(pos, m.get_start() - pos), depth)
		var tag := m.get_string().to_lower()
		if tag.begins_with("[color"):
			depth += 1
		elif tag.begins_with("[/color"):
			depth = maxi(0, depth - 1)
		out += m.get_string()
		pos = m.get_end()
	out += _paint(text.substr(pos), depth)
	return out


static func _paint(seg: String, depth: int) -> String:
	if depth > 0 or seg == "":
		return seg
	for kw in _kw_rx:
		seg = (kw[0] as RegEx).sub(seg, "[b][color=#" + String(kw[1]) + "]$1[/color][/b]", true)
	return seg
