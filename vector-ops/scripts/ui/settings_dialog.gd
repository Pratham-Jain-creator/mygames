extends Control
## Settings (scenes/ui/settings_dialog.tscn), shared by the start menu and the
## pause menu. Sliders write straight into GameState / the audio bus, and the
## values are saved to disk whenever the dialog is closed.


func _ready() -> void:
	%SensSlider.value = GameState.sens_mult
	%FovSlider.value = GameState.fov_setting
	%VolSlider.value = GameState.master_volume
	_on_sens(%SensSlider.value)
	_on_fov(%FovSlider.value)
	_on_vol(%VolSlider.value)
	%SensSlider.value_changed.connect(_on_sens)
	%FovSlider.value_changed.connect(_on_fov)
	%VolSlider.value_changed.connect(_on_vol)
	%BtnClose.pressed.connect(func() -> void: visible = false)
	visibility_changed.connect(func() -> void:
		if not visible:
			SaveData.save_all())


func _on_sens(v: float) -> void:
	GameState.sens_mult = v
	%SensValue.text = "%.2fx" % v


func _on_fov(v: float) -> void:
	GameState.fov_setting = v
	%FovValue.text = "%d" % v


func _on_vol(v: float) -> void:
	GameState.master_volume = v
	SaveData.apply_audio()
	%VolValue.text = "%.2f" % v
