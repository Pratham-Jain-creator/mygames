extends CanvasLayer
## Autoload: scene-to-scene navigation with an animated fade (AnimationPlayer).

const MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"
const NETWORK_MAP := "res://scenes/network_map/network_map.tscn"
const SERVER := "res://scenes/server/server_screen.tscn"
const SHOP := "res://scenes/shop/shop_screen.tscn"
const GAME_OVER := "res://scenes/game_over/game_over.tscn"

@onready var anim: AnimationPlayer = $AnimationPlayer
var _busy := false


func go(path: String) -> void:
	if _busy:
		return
	_busy = true
	anim.play(&"fade_out")
	await anim.animation_finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	anim.play(&"fade_in")
	await anim.animation_finished
	_busy = false
