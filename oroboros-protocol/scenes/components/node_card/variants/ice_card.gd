class_name IceCard
extends NodeCard
## ICE (Enemy). Pulses crimson on hover and previews the damage it will deal.


func _ready() -> void:
	super()
	node_type = Enums.NodeType.ICE


func _hover_animation(hovered: bool) -> void:
	z_index = 10 if hovered else (5 if selected else 0)
	if hovered:
		play_anim(&"hover_in")
		anim.queue(&"pulse")
	else:
		play_anim(&"hover_out")


func on_weapon_changed(weapon: WeaponState, enabled: bool) -> void:
	if data == null or face_down:
		_damage_label.visible = false
		_frame.divider = false
		return
	# Glitch keeps its damage read-out: a thin line, then the number centred below it.
	_frame.divider = true
	_damage_label.visible = true
	_damage_label.offset_left = 14.0
	_damage_label.offset_right = 146.0
	_damage_label.offset_top = 190.0
	_damage_label.offset_bottom = 218.0
	_damage_label.add_theme_font_size_override("font_size", 22)
	var v := data.eff_value
	if weapon != null and enabled and v <= weapon.ceiling:
		var dmg := maxi(0, v - weapon.strength)
		_damage_label.text = "-%d" % dmg if dmg > 0 else "SAFE"
		_damage_label.add_theme_color_override("font_color", Enums.COL_ICE if dmg > 0 else Enums.COL_COOLANT)
	else:
		_damage_label.text = "-%d RAW" % v
		_damage_label.add_theme_color_override("font_color", Enums.COL_ICE)


func show_forecast(f: Dictionary) -> void:
	if data == null or face_down or not _damage_label.visible:
		return
	var dmg := int(f.get("dmg", 0))
	if bool(f.get("raw", true)):
		_damage_label.text = "-%d RAW" % dmg
		_damage_label.add_theme_color_override("font_color", Enums.COL_ICE)
	else:
		_damage_label.text = "-%d" % dmg if dmg > 0 else "SAFE"
		_damage_label.add_theme_color_override("font_color", Enums.COL_ICE if dmg > 0 else Enums.COL_COOLANT)


func _describe() -> String:
	var sv: ServerState = RunState.server
	var txt := "Glitch: your Protocol corrupts the Server. Resolving it damages the Server's Integrity by its value minus your Firewall Base Strength (min 0). Unblocked damage [b]overclocks[/b] the Server: +1 Overclock for the rest of the Server.\nWith no usable Firewall the Server takes the full [b]%d[/b]." % data.eff_value
	if sv != null and sv.weapon != null:
		var w := sv.weapon
		if data.eff_value <= w.ceiling:
			txt += "\n\n[color=#FFB400]Equipped Firewall (STR %d): Integrity damage %d. Ceiling would drop to %d.[/color]" % [w.strength, maxi(0, data.eff_value - w.strength), data.eff_value - 1]
		else:
			txt += "\n\n[color=#FF003C]Your Firewall's ceiling (%s) is too low to target this Glitch.[/color]" % w.ceiling_text()
	return txt
