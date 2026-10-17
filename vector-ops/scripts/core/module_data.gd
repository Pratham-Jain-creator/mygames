class_name ModuleData
extends Resource
## Everything that describes one combat module, kept in a .tres file under
## res://data/modules/ so it can be tuned in the Inspector without touching code.
##
## The text fields are templates: "{cost}", "{damage}", "{cooldown}", "{range}",
## "{weight}" and every key of `tuning` are filled in from the numbers below, so
## the picker, the guide and the HUD can never disagree with the real stats.

@export_group("Identity")
@export var id: String = ""
@export var display_name: String = ""
@export_enum("WEAPON", "DEFENSE", "MOBILITY", "STEALTH") var category: String = "WEAPON"
@export var color: Color = Color.WHITE
@export var weight: float = 1.0
@export_file("*.gd") var script_path: String = ""

@export_group("Text")
## One line under the module name on the HUD hand card.
@export var hud_meta_template: String = ""
@export_multiline var description_template: String = ""

@export_group("Stats")
## Flux spent per use (per shot, per placement, base cost...).
@export var cost: float = 0.0
## Seconds before the module can be used again.
@export var cooldown: float = 0.0
## Damage of one hit.
@export var damage: float = 0.0
## Reach in metres (weapon range, lock range, blink distance...).
@export var range_m: float = 0.0
## Module-specific numbers (projectile speed, radius, spread...). Read with tune().
@export var tuning: Dictionary = {}

## Description with the numbers filled in.
var description: String:
	get:
		return description_template.format(_vars())

## HUD line with the numbers filled in.
var hud_meta: String:
	get:
		return hud_meta_template.format(_vars())


## A module-specific number from `tuning`.
func tune(key: StringName) -> float:
	if not tuning.has(key) and not tuning.has(String(key)):
		push_error("Module '%s' has no tuning value '%s'" % [id, key])
		return 0.0
	return float(tuning.get(key, tuning.get(String(key), 0.0)))


func _vars() -> Dictionary:
	var v: Dictionary = {
		"cost": _fmt(cost), "cooldown": _fmt(cooldown), "damage": _fmt(damage),
		"range": _fmt(range_m), "weight": _fmt(weight),
	}
	for k in tuning:
		v[String(k)] = _fmt(float(tuning[k]))
	return v


static func _fmt(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(snappedf(x, 0.01))
