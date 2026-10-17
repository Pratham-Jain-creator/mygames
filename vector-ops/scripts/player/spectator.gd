class_name Spectator
extends Node
## Orbit camera that takes over when the local player is Ejected (Task 1.4),
## or when joining mid-round. Tab cycles targets.

var cam: Camera3D
var yaw: float = 0.0
var pitch: float = -0.35
var idx: int = 0


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "SpectatorCam"
	add_child(cam)


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= mm.relative.x * 0.003
		pitch = clampf(pitch - mm.relative.y * 0.003, -1.3, 0.6)
	if event.is_action_pressed("spectate_next"):
		idx += 1


func _process(delta: float) -> void:
	var phase: int = GameState.phase
	var in_round: bool = phase == GameState.Phase.COUNTDOWN or phase == GameState.Phase.LIVE or phase == GameState.Phase.ROUND_END
	var lp: Node = GameState.get_local_player()
	var need: bool = in_round and (lp == null or lp.flux.ejected)
	if not need:
		return
	if not cam.current:
		cam.make_current()
	if GameState.using_pad and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var lv: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.15)
		yaw -= lv.x * 2.5 * delta
		pitch = clampf(pitch - lv.y * 2.0 * delta, -1.3, 0.6)
	var mates: Array = []
	var others: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p.flux.ejected:
			continue
		if p.team == GameState.local_team:
			mates.append(p)
		else:
			others.append(p)
	var pool: Array = mates if not mates.is_empty() else others
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	if pool.is_empty():
		cam.global_position = Vector3(0, 18, 0) + basis * Vector3(0, 0, 14)
	else:
		var target: Node = pool[idx % pool.size()]
		var t_pos: Vector3 = target.global_position + Vector3(0, 1.6, 0)
		cam.global_position = t_pos + basis * Vector3(0, 0.6, 4.0)
	cam.global_basis = basis
