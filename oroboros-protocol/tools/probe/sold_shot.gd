extends Node
func _ready() -> void:
	RunState.start_new_run()
	RunState.money = 12
	var scr: Control = load("res://scenes/shop/shop_screen.tscn").instantiate()
	add_child(scr)
	await get_tree().create_timer(2.0).timeout
	var rows: Array = scr._rows
	for i in min(2, rows.size()):
		rows[i].set_sold(true)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/probe/shots/sold.png")
	get_tree().quit()
