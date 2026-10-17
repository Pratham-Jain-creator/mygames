class_name FloatingText
extends Node2D
## Short-lived number popup (-3 HP, +Ø1, +0.5 ...). Motion is the "rise" animation.

const SCENE_PATH := "res://scenes/components/floating_text/floating_text.tscn"


static func spawn(parent: Node, text: String, color: Color, at: Vector2) -> void:
	var scene: PackedScene = load(SCENE_PATH)
	var f: FloatingText = scene.instantiate()
	parent.add_child(f)
	f.global_position = at
	f.start(text, color)


func start(text: String, color: Color) -> void:
	var label: Label = $Label
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	var player: AnimationPlayer = $AnimationPlayer
	player.play(&"rise")
	player.animation_finished.connect(func(_n): queue_free())
