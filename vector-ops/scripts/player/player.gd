class_name Player
extends CharacterBody3D
## First-person operator (Milestones 0, 2, 3).
##
## Networking model
##  - Movement: owner-authoritative. The controlling peer (the client for a
##    human, the server for a bot) simulates and replicates position/rotation.
##  - Flux, shield, active slot: server-authoritative (FluxComponent has
##    authority 1). The controller asks for actions via request(); the server
##    validates, spends Flux and applies effects.

class Cmd:
	var move: Vector2 = Vector2.ZERO # x = right, y = forward
	var jump: bool = false
	var sprint: bool = false
	var slide_pressed: bool = false
	# index 0 = right hand (LMB), 1 = left hand (RMB)
	var fire_held: Array = [false, false]
	var fire_pressed: Array = [false, false]

	# rotate equipment: [right hand (E), left hand (Q)]
	var rotate: Array = [false, false]

	func clear_fire() -> void:
		fire_held = [false, false]
		fire_pressed = [false, false]
		rotate = [false, false]
		slide_pressed = false

const GRAVITY := 22.0
const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 8.0 # ~1.45 m: clears the low containers (<= 1.35 m), not the big ones
const LADDER_SPEED := 2.2
const EYE_HEIGHT := 1.6
const SLIDE_EYE_HEIGHT := 0.95
const SLIDE_TIME := 1.0
const SLIDE_MIN_SPEED := 2.0 # you must be moving at least this fast to start a slide
const SLIDE_COOLDOWN := 0.9
const MOUSE_SENS := 0.0022
const MAX_BUNKERS := 6
const ATTACK_IDS := ["kinetic", "edge", "blast", "bolt", "seeker"] # using these drops the Mirage cloak

# --- gamepad look + light aim assist (only used while the last input was a pad) ---
const PAD_LOOK_SPEED := 3.4 # rad/s at full stick deflection
const ASSIST_CONE := 0.105 # ~6 degrees around the crosshair
const ASSIST_RANGE := 70.0
const ASSIST_PULL := 3.0 # how fast the crosshair is eased onto the target (per second)
const ASSIST_SLOW := 0.6 # stick turn speed multiplier while a target is under the crosshair

var peer_id: int = 1
var team: int = 0
var is_bot: bool = false
var is_local: bool = false
var display_name: String = "Operator"
var slot_ids: Array = []
var flux: FluxComponent
var head: Node3D
var camera: Camera3D
const BOT_MODEL_SCENE := preload("res://scenes/player/player.tscn") # bots keep the original character
const OPERATOR_MODEL_SCENE := preload("res://scenes/player/character.tscn") # human players
const ORB_SCENE := preload("res://scenes/items/orb.tscn")
const BUNKER_SCENE := preload("res://scenes/combat/bunker.tscn")
const BOOST_SCENE := preload("res://scenes/items/boost.tscn")
var model: PlayerModel
var name_label: Label3D
var modules: Array = []
var cmd: Cmd = Cmd.new()
var brain: Node = null
var yaw: float = 0.0
var pitch: float = 0.0

var _ladders: int = 0
var _applied: Array = [-1, -1]
var _rot_guard: float = 0.0
var _was_ejected: bool = false
var _sprint_sent: bool = false
var _last_pos: Vector3 = Vector3.ZERO
var viewmodel: ViewModel
var hum: AudioStreamPlayer3D
var on_ground: bool = true # replicated: lets every peer pick the right animation / sound
var slide_on: bool = false # replicated
var _was_ground: bool = true
var _was_sliding: bool = false
var _air_t: float = 0.0
var _fall_v: float = 0.0
var run_on: bool = false # F toggles running
var _slide_t: float = 0.0
var _slide_req: bool = false # Shift pressed since the last physics tick (latched so it can't be missed)
var _slide_cd: float = 0.0
var _slide_dir: Vector2 = Vector2.ZERO
var _slide_speed: float = 0.0
var _keep_mom: bool = false # jumped out of a slide: horizontal momentum carries
var spread_deg: float = 0.2
var move_speed: float = 0.0
var _heart_t: float = 0.0
var _mir_key: int = -1
var _pviz: Dictionary = {}
var _bunker_ids: Array = []
var scoped: bool = false # Bolt scope: zoomed, frozen in place
var _fire_block: Array = [false, false] # button ignored until released


