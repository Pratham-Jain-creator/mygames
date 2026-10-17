extends Node3D
## Boot: put the player at the level's spawn marker and make it the first checkpoint.


func _ready() -> void:
	var spawn: Node3D = $Dungeon/Spawn
	Game.set_checkpoint(spawn.global_position, spawn.global_rotation.y)
	$Player.respawn(false)
