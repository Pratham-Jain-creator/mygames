extends Control

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var death_message_2: Label = $deathMessage2
@onready var sound_player: AnimationPlayer = $soundPlayer

var on_death_screen : bool = false

func _ready() -> void:
	visible = false
	on_death_screen = false

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("escape") and on_death_screen:
		_on_start_pressed()
	if Input.is_action_just_pressed("exit"):
		get_tree().quit()

func resume() -> void:
	get_tree().paused = false
	animation_player.play("blur")
	
func pause() -> void:
	sound_player.play("sound")
	get_tree().paused = true
	on_death_screen = true
	death_message_2.text = "Score: " + str(Global.score)
	animation_player.play_backwards("blur")
	Global.is_first_load = false
	



func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_start_pressed() -> void:
	Global._reset()
	get_tree().reload_current_scene()