## Builds the whole node tree. Called by the MultiplayerSpawner spawn function
## on every peer, so the structure is identical everywhere.
func setup(d: Dictionary) -> void:
	name = "P%d" % int(d["id"])
	peer_id = int(d["peer"])
	team = int(d["team"])
	is_bot = bool(d["bot"])
	display_name = String(d["name"])
	slot_ids = Loadout.sanitize(d["loadout"])
	position = d["pos"]
	yaw = float(d["yaw"])
	rotation.y = yaw
	_last_pos = position
	collision_layer = 2
	collision_mask = 3

	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)

	var col := Color(0.25, 0.55, 1.0) if team == 0 else Color(1.0, 0.55, 0.15)
	model = (BOT_MODEL_SCENE if is_bot else OPERATOR_MODEL_SCENE).instantiate() as PlayerModel
	model.name = "Model"
	add_child(model)
	model.set_team_color(col)
	model.footstep.connect(_on_footstep) # fired by the walk / run animation when a foot lands

	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE_HEIGHT
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 85.0
	camera.near = 0.03
	head.add_child(camera)

	viewmodel = ViewModel.new()
	head.add_child(viewmodel)
	viewmodel.setup(self, col)

	hum = AudioStreamPlayer3D.new()
	hum.name = "Hum"
	hum.stream = Sfx.stream("hum")
	hum.volume_db = -14.0
	hum.max_distance = 20.0
	hum.unit_size = 5.0
	head.add_child(hum)

	name_label = Label3D.new()
	name_label.name = "Nameplate"
	name_label.text = display_name
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.pixel_size = 0.006
	name_label.position.y = 2.2
	name_label.modulate = col
	name_label.visible = false
	add_child(name_label)

	flux = FluxComponent.new()
	flux.name = "Flux"
	flux.player = self
	flux.max_flux = Loadout.max_flux(slot_ids)
	flux.active_flux = flux.max_flux
	add_child(flux)
	flux.build_sync()

	# modules: modules[hand][slot] (Module or null)
	for h in Loadout.HANDS:
		var row: Array = []
		for s in Loadout.SLOTS_PER_HAND:
			var id: String = slot_ids[h][s]
			if id == "":
				row.append(null)
				continue
			var m: Module = Loadout.create_module(id)
			m.setup(self, h, s)
			add_child(m)
			row.append(m)
		modules.append(row)
		flux.set_slot(h, Loadout.first_slot(slot_ids[h]))

	# replicated movement
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":position", ":rotation", "Head:rotation", ":on_ground", ":slide_on"]:
		var np := NodePath(prop)
		cfg.add_property(np)
		cfg.property_set_replication_mode(np, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = cfg
	add_child(sync)

	# bots are simulated by the server
	if is_bot:
		var agent := NavigationAgent3D.new()
		agent.name = "NavAgent"
		agent.path_desired_distance = 1.0
		agent.target_desired_distance = 1.5
		agent.radius = 0.5
		agent.height = 1.8
		add_child(agent)
		if GameState.multiplayer.is_server():
			brain = BotBrain.new()
			add_child(brain)
			brain.setup(self)

	set_multiplayer_authority(1 if is_bot else peer_id)
	flux.set_multiplayer_authority(1)


func _ready() -> void:
	add_to_group("players")
	is_local = (not is_bot) and peer_id == multiplayer.get_unique_id()
	if is_local:
		camera.current = true
		model.visible = false
		GameState.local_team = team
	# equip each hand's current slot
	for h in 2:
		_apply_slot(h)


# --- helpers used by modules / bots -----------------------------------------

func active_module(hand: int) -> Module:
	var row: Array = modules[hand]
	var s: int = flux.slot_of(hand)
	if s < 0 or s >= row.size():
		return null
	return row[s]


func _apply_slot(hand: int) -> void:
	var s: int = flux.slot_of(hand)
	if _applied[hand] == s:
		return
	var row: Array = modules[hand]
	if _applied[hand] >= 0 and row[_applied[hand]] != null:
		row[_applied[hand]].deactivate()
	_applied[hand] = s
	if row[s] != null:
		row[s].activate()


func eye_pos() -> Vector3:
	return global_position + Vector3(0, head.position.y, 0)


func aim_dir() -> Vector3:
	return -head.global_transform.basis.z


func world_move_dir() -> Vector3:
	var fwd: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var v: Vector3 = right * cmd.move.x + fwd * cmd.move.y
	v.y = 0.0
	return v


func ladder_enter() -> void:
	_ladders += 1


func ladder_exit() -> void:
	_ladders = maxi(0, _ladders - 1)


# --- input & simulation ------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or flux.ejected:
		return
	if event.is_action_pressed("slide") and not event.is_echo():
		_slide_req = true
	var mm := event as InputEventMouseMotion
	if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = MOUSE_SENS * GameState.sens_mult * (0.35 if scoped else 1.0)
		yaw -= mm.relative.x * sens
		pitch = clampf(pitch - mm.relative.y * sens, -1.5, 1.5)


func _collect_input(live: bool) -> void:
	var active: bool = live and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not active:
		cmd.move = Vector2.ZERO
		cmd.jump = false
		cmd.sprint = false
		cmd.clear_fire()
		return
	cmd.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	cmd.jump = Input.is_action_pressed("jump")
	if Input.is_action_just_pressed("toggle_run"):
		run_on = not run_on
	cmd.sprint = run_on
	cmd.slide_pressed = _slide_req or Input.is_action_just_pressed("slide")
	_slide_req = false
	cmd.fire_held = [Input.is_action_pressed("fire"), Input.is_action_pressed("fire_left")]
	cmd.fire_pressed = [Input.is_action_just_pressed("fire"), Input.is_action_just_pressed("fire_left")]
	cmd.rotate = [Input.is_action_just_pressed("rotate_right"), Input.is_action_just_pressed("rotate_left")]


func _physics_process(delta: float) -> void:
	if flux.ejected:
		if not _was_ejected:
			_on_ejected()
		return
	for h in 2:
		_apply_slot(h)
	if GameState.phase != GameState.Phase.LIVE:
		scoped = false
	if is_multiplayer_authority():
		_controller_step(delta)
	_step_audio(delta)


## Mirage: body fades out (almost fully for enemies, half for teammates).
func _update_mirage() -> void:
	var mir: bool = flux.stealth == 2
	var enemy_view: bool = (not is_local) and team != GameState.local_team
	var key: int = (1 if mir else 0) + (2 if enemy_view else 0)
	if key == _mir_key:
		return
	_mir_key = key
	model.set_fade(((0.03 if enemy_view else 0.35) if mir else 1.0))
	var cloaked: bool = mir and enemy_view
	model.set_shadows(not cloaked)
	viewmodel.visible = not cloaked


func is_sprinting() -> bool:
	return _sprint_sent


func _exit_tree() -> void:
	for id in _pviz:
		if is_instance_valid(_pviz[id]["node"]):
			_pviz[id]["node"].queue_free()
	_pviz.clear()


func _process(delta: float) -> void:
	# projectile mirrors that stopped receiving updates
	var nowms: int = Time.get_ticks_msec()
	for id in _pviz.keys():
		if nowms - int(_pviz[id]["t"]) > 500:
			if is_instance_valid(_pviz[id]["node"]):
				_pviz[id]["node"].queue_free()
			_pviz.erase(id)
	if flux.ejected:
		return
	model.update_motion(move_speed, "slide" if slide_on else ("ground" if on_ground else "air"), delta)
	if not is_local:
		model.set_head_look(head.rotation.x, 0.0, delta)
	_update_mirage()
	if is_local:
		camera.fov = lerpf(camera.fov, 22.0 if scoped else GameState.fov_setting + (10.0 if _slide_t > 0.0 else 0.0), clampf(delta * 14.0, 0.0, 1.0))
		viewmodel.visible = not scoped
		# the camera drops while sliding
		head.position.y = lerpf(head.position.y, SLIDE_EYE_HEIGHT if _slide_t > 0.0 else EYE_HEIGHT, clampf(delta * 14.0, 0.0, 1.0))
	if flux.shield_on and not hum.playing:
		hum.play()
	elif not flux.shield_on and hum.playing:
		hum.stop()
	# low-Flux heartbeat on other players (audible cue to finish them)
	if not is_local:
		var low: bool = flux.total_flux() < flux.max_flux * 0.3 or flux.active_flux < flux.max_flux * 0.1
		if low:
			_heart_t -= delta
			if _heart_t <= 0.0:
				_heart_t = 0.85
				Sfx.play_3d(self, "heart", global_position + Vector3(0, 1.2, 0), 2.0, 15.0)
	name_label.visible = (not is_local) and team == GameState.local_team and not flux.ejected


## Gamepad: right stick turns the view (response curve), and when an enemy is
## near the crosshair the stick slows down and the aim is eased toward them
## while you steer or fire. Mouse players never run this.
func _pad_look(delta: float, live: bool) -> void:
	var v: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.15)
	var mag: float = v.length()
	var look: Vector2 = v.normalized() * pow(mag, 1.7) if mag > 0.0 else Vector2.ZERO
	var tgt: Node = _assist_target() if live else null
	var rate: float = PAD_LOOK_SPEED * GameState.sens_mult * (0.4 if scoped else 1.0)
	if tgt != null:
		rate *= ASSIST_SLOW
	yaw -= look.x * rate * delta
	pitch = clampf(pitch - look.y * rate * delta, -1.5, 1.5)
	if tgt != null and (mag > 0.1 or cmd.fire_held[0] or cmd.fire_held[1]):
		var d: Vector3 = (tgt.global_position + Vector3(0, 1.25, 0)) - eye_pos()
		var ty: float = atan2(-d.x, -d.z)
		var tp: float = asin(clampf(d.normalized().y, -1.0, 1.0))
		var cone: float = ASSIST_CONE * (0.7 if scoped else 1.0)
		var closeness: float = 0.4 + 0.6 * (1.0 - clampf(aim_dir().angle_to(d) / cone, 0.0, 1.0))
		var k: float = clampf(ASSIST_PULL * closeness * delta, 0.0, 1.0)
		yaw += wrapf(ty - yaw, -PI, PI) * k
		pitch = clampf(pitch + (tp - pitch) * k, -1.5, 1.5)


