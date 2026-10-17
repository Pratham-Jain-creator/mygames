class_name DataCacheCard
extends NodeCard
## Data Cache (Score). Counts double as Base Data.


func _on_refreshed() -> void:
	_set_effect("+%d" % (data.eff_value * 2))


func _describe() -> String:
	return "Siphon: mines raw bytes. When resolved it adds [b]%d[/b] Base Bytes (value x2).\nBest paired in [b]Bulk Siphon[/b] (3 Siphons) or [b]Cache Clear[/b] (Firewall + 2 Siphons)." % (data.eff_value * 2)
