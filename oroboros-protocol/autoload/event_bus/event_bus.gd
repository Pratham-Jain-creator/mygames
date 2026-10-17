extends Node
## Global signal hub. Keeps HUD widgets decoupled from game logic.

signal money_changed(value: int)
signal health_changed(old_value: int, new_value: int, max_value: int)
signal daemons_changed
signal consumables_changed
signal deck_changed
signal room_changed
signal toast_requested(text: String, color: Color)
signal daemon_popup(uid: int, text: String)