## Closest enemy to the crosshair inside the assist cone with a clear line of sight.
func _assist_target() -> Node:
	var cone: float = ASSIST_CONE * (0.7 if scoped else 1.0)
	var fwd: Vector3 = aim_dir()
	var eye: Vector3 = eye_pos()
	var best: Node = null
	var best_a: float = cone
	var space := get_world_3d().direct_space_state
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or p.team == team or p.flux.ejected or p.flux.stealth == 2:
			continue # teammates, the dead and Mirage users are never assisted
		var pt: Vector3 = p.global_position + Vector3(0, 1.25, 0)
		var to: Vector3 = pt - eye
		var dist: float = to.length()
		if dist > ASSIST_RANGE or dist < 1.0:
			continue
		var a: float = fwd.angle_to(to)
		if a >= best_a:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, pt, 1, [get_rid()])
		if not space.intersect_ray(q).is_empty():
			continue # blocked by the map
		best = p
		best_a = a
	return best


## Gamepad shot correction (used by the Bolt): if the shot would miss an enemy by only
## a little (within a margin around their body that grows slightly with distance), the
## direction is bent onto their chest. Shots that already hit are left alone, so
## headshots stay yours; anything clearly off-target is untouched. Mouse: no change.
func pad_snap(dir: Vector3) -> Vector3:
	if not GameState.using_pad or is_bot:
		return dir
	var eye: Vector3 = eye_pos()
	var d: Vector3 = dir.normalized()
	var space := get_world_3d().direct_space_state
	var best_dir: Vector3 = dir
	var best_miss: float = INF
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or p.team == team or p.flux.ejected or p.flux.stealth == 2:
			continue
		var chest: Vector3 = p.global_position + Vector3(0, 1.2, 0)
		var dist: float = eye.distance_to(chest)
		if dist < 2.0 or dist > ASSIST_RANGE * 2.0:
			continue
		var gap: float = _ray_to_body(eye, d, p.global_position) - 0.4 # distance outside the body capsule
		if gap <= 0.0:
			return dir # already on target
		var margin: float = clampf(0.5 + dist * 0.012, 0.5, 1.5)
		if gap > margin or gap >= best_miss:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, chest, 1)).is_empty():
			continue
		best_miss = gap
		best_dir = (chest - eye).normalized()
	return best_dir


