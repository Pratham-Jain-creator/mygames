class_name WeaponBay
extends InteractiveControl
## Shows the equipped Breach Protocol: etched Base Strength + a Target Ceiling that
## ticks down violently (ceiling_hit) and shatters (shatter) when the weapon breaks.

const ART_EMPTY := preload("res://assets/UI/firewall_empty.png")
const ART_ON := preload("res://assets/UI/firewall_equipped.png")

var _active := false
var _strength := 0
var _ceiling_text := "INF"

@onready var _strength_label: Label = %StrengthLabel
@onready var _ceiling_label: Label = %CeilingLabel
@onready var _empty_label: Label = %EmptyLabel
@onready var _art: TextureRect = %Art


func _ready() -> void:
	super()
	show_empty()


func show_empty() -> void:
	_active = false
	_art.texture = ART_EMPTY
	_strength_label.visible = false
	_ceiling_label.visible = false
	_empty_label.visible = true


func show_weapon(strength: int, ceiling_text: String, animate := true) -> void:
	_active = true
	_art.texture = ART_ON
	_strength = strength
	_ceiling_text = ceiling_text
	_strength_label.text = "STR %d" % strength
	_ceiling_label.text = "CAP %s" % ceiling_text
	_strength_label.visible = true
	_ceiling_label.visible = true
	_empty_label.visible = false
	if animate:
		play_anim(&"equip")
		AudioService.play("slam", 1.2)


func set_ceiling(ceiling_text: String) -> void:
	_ceiling_text = ceiling_text
	_ceiling_label.text = "CAP %s" % ceiling_text
	play_anim(&"ceiling_hit")
	AudioService.play("hit", 1.6, -4.0)


func shatter() -> void:
	play_anim(&"shatter")
	AudioService.play("break")
	await anim.animation_finished
	show_empty()


func get_tip_data() -> Dictionary:
	if not _active:
		return {"title": "NO FIREWALL", "body": "Resolve a Firewall node to equip it. Glitch then deals (Glitch value - Base Strength) damage instead of its full value.", "color": Enums.COL_BREACH}
	return {
		"title": "EQUIPPED PROTOCOL",
		"body": "[b]Base Strength %d[/b]: blocks this much Glitch damage and never decreases.\n[b]Target Ceiling %s[/b]: the highest Glitch it can still target. Each hit sets it to Glitch value - 1.\n\nWeak Glitches are not free: each one drags the ceiling down." % [_strength, _ceiling_text],
		"color": Enums.COL_BREACH,
	}
