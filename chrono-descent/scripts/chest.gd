class_name LootChest
extends Node2D
## A treasure chest: ash and materials (or, in a gauntlet, the reward that unlocks when the fight is won).
## Its picture is the mimic sheet's disguised chest, so a real chest and a mimic look the same until one bites.
## `locked` chests (a gauntlet's reward) cannot be opened until unlock() is called.

signal opened_by(player: Node)

@export var locked: bool = false
## A golden chest holds more.
@export var golden: bool = false
## Extra materials on top of the usual.
@export var bonus_materials: int = 0

var opened: bool = false

var _sprite: Sprite2D
var _glow: PointLight2D
var _clock: float = 0.0


func _ready() -> void:
	add_to_group("interactable")
	z_index = 1
	_clock = randf() * TAU
	_sprite = Sprite2D.new()
	var sheet := SpriteLib.MOBS + ("mimic_chest_golden.png" if golden else "mimic_chest.png")
	_sprite.texture = SpriteLib.texture(sheet)
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(0, 0, 64, 64)
	_sprite.scale = Vector2(0.75, 0.75)
	_sprite.offset = Vector2(0, -22) # the chest sits in the lower half of its cell
	add_child(_sprite)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(0.4, 0.4, 0.4), Color.BLACK])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	_glow = PointLight2D.new()
	_glow.texture = texture
	_glow.color = Color(1.0, 0.82, 0.4) if golden else Color(1.0, 0.7, 0.4)
	_glow.texture_scale = 0.7
	_glow.energy = 0.0 if locked else 0.5
	_glow.position = Vector2(0, -8)
	add_child(_glow)
	_refresh_look()


func _process(delta: float) -> void:
	_clock += delta
	if not opened and not locked:
		_glow.energy = 0.45 + 0.12 * sin(_clock * 3.0)


func _refresh_look() -> void:
	_sprite.modulate = Color(0.55, 0.55, 0.6) if locked else (Color(0.5, 0.5, 0.5) if opened else Color.WHITE)


func unlock() -> void:
	if opened or not locked:
		return
	locked = false
	_refresh_look()
	_glow.energy = 0.5
	GameManager.toast_requested.emit("THE REWARD CHEST UNLOCKS", null, Color(1.0, 0.85, 0.5))


func can_interact() -> bool:
	return not opened and not locked


func get_prompt() -> String:
	return "OPEN CHEST"


func interact(by: Node) -> void:
	if opened or locked:
		return
	opened = true
	_refresh_look()
	_glow.energy = 0.0
	Audio.play(preload("res://assets/sounds/coin.wav"), -4.0, 0.8)
	var depth := maxi(GameManager.current_depth, 1)
	var parent := get_parent()
	var multiplier := 2.0 if golden else 1.0
	Loot.drop_ash(parent, global_position + Vector2(0, 6), int(round(float(30 + 12 * depth) * multiplier * Loot.floor_scale(depth) * 0.5)))
	Loot.drop_materials(parent, global_position + Vector2(0, 6), 1 + (1 if golden else 0) + randi() % 2 + bonus_materials, depth)
	if randf() < 0.08:
		Pickup.spawn(parent, global_position + Vector2(0, 6), Pickup.Kind.ECHO, 1)
	var burst := create_tween().set_parallel(true)
	burst.tween_property(_sprite, "scale", Vector2(0.9, 0.62), 0.08)
	burst.chain().tween_property(_sprite, "scale", Vector2(0.75, 0.75), 0.18).set_trans(Tween.TRANS_BACK)
	GameManager.shake_camera(1.5, 0.12)
	opened_by.emit(by)
