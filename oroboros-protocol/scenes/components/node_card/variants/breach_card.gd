class_name BreachCard
extends NodeCard
## Breach Protocol (Weapon). Shows both variables: etched Base Strength and the
## overlaid Target Ceiling.


func _ready() -> void:
	super()
	node_type = Enums.NodeType.BREACH


func _on_refreshed() -> void:
	var bonus := 3 if RunState.has_daemon("sharp_edge") else 0
	_set_effect("ABSORBS %d" % (data.eff_value + bonus))


func _describe() -> String:
	return "Firewall: a barrier against Glitches. Equipping replaces your current Firewall.\n[b]Base Strength[/b] (%d) is how much Glitch damage it blocks and never decreases.\n[b]Target Ceiling[/b] is the highest Glitch it can target; after each hit it drops to exactly Glitch value - 1." % data.eff_value
