class_name BoltView
extends Node3D
## Logic for scenes/bolt.tscn (the Bolt sniper rifle). The mesh, bolt handle,
## muzzle flash and the animations (idle / equip / fire) all live in the scene;
## this script only decides which animation to play.

@onready var anim: AnimationPlayer = $Anim


func _ready() -> void:
	# first-person model: no shadows from the viewmodel
	for n in find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func play_equip() -> void:
	anim.play("equip")
	anim.queue("idle")


func play_fire() -> void:
	anim.play("fire")
	anim.queue("idle")
