class_name ViewModel
extends Node3D
## First-person arms and held items, attached to the head.
## The arms come from scenes/fps.tscn. Each hand's parts are grouped under a
## "rig" that sits on that hand's socket marker (HandSocketR / HandSocketL),
## and the equipped module of that hand is attached to the same rig, so the
## hand and the item move together (visible to enemies too).

const BOT_FPS_SCENE := preload("res://scenes/player/fps.tscn") # bots keep the original arms
const OPERATOR_FPS_SCENE := preload("res://scenes/player/character_fps.tscn")
const BOLT_SCENE := preload("res://scenes/items/bolt.tscn")
const KINETIC_SCENE := preload("res://scenes/items/kinetic.tscn")
const AEGIS_SCENE := preload("res://scenes/items/aegis.tscn")
const ORB_SCENE := preload("res://scenes/items/orb.tscn")
const AEGIS_HELD_SCENE := preload("res://scenes/items/aegis_held.tscn")
const EDGE_SCENE := preload("res://scenes/items/edge.tscn")
const BLAST_SCENE := preload("res://scenes/items/blast.tscn")
const VECTOR_SCENE := preload("res://scenes/items/vector.tscn")
const BOOST_SCENE := preload("res://scenes/items/boost.tscn")
const HEAL_SCENE := preload("res://scenes/items/heal.tscn")
# turns an item (authored with its muzzle on -Z) so it points along the character's forearm (-Y)
const EDGE_COMBO := ["slash_left", "slash_right", "poke"]
const COMBO_RESET_MS := 900
const HOLD_BASIS := Basis(Vector3.RIGHT, -PI / 2.0)
const AEGIS_HELD := 0.3  # small shield scale when held at the side
# Curved shield when in use: sized to cover the whole body and to match the
# 90 degree blocking arc in FluxComponent (edges ~48 deg either side).
const AEGIS_UP_SCALE := Vector3(1.6, 1.05, 1.6)
const AEGIS_UP_POS := Vector3(0.0, -0.6, -0.35)  # relative to the head
const AEGIS_RIG_UP := Vector3(0.0, -0.15, -0.5)  # where the hand rig moves while the shield is raised

var player: Player
var bolt_views: Array = [null, null]   # BoltView per hand
var aegis_nodes: Array = [null, null]  # curved shield (in use) per hand
var aegis_held: Array = [null, null]   # small shield (carried) per hand
var sleeve: Color = Color.WHITE
var base: Array = [Vector3.ZERO, Vector3.ZERO]      # rig rest position = hand socket
var palm_off: Array = [Vector3.ZERO, Vector3.ZERO]  # palm relative to the socket
var sockets3d: Array = []   # the character model's own HandSocketR / HandSocketL (what other players see)
var rigs: Array = []        # Node3D per hand (0 = right / LMB, 1 = left / RMB)
var hand_meshes: Array = [] # arm + hand meshes of fps.tscn (first-person only)
var items: Array = []       # Dictionary id -> Node3D per hand
var flashes: Array = []     # muzzle flash mesh per hand
var _shown: Array = ["", ""]
var _combo: Array = [0, 0]
var _combo_ms: Array = [0, 0]
var _kick: Array = [0.0, 0.0]
var _dip: Array = [0.0, 0.0]
var _t: float = 0.0


func setup(p: Player, sleeve_color: Color) -> void:
	player = p
	sleeve = sleeve_color
	name = "ViewModel"
	sockets3d = [p.model.get_node("ShoulderPivotR/ElbowPivotR/HandSocketR"), p.model.get_node("ShoulderPivotL/ElbowPivotL/HandSocketL")]

	# take the arms out of fps.tscn (we keep our own camera)
	var fps := (BOT_FPS_SCENE if p.is_bot else OPERATOR_FPS_SCENE).instantiate()
	var hands := fps.get_node("Camera3D/ViewModel") as Node3D
	var sockets: Array = [hands.get_node("HandSocketR"), hands.get_node("HandSocketL")]
	var palms: Array = [hands.get_node("PalmR"), hands.get_node("PalmL")]
	for h in 2:
		base[h] = (sockets[h] as Node3D).position
		palm_off[h] = (palms[h] as Node3D).position - (sockets[h] as Node3D).position
	var parts: Array = [[], []]
	for ch in hands.get_children():
		var n3 := ch as Node3D
		if n3 != null:
			parts[0 if n3.position.x > 0.0 else 1].append(n3)

	for h in 2:
		var rig := Node3D.new()
		rig.name = "HandR" if h == 0 else "HandL"
		rig.position = base[h]
		add_child(rig)
		rigs.append(rig)
		for n3: Node3D in parts[h]:
			hands.remove_child(n3)
			n3.owner = null # no longer part of fps.tscn: avoids the 'owner inconsistent' warnings
			rig.add_child(n3)
			n3.position -= base[h]
			var mi := n3 as MeshInstance3D
			if mi != null:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if String(mi.name).contains("Glow"):
					_tint(mi, sleeve)
				hand_meshes.append(mi)
		var d := {}
		for id in Loadout.ids():
			var it := _make_item(id, h)
			it.position = palm_off[h]
			it.visible = false
			rig.add_child(it)
			d[id] = it
		items.append(d)
	fps.free()