## Shortest distance between the ray (o, d) and a standing body's centre line (feet + 0.4 .. 1.4).
func _ray_to_body(o: Vector3, d: Vector3, feet: Vector3) -> float:
	var a: Vector3 = feet + Vector3(0, 0.4, 0)
	var v: Vector3 = Vector3(0, 1.0, 0)
	var w: Vector3 = o - a
	var b: float = d.dot(v)
	var dd: float = d.dot(w)
	var e: float = v.dot(w)
	var den: float = v.dot(v) - b * b # (d.d = 1, v.v = 1)
	var t: float = 0.5
	if den > 0.0001:
		t = clampf((e - b * dd) / den, 0.0, 1.0)
	var s: float = maxf(0.0, b * t - dd)
	t = clampf(e + b * s, 0.0, 1.0) # re-fit along the body now that s is fixed
	return (o + d * s).distance_to(a + v * t)


func _controller_step(delta: float) -> void:
	if is_local and GameState.using_pad and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var ph: int = GameState.phase
		if ph == GameState.Phase.LIVE or ph == GameState.Phase.COUNTDOWN:
			_pad_look(delta, ph == GameState.Phase.LIVE)
	rotation.y = yaw
	head.rotation.x = pitch
	var live: bool = GameState.phase == GameState.Phase.LIVE
	var countdown: bool = GameState.phase == GameState.Phase.COUNTDOWN
	if is_local:
		_collect_input(live or countdown)
		if not live:
			cmd.move = Vector2.ZERO
			cmd.jump = false
			cmd.sprint = false
			cmd.fire_held = [false, false]
			cmd.fire_pressed = [false, false]
	var input: Vector2 = cmd.move if live else Vector2.ZERO

	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var wish: Vector3 = right * input.x + forward * input.y
	if wish.length() > 1.0:
		wish = wish.normalized()

	if is_local and (flux.active_flux <= 0.5 or (scoped and is_on_floor() and _slide_t <= 0.0)):
		run_on = false # out of Flux, or scoped on foot: running drops back to walking
	var sprinting: bool = live and cmd.sprint and input.y > 0.1 and flux.active_flux > 0.5 and not flux.shield_on and not scoped and _slide_t <= 0.0
	if sprinting != _sprint_sent:
		_sprint_sent = sprinting
		request(0, "sprint", {"on": sprinting})

	var speed: float = SPRINT_SPEED if sprinting else WALK_SPEED
	if flux.slowed:
		speed *= 0.7
	if flux.shield_on:
		speed *= 0.6
	if _bolt_equipped():
		speed *= 0.8 # the heavy rifle slows you while it is in hand
	var accel: float = 34.0 if is_on_floor() else 10.0 # softer ground acceleration = smoother starts and stops
	var cur := Vector2(velocity.x, velocity.z)
	_slide_cd -= delta
	# Shift: slide in the direction you are moving (needs at least a brisk walk)
	if live and cmd.slide_pressed and is_on_floor() and _slide_t <= 0.0 and _slide_cd <= 0.0 \
			and not scoped and cur.length() >= SLIDE_MIN_SPEED:
		_slide_dir = cur.normalized()
		_slide_speed = clampf(maxf(cur.length(), WALK_SPEED) * 1.6, 10.0, 14.0)
		_slide_t = SLIDE_TIME
		_slide_cd = SLIDE_COOLDOWN
	var sliding_now: bool = _slide_t > 0.0
	var hv: Vector2
	if sliding_now:
		_slide_t = maxf(0.0, _slide_t - delta)
		hv = _slide_dir * lerpf(WALK_SPEED * 0.5, _slide_speed, _slide_t / SLIDE_TIME)
	elif not is_on_floor() and (_keep_mom or scoped):
		hv = cur # airborne after a slide-jump, or scoped mid-jump: momentum continues
	else:
		hv = cur.move_toward(Vector2(wish.x, wish.z) * speed, accel * delta)
		if scoped:
			hv = Vector2.ZERO # scoped on foot: stationary
	if is_on_floor() and not sliding_now:
		_keep_mom = false
	velocity.x = hv.x
	velocity.z = hv.y

	if _ladders > 0 and live:
		if input.y > 0.1:
			velocity.y = LADDER_SPEED # climbing is slow and exposed
		else:
			velocity.y = move_toward(velocity.y, 0.0, 30.0 * delta)
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
	if cmd.jump and is_on_floor() and live and not scoped:
		velocity.y = JUMP_VELOCITY
		if sliding_now:
			_keep_mom = true # slide-jump keeps the slide's speed
			_slide_t = 0.0

	move_and_slide()
	on_ground = is_on_floor()
	slide_on = sliding_now

	# during the pre-round countdown you may still swap each hand's module (free)
	if countdown:
		_rot_guard -= delta
		for h in 2:
			if cmd.rotate[h] and _rot_guard <= 0.0:
				_rot_guard = 0.2
				request(h, "rotate", {})

	if live:
		_rot_guard -= delta
		# release the suppressed button once it is let go
		for h in 2:
			if _fire_block[h] and not cmd.fire_held[h]:
				_fire_block[h] = false
		# Bolt scoped: the other hand's click only unscopes (no ability fires)
		if scoped and not is_bot:
			var bh: int = _scope_hand()
			if bh >= 0:
				var oh: int = 1 - bh
				if cmd.fire_pressed[oh]:
					scoped = false
					_fire_block[oh] = true
		for h in 2:
			if _fire_block[h]:
				cmd.fire_held[h] = false
				cmd.fire_pressed[h] = false
		for h in 2:
			if cmd.rotate[h] and _rot_guard <= 0.0:
				_rot_guard = 0.2
				request(h, "rotate", {})
			var m = active_module(h)
			if m != null and m.is_active and not flux.hand_off(h):
				m.controller_update(delta)


