extends Control
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	visible = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	test_esc()
	if Input.is_action_just_pressed("exit"):
		get_tree().quit()


func resume() -> void:
	get_tree().paused = false
	animation_player.play("blur")
	
func pause() -> void:
	get_tree().paused = true
	animation_player.play_backwards("blur")
	
	
func test_esc() -> void:
	if Input.is_action_just_pressed("escape") and get_tree().paused:
		resume()
	elif Input.is_action_just_pressed("escape") and !get_tree().paused:
		pause()



func _on_resume_pressed() -> void:
	resume()
	
func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().quit()
	