func _tint(mi: MeshInstance3D, c: Color) -> void:
	var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
	if src == null:
		return
	var m := src.duplicate() as StandardMaterial3D
	m.albedo_color = c.lerp(Color.WHITE, 0.3)
	m.emission = c
	mi.material_override = m


func _box(size: Vector3, c: Color, emissive: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, emissive)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _mat(c: Color, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _orb(c: Color, s: float, pos: Vector3) -> Node3D:
	var o := ORB_SCENE.instantiate() as OrbView
	o.scale = Vector3.ONE * s
	o.position = pos
	o.set_color(c, 0.8)
	return o


func _make_item(id: String, h: int) -> Node3D:
	var root := Node3D.new()
	match id:
		"kinetic":
			var g := KINETIC_SCENE.instantiate() as Node3D
			g.scale = Vector3.ONE * 1.6
			g.position = Vector3(0, 0.05, -0.02)
			root.add_child(g)
			var f := _box(Vector3(0.08, 0.08, 0.08), Color(1.0, 0.9, 0.4), true)
			f.position = g.position + (g.get_node("Muzzle") as Node3D).position * g.scale.x + Vector3(0, 0, -0.04)
			f.visible = false
			root.add_child(f)
			flashes.resize(2)
			flashes[h] = f
		"edge":
			# the blade is authored pointing up: tip it forward; its slash animation plays inside this holder
			var edge_hold := Node3D.new()
			edge_hold.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			edge_hold.position = Vector3(0, 0.04, -0.05)
			root.add_child(edge_hold)
			edge_hold.add_child(EDGE_SCENE.instantiate())
		"aegis":
			var small := AEGIS_HELD_SCENE.instantiate() as Node3D
			small.scale = Vector3.ONE * AEGIS_HELD
			small.position = Vector3(0, 0.04, -0.08)
			root.add_child(small)
			aegis_held[h] = small
			var sh := AEGIS_SCENE.instantiate() as Node3D
			sh.scale = AEGIS_UP_SCALE
			sh.position = AEGIS_UP_POS - AEGIS_RIG_UP - palm_off[h]
			sh.visible = false
			root.add_child(sh)
			aegis_nodes[h] = sh
		"boost":
			# the pad scene, shrunk to a puck in the palm (its trigger zone is not needed in hand)
			var pad := BOOST_SCENE.instantiate() as Node3D
			(pad.get_node("TriggerZone") as Area3D).monitoring = false
			pad.scale = Vector3.ONE * 0.18
			pad.position = Vector3(0, 0.1, -0.1)
			root.add_child(pad)
		"shift":
			root.add_child(_orb(Color(0.7, 0.4, 1.0), 0.6, Vector3(0, 0.1, -0.1)))
		"vector":
			var vec := VECTOR_SCENE.instantiate() as Node3D
			vec.scale = Vector3.ONE * 1.5
			vec.position = Vector3(0, 0.02, -0.02)
			root.add_child(vec)
		"blast":
			var blast := BLAST_SCENE.instantiate() as Node3D
			blast.position = Vector3(0, 0.0, 0.05)
			root.add_child(blast)
		"seeker":
			root.add_child(_orb(Color(0.4, 1.0, 0.4), 0.55, Vector3(0, 0.1, -0.15)))
		"bolt":
			# holder places/scales the rifle; the scene's own animations move the rifle inside it
			var hold := Node3D.new()
			hold.scale = Vector3.ONE * 0.6
			hold.position = Vector3(0, 0.054, -0.12)
			root.add_child(hold)
			var bv := BOLT_SCENE.instantiate() as BoltView
			hold.add_child(bv)
			bolt_views[h] = bv
		"bunker":
			var bk := _box(Vector3(0.28, 0.2, 0.05), Color(0.2, 0.75, 0.9))
			bk.position = Vector3(0, 0.08, -0.15)
			root.add_child(bk)
		"heal":
			var kit := HEAL_SCENE.instantiate() as Node3D
			kit.position = Vector3(0, 0.08, -0.1)
			root.add_child(kit)
		"ghost":
			root.add_child(_orb(Color(0.9, 0.95, 1.0), 0.5, Vector3(0, 0.1, -0.1)))
		"mirage":
			root.add_child(_orb(Color(0.8, 0.3, 0.9), 0.5, Vector3(0, 0.1, -0.1)))
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## World position of a held item's barrel (the kinetic scene's Muzzle node); ZERO if not found.
func muzzle_of(id: String, h: int) -> Vector3:
	if h >= items.size() or not items[h].has(id):
		return Vector3.ZERO
	var m := (items[h][id] as Node).find_child("Muzzle", true, false) as Node3D
	return m.global_position if m != null else Vector3.ZERO


## Plays an animation from the held item scene's own AnimationPlayer.
func _play_anim(h: int, id: String, anim: String) -> void:
	var ap := (items[h][id] as Node).find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and ap.has_animation(anim):
		ap.stop()
		ap.play(anim)


## Edge combo: left swing, right swing, poke, then around again. A pause restarts it.
func _next_combo(h: int) -> String:
	var now: int = Time.get_ticks_msec()
	if now - _combo_ms[h] > COMBO_RESET_MS:
		_combo[h] = 0
	_combo_ms[h] = now
	var anim: String = EDGE_COMBO[_combo[h] % EDGE_COMBO.size()]
	_combo[h] += 1
	return anim


func kick_cast() -> void:
	for h in 2:
		if _shown[h] in ["vector", "blast", "seeker", "bunker"]:
			_kick[h] = 1.0
			if _shown[h] == "blast":
				_play_anim(h, "blast", "fire")


func kick_by_id(id: String) -> void:
	for h in 2:
		if _shown[h] == id:
			_kick[h] = 1.0
			if id == "edge":
				_play_anim(h, "edge", _next_combo(h))
			if id == "bolt" and bolt_views[h] != null:
				bolt_views[h].play_fire()
			if id == "kinetic" and h < flashes.size() and flashes[h] != null:
				flashes[h].visible = true


func _process(delta: float) -> void:
	if player == null or player.flux == null:
		return
	var fl: FluxComponent = player.flux
	_t += delta * (4.0 + player.move_speed)
	var moving: float = clampf(player.move_speed / 6.0, 0.0, 1.5)
	# other players already have arms on their character model: show only the held item
	for hm in hand_meshes:
		(hm as MeshInstance3D).visible = player.is_local
	for h in 2:
		var id := ""
		var m = player.active_module(h)
		if m != null:
			id = m.data.id
		if id != _shown[h]:
			for k in items[h]:
				items[h][k].visible = (k == id)
			_shown[h] = id
			_dip[h] = 1.0
			if id == "bolt" and bolt_views[h] != null:
				bolt_views[h].play_equip()
		_kick[h] = move_toward(_kick[h], 0.0, delta * 6.0)
		_dip[h] = move_toward(_dip[h], 0.0, delta * 4.0)
		if h < flashes.size() and flashes[h] != null and _kick[h] < 0.7:
			flashes[h].visible = false
		var pos: Vector3 = base[h]
		pos.y += sin(_t + h * PI) * 0.012 * moving
		pos.x += cos(_t * 0.5 + h * PI) * 0.01 * moving
		pos.y -= _dip[h] * 0.3
		pos.z += _kick[h] * 0.08
		var rot := Vector3.ZERO
		if id == "edge":
			pos.z -= _kick[h] * 0.2 # the swing itself is the scene's slash animation
		if aegis_nodes[h] != null:
			var up: bool = fl.shield_on and id == "aegis"
			aegis_nodes[h].visible = up
			aegis_held[h].visible = not up
		if id == "heal":
			# the kit shows whether the heal is still available and is raised while it is working
			var kit_root := items[h]["heal"] as Node3D
			(kit_root.find_child("Cross", true, false) as Node3D).visible = not fl.heal_used
			var kap := kit_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if kap != null:
				kap.speed_scale = 3.5 if fl.healing else 1.0
			if fl.healing:
				pos.y += 0.1
				pos.z -= 0.08
		if id == "aegis" and fl.shield_on:
			pos = AEGIS_RIG_UP
		if fl.hand_off(h):
			pos.y -= 0.25
			rot.x = -0.6
		var rig: Node3D = rigs[h]
		if player.is_local:
			rig.position = rig.position.lerp(pos, clampf(delta * 18.0, 0.0, 1.0))
			rig.rotation = rig.rotation.lerp(rot, clampf(delta * 18.0, 0.0, 1.0))
		else:
			# other players: the character's own arm raises and the item sits in its hand
			var sock := sockets3d[h] as Node3D
			rig.global_transform = Transform3D(sock.global_basis * HOLD_BASIS, sock.global_position)
			player.model.pose_arm(h, id != "", player.head.rotation.x, fl.hand_off(h), delta)
