extends RefCounted
## Vector icons for the 12 modules, used by the HUD loadout cards.
## Every shape is a polygon centred on (0, 0) inside a ~30x30 box.
## To use real art instead, drop a PNG at res://assets/images/UI/icons/<id>.png
## (e.g. kinetic.png): texture_of() picks it up and the card hides the glyph.

const ICON_DIR := "res://assets/images/UI/icons/"

const SHAPES := {
	"kinetic": [-14, -4, 8, -4, 14, 0, 8, 4, -6, 4, -10, 10, -14, 10],
	"edge": [0, -15, 4, -4, 4, 5, 9, 5, 9, 8, 2, 8, 2, 15, -2, 15, -2, 8, -9, 8, -9, 5, -4, 5, -4, -4],
	"aegis": [-10, -14, 10, -14, 14, 0, 0, 15, -14, 0],
	"boost": [0, -15, 13, 0, 5, 0, 5, 14, -5, 14, -5, 0, -13, 0],
	"shift": [-14, 0, -4, -12, -4, -5, 4, -5, 4, -12, 14, 0, 4, 12, 4, 5, -4, 5, -4, 12],
	"bolt": [-15, -3, 6, -3, 6, -5, 11, -5, 11, -3, 15, -1, 15, 1, 6, 1, 4, 6, -2, 6, -4, 2, -15, 2],
	"bunker": [-14, -6, -14, 12, 14, 12, 14, -6, 8, -6, 8, -12, 3, -12, 3, -6, -3, -6, -3, -12, -8, -12, -8, -6],
	"ghost": [-10, 14, -10, -4, -6, -12, 0, -15, 6, -12, 10, -4, 10, 14, 5, 9, 0, 14, -5, 9],
	"mirage": [0, -15, 14, 0, 0, 15, -14, 0],
	"heal": [-4, -14, 4, -14, 4, -4, 14, -4, 14, 4, 4, 4, 4, 14, -4, 14, -4, 4, -14, 4, -14, -4, -4, -4],
}
const EMPTY_SHAPE := [-6, -6, 6, -6, 6, 6, -6, 6]


static func shape_of(id: String) -> PackedVector2Array:
	match id:
		"blast":
			return _star(8, 15.0, 7.0)
		"seeker":
			return _star(4, 15.0, 4.5)
	var flat: Array = SHAPES.get(id, EMPTY_SHAPE)
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return out


## The module's PNG icon, or null when none has been drawn yet.
static func texture_of(id: String) -> Texture2D:
	var path: String = ICON_DIR + id + ".png"
	if id != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func _star(points: int, outer: float, inner: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var r: float = outer if i % 2 == 0 else inner
		var a: float = -PI * 0.5 + PI * float(i) / float(points)
		out.append(Vector2(cos(a), sin(a)) * r)
	return out
