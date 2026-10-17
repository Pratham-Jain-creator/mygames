class_name NodeData
extends RefCounted
## One Node (card) of the deck. `base_value` is permanent; `eff_value` is the
## per-room value after boss / daemon modifiers (Wall, Mirror, Quarantine...).

static var _next_uid := 1

var uid: int
var type: int
var base_value: int
var eff_value: int
var zipped := false      # Compress: +10 Base Data when resolved
var holo := false        # Overclock: +1 Bandwidth when resolved
var gold := false        # Gild: earns Ø when resolved
var encrypted := false   # Encrypt applied at least once
var temporary := false   # spawned mid-server (Glitch); vanishes at server end
var face_down := false   # runtime only (Cipher / Poltergeist)
var spent_hidden := false  # runtime only: resolved while face down (Blind Injection); Tailbytes shows it as unknown
var type_known := false  # runtime only: face down but the TYPE is visible (Cipher hides values only)
var burn_mark := 0       # Burn-In: id of the Server in which this Node last grew
var stash_turns := 0     # runtime only: turns this Node has been carried in the Stash


func _init(p_type: int, p_value: int) -> void:
	uid = NodeData._next_uid
	NodeData._next_uid += 1
	type = p_type
	base_value = p_value
	eff_value = p_value


func is_modified() -> bool:
	return zipped or holo or gold or encrypted


func duplicate_node() -> NodeData:
	var n := NodeData.new(type, base_value)
	n.zipped = zipped
	n.holo = holo
	n.gold = gold
	n.encrypted = encrypted
	return n


func mod_tags() -> Array:
	var t: Array = []
	if encrypted:
		t.append("E")
	if zipped:
		t.append("Z")
	if holo:
		t.append("H")
	if gold:
		t.append("Ø")
	return t


func label() -> String:
	return "%s %d" % [Enums.TYPE_SHORT[type], eff_value]
