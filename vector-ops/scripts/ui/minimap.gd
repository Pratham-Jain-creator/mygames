class_name Minimap
extends Control
## Radar controller. The layout lives in hud.tscn (MinimapModule); this script
## only moves the pins. Teammates are always shown; enemies only while their
## radar_visible flag is set (not running Ghost, or still carrying a signature).
## Pins beyond radar range are pinned to the rim so you keep their bearing.

const BLIP_SCENE := preload("res://scenes/ui/minimap_blip.tscn")
const RIM_MARGIN := 8.0
const SIG_AMBER := Color(0.95, 0.75, 0.25)
const SIG_MASKED := Color("43e0c6")
const SIG_EXPOSED := Color("e05263")

@export var radar_range_meters: float = 40.0
## true (default): the map turns with you, so the white arrow always points up = where you look.
## false: north-up map, the white arrow turns.
@export var rotate_with_player: bool = true

@onready var _canvas: Control = %MapCanvas
@onready var _blips: Control = %BlipContainer
@onready var _arrow: Polygon2D = %PlayerArrow
@onready var _walls: Control = %Walls
@onready var _sig: Label = %SignatureStatus
@onready var _range: Label = %RangeLabel
@onready var _hint: Label = %PingHint

var _pool: Dictionary = {} # player -> blip node
var _t: float = 0.0


func _ready() -> void:
	_range.text = "RANGE: %dm · %s" % [int(radar_range_meters), "ROT" if rotate_with_player else "N-UP"]


func _process(delta: float) -> void:
	_t += delta
	var lp: Node = GameState.get_local_player()
	if lp == null:
		_clear_blips()
		return
	var half: float = _canvas.size.x * 0.5
	var k: float = half / radar_range_meters
	var yaw: float = lp.rotation.y

	_arrow.position = _canvas.size * 0.5
	_arrow.rotation = 0.0 if rotate_with_player else -yaw
	_walls.set_view(lp.global_position, yaw, k, rotate_with_player)

	var seen: Dictionary = {}
	for p in get_tree().get_nodes_in_group("players"):
		if p == lp or p.flux.ejected:
			continue
		var friendly: bool = p.team == lp.team
		if not friendly and not p.flux.radar_visible:
			continue
		seen[p] = true
		var rel: Vector3 = p.global_position - lp.global_position
		var off := Vector2(rel.x, rel.z) * k
		var heading := Vector2(-sin(p.rotation.y), -cos(p.rotation.y))
		if rotate_with_player:
			off = off.rotated(yaw)
			heading = heading.rotated(yaw)
		var limit: float = half - RIM_MARGIN
		var edge: bool = off.length() > limit
		if edge:
			off = off.normalized() * limit
		var b: Node2D = _pool.get(p)
		if b == null or not is_instance_valid(b):
			b = BLIP_SCENE.instantiate()
			_blips.add_child(b)
			_pool[p] = b
		b.set_team(friendly)
		b.position = off
		b.set_heading(heading.angle() + PI * 0.5)
		b.set_edge(edge)
	for p in _pool.keys():
		if not seen.has(p):
			if is_instance_valid(_pool[p]):
				_pool[p].queue_free()
			_pool.erase(p)

	_update_status(lp)


func _update_status(lp: Node) -> void:
	var f: FluxComponent = lp.flux
	var txt: String = "SIG: VISIBLE"
	var col: Color = SIG_AMBER
	var pulse: bool = false
	if f.ejected:
		txt = "SIG: OFFLINE"
		col = Color(0.5, 0.55, 0.6)
	elif f.stealth == 1 and not f.radar_visible:
		txt = "SIG: MASKED"
		col = SIG_MASKED
	elif f.stealth == 1 or lp.scoped:
		# Ghost with a leftover signature, or a scoped Bolt shot is about to flag you
		txt = "SIG: EXPOSED"
		col = SIG_EXPOSED
		pulse = true
	_sig.text = txt
	_sig.modulate = col * Color(1, 1, 1, 0.65 + 0.35 * sin(_t * 9.0)) if pulse else col
	_hint.text = "TAB: SPECTATE" if f.ejected else ""


func _clear_blips() -> void:
	for p in _pool.keys():
		if is_instance_valid(_pool[p]):
			_pool[p].queue_free()
	_pool.clear()
