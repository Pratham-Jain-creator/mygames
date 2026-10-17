class_name Bunker
extends StaticBody3D
## Static barricade (Bunker module). Look, collision and the rise animation live
## in scenes/combat/bunker.tscn. Exists on every peer; the server owns its
## health and lifetime and tells everyone to remove it via Player.bunker_rpc.

const SIZE := Vector3(2.4, 2.2, 0.4) # matches the CollisionShape3D in the scene

var bid: int = 0
var owner_player: Player = null
var hp: float = 120.0

@onready var _seams: Array[MeshInstance3D] = [%SeamLeft, %SeamRight, %SeamTop]


## Tints the glowing seams with the owner's team colour. Call after add_child.
func build() -> void:
	var tc := Color(0.25, 0.55, 1.0) if (owner_player != null and owner_player.team == 0) else Color(1.0, 0.55, 0.15)
	var m := StandardMaterial3D.new()
	m.albedo_color = tc.lerp(Color.WHITE, 0.3)
	m.emission_enabled = true
	m.emission = tc
	m.emission_energy_multiplier = 3.2
	for s in _seams:
		s.material_override = m


func _physics_process(_delta: float) -> void:
	if GameState.phase == GameState.Phase.COUNTDOWN or GameState.phase == GameState.Phase.LOBBY:
		queue_free()
		return


## Server: shot at by a weapon.
func damage(d: float) -> void:
	if not multiplayer.is_server():
		return
	hp -= d
	if hp <= 0.0:
		remove()


func remove() -> void:
	if is_instance_valid(owner_player):
		owner_player.bunker_rpc.rpc("free", bid, Transform3D.IDENTITY)
	else:
		queue_free()