## The hand holding the Bolt while scoped (-1 if unclear, e.g. a Bolt in both hands).
func _scope_hand() -> int:
	var found: int = -1
	for h in 2:
		var m = active_module(h)
		if m != null and m.data.id == "bolt":
			if found >= 0:
				return -1
			found = h
	return found


func _bolt_equipped() -> bool:
	for h in 2:
		var m = active_module(h)
		if m != null and m.data.id == "bolt":
			return true
	return false


func _on_ejected() -> void:
	_was_ejected = true
	scoped = false
	model.visible = false
	name_label.visible = false
	viewmodel.visible = false
	hum.stop()
	velocity = Vector3.ZERO
	(get_node("Shape") as CollisionShape3D).set_deferred("disabled", true)
	Sfx.play_3d(self, "eject", global_position, 2.0, 50.0)
	GameState.player_ejected.emit(self)


## Smooths the speed used by the animations and fires the one-shot motion sounds.
## Footsteps themselves come from the walk / run animation (see _on_footstep).
func _step_audio(delta: float) -> void:
	var d: Vector3 = global_position - _last_pos
	_last_pos = global_position
	if d.length() > 3.0:
		return
	var raw: float = Vector2(d.x, d.z).length() / maxf(delta, 0.0001)
	move_speed = lerpf(move_speed, raw, clampf(delta * 14.0, 0.0, 1.0))
	var vy: float = d.y / maxf(delta, 0.0001)
	if slide_on and not _was_sliding:
		_motion_sound("slide", 1.0)
	_was_sliding = slide_on
	if not on_ground:
		_air_t += delta
		_fall_v = minf(_fall_v, vy)
	if on_ground != _was_ground:
		_was_ground = on_ground
		if on_ground:
			if _air_t > 0.15:
				_motion_sound("land", clampf(-_fall_v / 12.0, 0.5, 1.5))
			_air_t = 0.0
			_fall_v = 0.0
		elif vy > 2.0:
			_motion_sound("jump", 1.0)


