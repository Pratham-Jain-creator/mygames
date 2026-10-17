extends Node

var is_first_load: bool = true
var score: int = 0
var health: int = 3


func _reset() -> void :
	score = 0
	health = 3
	pass
