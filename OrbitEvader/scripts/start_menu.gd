extends Control


@onready var animation_player: AnimationPlayer = $AnimationPlayer
var on_start_screen : bool = false

func _process(delta: float) -> void:
	if on_start_screen and Input.is_action_just_pressed("escape"):
		Global.is_first_load = false
		get_tree().reload_current_scene()
	if Input.is_action_just_pressed("exit"):
		get_tree().quit()
	
func _ready() -> void:
	if Global.is_first_load:
		on_start_screen = true
		pause()
	else:
		visible = false
		get_tree().paused = false

func resume() -> void:
	get_tree().paused = false
	on_start_screen = false
	animation_player.play("blur")
	
func pause() -> void:
	get_tree().paused = true
	animation_player.play_backwards("blur")



func _on_quit_pressed() -> void:
	get_tree().quit()
	


func _on_start_pressed() -> void:
	resume()
