class_name PlayerModel
extends Node3D
## Logic for scenes/player.tscn (the character). Geometry and animations live
## in the scene; this only tints, fades and picks idle / walk.

## Meshes whose name contains one of these get the team colour.
const TINT_KEYS := ["Glow", "Core", "Buckle", "Visor", "Team"]
## These are painted fully in the team colour (chest, back and helmet crest),
## so friend and foe read from every side.
const SOLID_KEYS := ["Team"]

var _meshes: Array = []
var _tinted: Array = []


func _ready() -> void:
	# the arms are posed by pose_arm() (they hold the equipped items), so the animations must not move them
	var ap := get_node_or_null("Anim") as AnimationPlayer
	if ap == null:
		return
	for n in ap.get_animation_list():
		var a: Animation = ap.get_animation(n)
		for i in a.get_track_count():
			if String(a.track_get_path(i)).begins_with("ShoulderPivot"):
				a.track_set_enabled(i, false)


func _collect() -> void:
	if not _meshes.is_empty():
		return
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		_meshes.append(mi)
		for k in TINT_KEYS:
			if String(mi.name).contains(k):
				_tinted.append(mi)
				break


## Safe to call before the model enters the tree.
func set_team_color(c: Color) -> void:
	_collect()
	var cache := {}
	for mi: MeshInstance3D in _tinted:
		var src := mi.mesh.material as StandardMaterial3D
		if src == null:
			continue
		var solid := false
		for k in SOLID_KEYS:
			if String(mi.name).contains(k):
				solid = true
		var key := str(src.get_instance_id()) + ("s" if solid else "t")
		if not cache.has(key):
			var m := src.duplicate() as StandardMaterial3D
			m.albedo_color = c if solid else c.lerp(Color.WHITE, 0.3)
			if m.emission_enabled:
				m.emission = c
			cache[key] = m
		mi.material_override = cache[key]
	var light := get_node_or_null("Light") as OmniLight3D
	if light != null:
		light.light_color = c


## 1.0 = solid, 0.0 = invisible (Mirage).
func set_fade(alpha: float) -> void:
	_collect()
	for mi: MeshInstance3D in _meshes:
		mi.transparency = 1.0 - alpha
	var light := get_node_or_null("Light") as OmniLight3D
	if light != null:
		light.visible = alpha > 0.5


func set_shadows(on: bool) -> void:
	_collect()
	var s := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi: MeshInstance3D in _meshes:
		mi.cast_shadow = s


## Emitted by the walk / run animations (method tracks) at the instant a foot lands.
signal footstep(foot: int)

## idle / walk / run / slide / air - what the character is currently playing.
var state := "idle"


## Raises one arm to hold an item out in front (aimed with the head pitch), or lets it hang.
## hand 0 = right arm, 1 = left arm.
func pose_arm(hand: int, holding: bool, pitch: float, hurt: bool, delta: float) -> void:
	var side := "R" if hand == 0 else "L"
	var shoulder := get_node_or_null("ShoulderPivot" + side) as Node3D
	if shoulder == null:
		return
	var elbow := shoulder.get_node("ElbowPivot" + side) as Node3D
	var up := 0.0
	var bend := 0.0
	if holding and not hurt:
		up = clampf(1.3 + pitch, 0.4, 2.6) # ~75 degrees forward, follows where the head looks
		bend = 0.35
	var k := clampf(delta * 14.0, 0.0, 1.0)
	shoulder.rotation = shoulder.rotation.lerp(Vector3(up, 0.0, 0.0), k)
	elbow.rotation = elbow.rotation.lerp(Vector3(bend, 0.0, 0.0), k)


## The head follows where the player looks (models without a HeadPivot, like the bots', ignore it).
## pitch > 0 looks up, yaw > 0 turns toward the character's left.
func set_head_look(pitch: float, yaw: float, delta: float) -> void:
	var pivot := get_node_or_null("HeadPivot") as Node3D
	if pivot == null:
		return
	var target := Vector3(clampf(pitch, -0.8, 0.8), clampf(yaw, -0.9, 0.9), 0.0)
	pivot.rotation = pivot.rotation.lerp(target, clampf(delta * 10.0, 0.0, 1.0))


## Called from the animation's method tracks: foot 0 = left, 1 = right.
func step(foot: int) -> void:
	footstep.emit(foot)


## speed = smoothed horizontal speed; mode = "ground", "air" or "slide".
## Switching uses a small hysteresis and a cross-fade so it never flickers.
func update_motion(speed: float, mode: String = "ground", delta: float = 0.016) -> void:
	var anim := get_node_or_null("Anim") as AnimationPlayer
	if anim == null or not anim.is_inside_tree():
		return
	var want: String
	if mode != "ground":
		want = mode
	elif state == "run":
		want = "run" if speed > 7.0 else ("walk" if speed > 0.4 else "idle")
	elif state == "walk":
		want = "run" if speed > 7.6 else ("walk" if speed > 0.4 else "idle")
	else:
		want = "run" if speed > 7.6 else ("walk" if speed > 0.7 else "idle")
	if want != state or anim.current_animation != want:
		state = want
		anim.play(want, 0.2)
	var target := 1.0
	if want == "walk":
		target = clampf(speed / 6.0, 0.6, 1.5)
	elif want == "run":
		target = clampf(speed / 9.0, 0.8, 1.3)
	anim.speed_scale = lerpf(anim.speed_scale, target, clampf(delta * 8.0, 0.0, 1.0))
