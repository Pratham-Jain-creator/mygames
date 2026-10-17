class_name PauseMenu
extends Control
## Pause overlay (scenes/ui/pause_menu.tscn), opened with ESC during a session.
## Playing alone it freezes the game. With other players connected it only frees
## the mouse (GameState.paused_ui), because the match keeps running for them.

const NOTE_FLUX := "[color=#43e0c6]■[/color] [color=#8ca3ad]Standing still accelerates Flux recovery.[/color]"
const NOTE_WARN := "[color=#e05263]■[/color] [color=#8ca3ad]Fractured Flux reduces max pool until next round.[/color]"


func _ready() -> void:
	%BtnResume.pressed.connect(close)
	%BtnSettings.pressed.connect(func() -> void: %SettingsDialog.visible = true)
	%BtnDisconnect.pressed.connect(_on_leave_match)
	%BtnQuit.pressed.connect(func() -> void: get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or not GameState.in_session:
		return
	get_viewport().set_input_as_handled()
	if %SettingsDialog.visible:
		%SettingsDialog.visible = false
	elif visible:
		close()
	else:
		open()


func open() -> void:
	_refresh_summary()
	visible = true
	GameState.paused_ui = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if multiplayer.get_peers().is_empty():
		get_tree().paused = true


func close() -> void:
	%SettingsDialog.visible = false
	visible = false
	GameState.paused_ui = false
	get_tree().paused = false


func _on_leave_match() -> void:
	close()
	GameState.leave_match()


func _refresh_summary() -> void:
	var loadout: Array = GameState.local_loadout
	var text := ""
	for h in Loadout.HANDS:
		text += "[color=#7f99a3]%s[/color]\n" % ("RIGHT HAND (%s / %s)" % [ControlHints.key(&"fire"), ControlHints.key(&"rotate_right")] if h == 0 else "LEFT HAND (%s / %s)" % [ControlHints.key(&"fire_left"), ControlHints.key(&"rotate_left")])
		var parts: PackedStringArray = []
		for s in Loadout.SLOTS_PER_HAND:
			var id: String = loadout[h][s]
			if id != "":
				var d := Loadout.get_data(id)
				parts.append("%d. %s (wt %d)" % [s + 1, d.display_name, int(d.weight)])
		text += "[color=#edf5f7]%s[/color]\n\n" % ("   ".join(parts) if not parts.is_empty() else "-")
	text += "[color=#7f99a3]MAX FLUX[/color]  [color=#43e0c6]%d[/color]\n\n" % int(Loadout.max_flux(loadout))
	text += NOTE_FLUX + "\n" + NOTE_WARN
	%LoadoutSummary.text = text