## Called by the character's walk / run animation exactly when a foot touches down.
func _on_footstep(foot: int) -> void:
	if not on_ground or slide_on or flux.ejected:
		return
	var kind: String = "step_run" if model.state == "run" else "step_walk"
	_motion_sound(kind, 1.0, (1.0 if foot == 0 else 0.92) * randf_range(0.96, 1.04))


func _motion_sound(kind: String, loud: float, pitch: float = 1.0) -> void:
	var db: float = linear_to_db(loud) + (-10.0 if is_local else -3.0)
	Sfx.play_3d(self, kind, global_position + Vector3(0, 0.1, 0), db, 30.0, pitch)


# --- requests (controller -> server) ----------------------------------------

func request(hand: int, kind: String, args: Dictionary) -> void:
	if multiplayer.is_server():
		_handle_request(hand, kind, args)
	else:
		srv_request.rpc_id(1, hand, kind, args)


@rpc("any_peer", "call_remote", "reliable")
func srv_request(hand: int, kind: String, args: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_handle_request(hand, kind, args)


func _handle_request(hand: int, kind: String, args: Dictionary) -> void:
	var ph: int = GameState.phase
	if flux.ejected or not (ph == GameState.Phase.LIVE or (ph == GameState.Phase.COUNTDOWN and kind == "rotate")):
		return
	if kind == "sprint":
		flux.sprinting = bool(args.get("on", false)) and flux.active_flux > 0.5 and not flux.shield_on
		return
	if hand < 0 or hand >= modules.size():
		return
	if kind == "rotate":
		_rotate_hand(hand)
		return
	var m = active_module(hand)
	if m != null and m.data.id == kind and not flux.hand_off(hand):
		var before: int = flux.last_spend_ms
		m.server_use(args)
		# using anything but the stealth modules leaves a radar signature
		if flux.last_spend_ms != before and kind != "ghost" and kind != "mirage":
			flux.signature = maxf(flux.signature, FluxComponent.SIG_USE)
			# attacking breaks the Mirage cloak (it must be toggled on again)
			if flux.stealth == 2 and ATTACK_IDS.has(kind):
				flux.stealth = 0


## Server: next filled slot after the current one (empty slots are skipped).
func _rotate_hand(hand: int) -> void:
	var row: Array = slot_ids[hand]
	var cur: int = flux.slot_of(hand)
	var nxt: int = cur
	for i in range(1, row.size()):
		var c: int = (cur + i) % row.size()
		if String(row[c]) != "":
			nxt = c
			break
	if nxt == cur:
		return
	var free: bool = GameState.phase == GameState.Phase.COUNTDOWN
	if free or flux.spend(FluxComponent.SWITCH_COST, "rotate"):
		flux.shield_on = false
		flux.set_slot(hand, nxt)


# --- events (server -> controller) ------------------------------------------

func send_event(kind: String, data: Dictionary) -> void:
	if is_multiplayer_authority():
		_handle_event(kind, data)
	else:
		cl_event.rpc_id(get_multiplayer_authority(), kind, data)


@rpc("any_peer", "call_remote", "reliable")
func cl_event(kind: String, data: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_handle_event(kind, data)


func _handle_event(kind: String, data: Dictionary) -> void:
	match kind:
		"impulse":
			var v: Vector3 = data["v"]
			velocity.x += v.x
			velocity.z += v.z
			velocity.y = v.y
		"ejected_by":
			if is_local:
				GameState.local_killed.emit(String(data["name"]), String(data["src"]), float(data["dist"]))
		"deny":
			if is_local:
				Sfx.play_ui(self, "warn", -4.0)
		"lunge":
			var lv: Vector3 = data["v"]
			velocity.x += lv.x
			velocity.z += lv.z
		"teleport":
			global_position = data["pos"]
			velocity = Vector3.ZERO
		"hurt":
			var blocked: bool = data.get("blocked", false)
			if is_bot and brain != null:
				brain.on_event(kind, data)
			if is_local:
				GameState.local_hurt.emit(data["from"], blocked)
				Sfx.play_ui(self, "block" if blocked else "hurt")
		"hit":
			if is_local:
				var killed: bool = data.get("killed", false)
				var blocked2: bool = data.get("blocked", false)
				var zone: String = data.get("zone", "torso")
				GameState.local_hit.emit(killed, blocked2, zone)
				Sfx.play_ui(self, "kill" if killed else ("block" if blocked2 else ("head" if zone == "head" else "hit")))


# --- cosmetic broadcast (server -> everyone) ---------------------------------

@rpc("any_peer", "call_local", "unreliable")
func fx_play(kind: String, a: Vector3, b: Vector3) -> void:
	var s: int = multiplayer.get_remote_sender_id()
	if s != 0 and s != 1:
		return
	match kind:
		"shot":
			_spawn_tracer(a, b, 0.0) # a is the muzzle itself
			Sfx.play_3d(self, "shot", a, -4.0, 60.0)
			viewmodel.kick_by_id("kinetic")
		"swing":
			Sfx.play_3d(self, "swing", a, 0.0, 30.0)
			viewmodel.kick_by_id("edge")
		"cast":
			Sfx.play_3d(self, "swing", a, -4.0, 30.0)
			viewmodel.kick_cast()
		"boom":
			Sfx.play_3d(self, "boom", a, 4.0, 70.0)
			_spawn_boom(a)
		"bolt":
			_spawn_tracer(a, b)
			Sfx.play_3d(self, "bolt", a, 3.0, 90.0)
			viewmodel.kick_by_id("bolt")
		"block":
			Sfx.play_3d(self, "block", a, 2.0, 40.0)
		"sbreak":
			Sfx.play_3d(self, "sbreak", a, 4.0, 45.0)
		"boost":
			Sfx.play_3d(self, "boost", a, 0.0, 40.0)
			viewmodel.kick_by_id("boost")
			_spawn_boost_pad(a)
		"heal":
			# a = start of the channel, b = finished
			Sfx.play_3d(self, "shift" if a == b else "boost", a, -8.0, 30.0, 1.6)
		"shift":
			viewmodel.kick_by_id("shift")
			Sfx.play_3d(self, "shift", a, 0.0, 40.0)
			Sfx.play_3d(self, "shift", b, 0.0, 40.0)


## Boost burst: the Boost pad scene flashes under the player's feet for one pulse.
func _spawn_boost_pad(pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var pad := BOOST_SCENE.instantiate() as Node3D
	(pad.get_node("TriggerZone") as Area3D).monitoring = false
	scene.add_child(pad)
	pad.global_position = pos + Vector3(0, 0.03, 0)
	get_tree().create_timer(0.8).timeout.connect(pad.queue_free)


func _spawn_boom(pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.8)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.8
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 9.0, 0.3)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(mi.queue_free)


## Cosmetic mirror of a server projectile (Vector / Blast / Seeker).
@rpc("any_peer", "call_local", "unreliable")
func proj_sync(id: int, kind: String, pos: Vector3, alive: bool) -> void:
	var s: int = multiplayer.get_remote_sender_id()
	if s != 0 and s != 1:
		return
	var e = _pviz.get(id)
	if not alive:
		if e != null:
			if is_instance_valid(e["node"]):
				e["node"].queue_free()
			_pviz.erase(id)
		return
	if e == null:
		var scene := get_tree().current_scene
		if scene == null:
			return
		var mi := ORB_SCENE.instantiate() as OrbView
		mi.scale = Vector3.ONE * (1.4 if kind == "blast" else 0.6)
		mi.set_color({"vector": Color(0.4, 1.0, 0.9), "blast": Color(1.0, 0.5, 0.1), "seeker": Color(0.5, 1.0, 0.4)}.get(kind, Color.WHITE), 1.5)
		scene.add_child(mi)
		mi.global_position = pos
		e = {"node": mi, "t": 0}
		_pviz[id] = e
	e["t"] = Time.get_ticks_msec()
	if is_instance_valid(e["node"]):
		e["node"].global_position = pos


## Server: place a Bunker (up to MAX_BUNKERS per player, oldest is removed).
func place_bunker(xf: Transform3D) -> void:
	var id: int = randi()
	_bunker_ids.append(id)
	if _bunker_ids.size() > MAX_BUNKERS:
		bunker_rpc.rpc("free", _bunker_ids.pop_front(), Transform3D.IDENTITY)
	bunker_rpc.rpc("spawn", id, xf)


@rpc("any_peer", "call_local", "reliable")
func bunker_rpc(op: String, id: int, xf: Transform3D) -> void:
	var s: int = multiplayer.get_remote_sender_id()
	if s != 0 and s != 1:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var nm := "Bunker_%d" % id
	if op == "spawn":
		var b := BUNKER_SCENE.instantiate() as Bunker
		b.name = nm
		b.bid = id
		b.owner_player = self
		scene.add_child(b)
		b.build()
		b.global_transform = xf
		Sfx.play_3d(self, "bunker", xf.origin, 2.0, 40.0)
	else:
		var n := scene.get_node_or_null(nm)
		if n != null:
			n.queue_free()


func _spawn_tracer(a: Vector3, b: Vector3, drop: float = 0.15) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a + Vector3(0, -drop, 0))
	im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.4)
	mi.material_override = mat
	scene.add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)
