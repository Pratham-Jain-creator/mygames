extends Node
## Dev helper: loads scripts / scenes one by one so parse errors surface with their
## real message (run this scene from the editor or the Godot MCP).

const PATHS := [
	"res://scenes/components/interactive_control/interactive_control.gd",
	"res://scenes/components/action_button/action_button.gd",
	"res://scenes/components/node_card/node_card.gd",
	"res://scenes/components/node_card/node_icon.gd",
	"res://scenes/components/node_card/variants/data_cache_card.gd",
	"res://scenes/components/node_card/variants/ice_card.gd",
	"res://scenes/components/node_card/variants/breach_card.gd",
	"res://scenes/components/node_card/variants/coolant_card.gd",
	"res://scenes/components/node_card/node_card_factory.gd",
	"res://scenes/components/daemon_card/daemon_card.gd",
	"res://scenes/components/weapon_bay/weapon_bay.gd",
	"res://scenes/components/led_block/led_block.gd",
	"res://scenes/components/led_health_bar/led_health_bar.gd",
	"res://scenes/components/score_display/score_display.gd",
	"res://scenes/components/shop_listing/shop_listing.gd",
	"res://scenes/components/deck_viewer/deck_viewer.gd",
	"res://scenes/components/type_picker/type_picker.gd",
	"res://scenes/components/hex_backdrop/hex_backdrop.gd",
	"res://scenes/components/toast/toast.gd",
	"res://scenes/components/floating_text/floating_text.gd",
	"res://scenes/components/server_card/server_card.gd",
	"res://scenes/components/base_screen/base_screen.gd",
	"res://scenes/components/safe_area/safe_area_container.gd",
	"res://scenes/main_menu/main_menu.gd",
	"res://scenes/network_map/network_map.gd",
	"res://scenes/server/server_screen.gd",
	"res://scenes/shop/shop_screen.gd",
	"res://scenes/game_over/game_over.gd",
	"res://scenes/components/action_button/action_button.tscn",
	"res://scenes/components/node_card/variants/data_cache_card.tscn",
	"res://scenes/components/node_card/variants/ice_card.tscn",
	"res://scenes/components/node_card/variants/breach_card.tscn",
	"res://scenes/components/node_card/variants/coolant_card.tscn",
	"res://scenes/components/daemon_card/daemon_card.tscn",
	"res://scenes/components/weapon_bay/weapon_bay.tscn",
	"res://scenes/components/led_block/led_block.tscn",
	"res://scenes/components/led_health_bar/led_health_bar.tscn",
	"res://scenes/components/score_display/score_display.tscn",
	"res://scenes/components/shop_listing/shop_listing.tscn",
	"res://scenes/components/deck_viewer/deck_viewer.tscn",
	"res://scenes/components/type_picker/type_picker.tscn",
	"res://scenes/components/hex_backdrop/hex_backdrop.tscn",
	"res://scenes/components/toast/toast.tscn",
	"res://scenes/components/floating_text/floating_text.tscn",
	"res://scenes/components/server_card/server_card.tscn",
	"res://scenes/main_menu/main_menu.tscn",
	"res://scenes/network_map/network_map.tscn",
	"res://scenes/server/server_screen.tscn",
	"res://scenes/shop/shop_screen.tscn",
	"res://scenes/game_over/game_over.tscn",
]


func _ready() -> void:
	for p in PATHS:
		var r = load(p)
		print("PROBE ", "OK " if r else "FAIL ", p)
		if r is PackedScene:
			var inst = (r as PackedScene).instantiate()
			if inst == null:
				print("PROBE INSTANTIATE FAIL ", p)
			else:
				inst.queue_free()
	print("PROBE DONE")
