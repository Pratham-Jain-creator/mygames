extends Control
## LAN dialog (scenes/ui/play_dialog.tscn): host a match or join by IP.
## It only reports what the player chose; the menu starts the session.

signal host_requested
signal join_requested(ip: String)


func _ready() -> void:
	%BtnHost.pressed.connect(func() -> void: host_requested.emit())
	%BtnJoin.pressed.connect(func() -> void: join_requested.emit(%IpEdit.text.strip_edges()))
	%BtnClose.pressed.connect(func() -> void: visible = false)
