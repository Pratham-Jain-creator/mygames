class_name OrbView
extends Node3D
## Reusable glowing orb (scenes/orb.tscn). Call set_color() to reuse it for
## different things: Seeker, Shift, Ghost, Mirage, projectiles...


func _ready() -> void:
	for n in find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Tints the orb. Safe to call before the orb enters the tree. Materials are
## duplicated so other orbs keep their own colour.
func set_color(c: Color, light_energy: float = -1.0) -> OrbView:
	var core := $Core as MeshInstance3D
	var glow := $Glow as MeshInstance3D
	var light := $Light as OmniLight3D
	var cm := (core.mesh.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	cm.albedo_color = c.lerp(Color.WHITE, 0.7)
	cm.emission = c
	core.material_override = cm
	var gm := (glow.mesh.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	gm.albedo_color = Color(c.r, c.g, c.b, gm.albedo_color.a)
	gm.emission = c
	glow.material_override = gm
	light.light_color = c
	if light_energy >= 0.0:
		light.light_energy = light_energy
	return self
