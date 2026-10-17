class_name CoolantCard
extends NodeCard
## Coolant (Healing).


func _ready() -> void:
	super()
	node_type = Enums.NodeType.COOLANT


func _on_refreshed() -> void:
	var amount := int(floor(data.eff_value * (2 if RunState.has_daemon("antivirus") else 1) * RunState.patch_factor()))
	_set_effect("HEAL %d" % amount)


func _describe() -> String:
	var amount := int(floor(data.eff_value * (2 if RunState.has_daemon("antivirus") else 1) * RunState.patch_factor()))
	if RunState.patch_factor() <= 0.0:
		return "[color=#FF003C]%s:[/color] this Patch restores nothing." % BossDB.name_of(RunState.server.boss_id).to_upper()
	if RunState.patch_factor() < 1.0:
		return "[color=#FF003C]%s:[/color] this Patch restores only [b]%d[/b] Integrity." % [BossDB.name_of(RunState.server.boss_id).to_upper(), amount]
	return "Repairs [b]%d[/b] Integrity when resolved (up to the maximum)." % amount
