extends CanvasLayer
## Autoload: full-screen CRT + chromatic aberration + screen shake.
## All motion is authored in the AnimationPlayer ("impact", "glitch_small");
## this script only triggers them.

@export var shake_offset := Vector2.ZERO:
	set(v):
		shake_offset = v
		if is_inside_tree():
			get_viewport().canvas_transform = Transform2D(0.0, v)

@onready var overlay: ColorRect = $Overlay
@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	anim.animation_finished.connect(func(_n): _sync_overlay())
	set_crt_enabled(bool(MetaSave.get_value("settings", "crt", true)))


func set_crt_enabled(on: bool) -> void:
	(overlay.material as ShaderMaterial).set_shader_parameter("crt_enabled", on)
	MetaSave.set_value("settings", "crt", on)
	_sync_overlay()


## The overlay reads the whole screen texture every frame (expensive). With CRT off
## and no hit-effect playing it is hidden entirely, which costs nothing.
func _sync_overlay() -> void:
	overlay.visible = is_crt_enabled() or anim.is_playing()


func is_crt_enabled() -> bool:
	return bool((overlay.material as ShaderMaterial).get_shader_parameter("crt_enabled"))


## Old-TV switch-on: a bright line grows from the middle, then opens up and down.
## Skipped entirely when CRT is off. `once` lets callers ask for it only at game start.
var _powered := false


func power_on(once := true) -> void:
	if once and _powered:
		return
	_powered = true
	if not is_crt_enabled():
		return
	overlay.visible = true
	(overlay.material as ShaderMaterial).set_shader_parameter("power", 0.0)
	anim.play(&"crt_on")


## Unmitigated hit: violent chromatic aberration + heavy screen shake.
func impact() -> void:
	overlay.visible = true
	anim.play(&"impact")


## Small mechanical feedback glitch (weapon break, denied action).
func glitch_small() -> void:
	overlay.visible = true
	anim.play(&"glitch_small")
