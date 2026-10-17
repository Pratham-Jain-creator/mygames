extends CharacterBody3D
## Wraithstride player.
## Ghost-Runner movement (wall-run, wall-jump, aim-dash, slide) + FFT jobs (charge-time abilities)
## + Sekiro combat (deflect window, posture, deathblow).
##
## Everything you SEE lives in player.tscn and is played by the AnimationPlayers:
##   HandAnim  viewmodel weapon   RollAnim  camera roll / slide dip
##   FovAnim   dash FOV kick      ShakeAnim land / hurt / jolt   FxAnim shockwave / heal motes
## This script only reads input, moves the body with vector maths and decides outcomes.

const JobData = preload("res://scripts/job_data.gd")
const BEAM_SCENE: PackedScene = preload("res://scenes/fx/beam.tscn")

const BASE_SPEED := 11.0
const GROUND_ACCEL := 70.0
const AIR_ACCEL := 22.0
const MOUSE_SENS := 0.0023
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const DASH_SPEED := 30.0
const DASH_TIME := 0.18
const SLIDE_TIME := 0.9
const WALLRUN_MAX := 3.0
const WALLRUN_MULT := 1.1
const WALL_COYOTE := 0.18
const KILL_Y := -40.0

# --- Flow: speed is power. Tier 0..3 (3 = Wraith) indexes these tables. ---
const CT_MULT: Array[float] = [1.0, 0.8, 0.55, 0.0]
const DMG_MULT: Array[float] = [1.0, 1.1, 1.25, 1.4]
const POSTURE_MULT: Array[float] = [1.0, 1.15, 1.4, 1.75]
const CD_TICK: Array[float] = [1.0, 1.15, 1.4, 2.0]

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Rig/Shake/Camera
@onready var aim_ray: RayCast3D = $Head/Rig/Shake/Camera/AimRay
@onready var melee_area: Area3D = $Head/MeleeArea
@onready var weapons: Node3D = $Head/Rig/Shake/Camera/Viewmodel/Hand/Weapons
@onready var sparks: CPUParticles3D = $Head/Rig/Shake/Camera/Sparks
@onready var shockwave: Node3D = $Fx/Shockwave
@onready var hand_anim: AnimationPlayer = $HandAnim
@onready var roll_anim: AnimationPlayer = $RollAnim
@onready var fov_anim: AnimationPlayer = $FovAnim
@onready var shake_anim: AnimationPlayer = $ShakeAnim
@onready var fx_anim: AnimationPlayer = $FxAnim

var job_id: StringName = &"knight"
var job: Dictionary = {}
var alive := true

var hp := 100.0
var max_hp := 100.0
var posture := 0.0
var max_posture := 100.0
var posture_regen_delay := 0.0

var run_speed := BASE_SPEED
var jump_velocity := 8.6
var air_dashes_left := 1
var gravity := 24.0

var coyote := 0.0
var jump_buffer := 0.0

var dash_timer := 0.0
var dash_cd := 0.0
var dash_dir := Vector3.ZERO
var dash_speed := DASH_SPEED

var sliding := false
var slide_timer := 0.0

var wall_running := false
var wall_run_time := 0.0
var wall_run_speed := 0.0
var wall_normal := Vector3.ZERO
var wall_coyote := 0.0
var wall_side := 0

var attack_cd := 0.0
var combo := 0
var guarding := false
var guard_time := 0.0
var stun := 0.0
var invuln := 0.0

var buff_guard := 0.0
var buff_guard_power := 0.0
var buff_haste := 0.0
var haste_mult := 1.0

var ability_cd: Array[float] = [0.0, 0.0]
var cast_slot := -1
var cast_time := 0.0
var cast_total := 0.0

var leaping := false
var leap_t := 0.0
var leap_power := 0.0
var leap_posture := 0.0

var near_crystal := false
var dash_hit: Array = []  # enemies already struck during the current dash
var snare := 0.0  # spider web: slowed + no jump until it times out or you dash free

var flow := 0.0
var flow_hold := 0.0
var wraith := false


func _ready() -> void:
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hand_anim.animation_finished.connect(_on_hand_finished)
	Game.enemy_killed.connect(_on_enemy_killed)
	apply_job(Game.current_job, true)


# --- input: look -------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-motion.relative.x * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x - motion.relative.y * MOUSE_SENS, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- main loop ---------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not alive:
		return
	_tick_timers(delta)
	_update_flow(delta)
	if global_position.y < KILL_Y:
		die("fell")
		return
	if Input.is_action_just_pressed("restart"):
		die("restart")
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if stun > 0.0:
		input = Vector2.ZERO
	# Body yaw only (pitch lives on Head), so this is a flat world-space wish direction.
	var wish := (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	_update_guard(delta)
	_update_actions()

	if dash_timer > 0.0:
		dash_timer -= delta
		velocity = dash_dir * dash_speed
		_dash_strike()
		if dash_timer <= 0.0:
			velocity = dash_dir * run_speed * 1.1  # keep momentum out of the dash
		move_and_slide()
		return

	_movement(delta, wish, input)
	var prev_vy := velocity.y
	var was_floor := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_floor and prev_vy < -8.0:
		shake_anim.play("land")
	if leaping and leap_t > 0.25 and is_on_floor():
		_land_slam()


## Called by webs / spider bolts.
func ensnare(t: float) -> void:
	if invuln > 0.0:
		return
	snare = maxf(snare, t)
	velocity.x *= 0.3
	velocity.z *= 0.3


func _tick_timers(delta: float) -> void:
	var tick := CD_TICK[flow_tier()]
	jump_buffer = maxf(jump_buffer - delta, 0.0)
	attack_cd = maxf(attack_cd - delta, 0.0)
	dash_cd = maxf(dash_cd - delta * tick, 0.0)
	invuln = maxf(invuln - delta, 0.0)
	stun = maxf(stun - delta, 0.0)
	snare = maxf(snare - delta, 0.0)
	wall_coyote = maxf(wall_coyote - delta, 0.0)
	for i in 2:
		ability_cd[i] = maxf(ability_cd[i] - delta * tick, 0.0)
	if buff_guard > 0.0:
		buff_guard -= delta
		if buff_guard <= 0.0:
			Game.buff_changed.emit(&"guard", false)
	if buff_haste > 0.0:
		buff_haste -= delta
		if buff_haste <= 0.0:
			Game.buff_changed.emit(&"haste", false)
	if sliding:
		slide_timer -= delta
		if slide_timer <= 0.0 or not is_on_floor() or Vector2(velocity.x, velocity.z).length() < 2.5:
			_end_slide()
	if cast_slot >= 0:
		cast_time += delta
		if cast_time >= cast_total:
			var slot := cast_slot
			cast_slot = -1
			_resolve_ability(slot)
	if leaping:
		leap_t += delta
	posture_regen_delay -= delta
	if posture_regen_delay <= 0.0 and posture > 0.0:
		posture = maxf(posture - (8.0 if guarding else 18.0) * delta, 0.0)


# --- movement ----------------------------------------------------------------
func _movement(delta: float, wish: Vector3, input: Vector2) -> void:
	var on_floor := is_on_floor()
	var speed := run_speed
	if buff_haste > 0.0:
		speed *= haste_mult
	if is_casting():
		speed *= 0.5
	if snare > 0.0:
		speed *= 0.3

	if on_floor:
		coyote = COYOTE_TIME
		air_dashes_left = int(job["air_dashes"])
		wall_run_time = 0.0
	else:
		coyote = maxf(coyote - delta, 0.0)

	_update_wall_run(delta, input)

	if not on_floor and not wall_running:
		velocity.y -= gravity * delta

	if not wall_running:
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		if sliding and on_floor:
			hv = hv.move_toward(Vector3.ZERO, 4.0 * delta)
			hv += wish * 3.0 * delta
		elif on_floor:
			hv = hv.move_toward(wish * speed, GROUND_ACCEL * delta)
		else:
			# Air: steer but never bleed off momentum that was earned (dash / wall-jump).
			var prev_speed := hv.length()
			hv += wish * AIR_ACCEL * delta
			hv = hv.limit_length(maxf(speed, prev_speed))
		velocity.x = hv.x
		velocity.z = hv.z

	if Input.is_action_just_pressed("jump"):
		jump_buffer = JUMP_BUFFER
	if jump_buffer > 0.0 and stun <= 0.0 and snare <= 0.0:
		if coyote > 0.0:
			velocity.y = jump_velocity
			if sliding:
				velocity.x *= 1.12
				velocity.z *= 1.12
				_end_slide()
			coyote = 0.0
			jump_buffer = 0.0
		elif wall_running or wall_coyote > 0.0:
			_wall_jump()
			jump_buffer = 0.0
	if Input.is_action_just_released("jump") and velocity.y > 3.0 and not leaping:
		velocity.y *= 0.55  # variable jump height


func _update_wall_run(delta: float, input: Vector2) -> void:
	var touching := is_on_wall() and not is_on_floor() and absf(get_wall_normal().y) < 0.25
	var wants := input.y < -0.1 and wall_run_time < WALLRUN_MAX
	if touching and wants:
		var n := get_wall_normal()
		var fwd := -global_transform.basis.z
		# Run direction = wall tangent (normal x up), flipped to match where we're looking.
		var along := n.cross(Vector3.UP).normalized()
		if along.dot(fwd) < 0.0:
			along = -along
		if not wall_running:
			wall_running = true
			wall_run_speed = maxf(Vector2(velocity.x, velocity.z).length(), run_speed) * WALLRUN_MULT
			velocity.y = clampf(velocity.y, -1.0, 2.5)
			air_dashes_left = int(job["air_dashes"])
			# Wall is on our right if the direction INTO the wall points along our right axis.
			wall_side = 1 if (-n).dot(global_transform.basis.x) > 0.0 else -1
			roll_anim.play("wallrun_right" if wall_side > 0 else "wallrun_left", 0.12)
		wall_normal = n
		wall_coyote = WALL_COYOTE
		wall_run_time += delta
		var hv := along * wall_run_speed - n * 3.0  # small push keeps us glued to the wall
		velocity.x = hv.x
		velocity.z = hv.z
		velocity.y = move_toward(velocity.y, -0.2 - 0.35 * wall_run_time, 12.0 * delta)
	elif wall_running:
		wall_running = false
		roll_anim.play("roll_reset", 0.18)


func _wall_jump() -> void:
	var fwd := -global_transform.basis.z
	var push := wall_normal * 7.5 + fwd * maxf(wall_run_speed * 0.6, 5.0)
	velocity = Vector3(push.x, jump_velocity * 1.05, push.z)
	air_dashes_left = int(job["air_dashes"])
	wall_running = false
	wall_coyote = 0.0
	wall_run_time = WALLRUN_MAX * 0.4
	_gain_flow(6.0)
	roll_anim.play("roll_reset", 0.15)


func _start_dash(dir: Vector3, time: float, speed: float) -> void:
	dash_dir = dir.normalized()
	dash_timer = time
	dash_speed = speed
	_gain_flow(5.0)
	invuln = maxf(invuln, time + 0.08)
	snare = 0.0  # a dash tears you out of webs
	dash_hit.clear()
	if sliding:
		sliding = false
	wall_running = false
	cast_slot = -1
	fov_anim.play("dash")
	roll_anim.play("roll_reset", 0.1)


func _end_slide() -> void:
	sliding = false
	if not wall_running:
		roll_anim.play("roll_reset", 0.15)


# --- actions -----------------------------------------------------------------
func _update_actions() -> void:
	if stun > 0.0:
		return
	if Input.is_action_just_pressed("attack"):
		_try_attack()
	if Input.is_action_just_pressed("ability_1"):
		_try_ability(0)
	if Input.is_action_just_pressed("ability_2"):
		_try_ability(1)
	if Input.is_action_just_pressed("interact") and near_crystal:
		_cycle_job()
	if Input.is_action_just_pressed("dash") and dash_cd <= 0.0 and (is_on_floor() or air_dashes_left > 0):
		if not is_on_floor():
			air_dashes_left -= 1
		dash_cd = float(job["dash_cd"])
		var dir := -camera.global_transform.basis.z  # dash goes where you LOOK
		if is_on_floor() and dir.y < 0.0:
			dir.y = 0.0
		_start_dash(dir, DASH_TIME, DASH_SPEED)
	if Input.is_action_just_pressed("slide"):
		if leaping:
			velocity = Vector3(velocity.x * 0.3, -38.0, velocity.z * 0.3)  # Dragoon dive
		elif is_on_floor() and not sliding and Vector2(velocity.x, velocity.z).length() > 6.0:
			sliding = true
			slide_timer = SLIDE_TIME
			roll_anim.play("slide_in", 0.08)


func _update_guard(delta: float) -> void:
	var want := Input.is_action_pressed("deflect") and stun <= 0.0 and not is_casting() and dash_timer <= 0.0
	if want and not guarding:
		guarding = true
		guard_time = 0.0
		hand_anim.play("deflect", 0.03)
	elif not want and guarding:
		guarding = false
		hand_anim.play("guard_drop", 0.03)
	if guarding:
		guard_time += delta


func _try_attack() -> void:
	if attack_cd > 0.0 or guarding or is_casting() or dash_timer > 0.0:
		return
	attack_cd = float(job["atk_cd"]) * (0.6 if job_id == &"monk" and flow_tier() >= 2 else 1.0)
	combo = 1 - combo
	hand_anim.play("swing_a" if combo == 0 else "swing_b", 0.03)


## Called by a method track inside the swing_a / swing_b animations at the strike frame.
func _on_swing_hit() -> void:
	for body in melee_area.get_overlapping_bodies():
		if body.is_in_group("enemy") and body.has_method("take_hit"):
			var dmg := float(job["atk_damage"]) * _level_mult() * DMG_MULT[flow_tier()]
			if job_id == &"thief" and flow_tier() >= 2:
				# Backstab: the enemy's forward points away from us (dot < 0 = we are behind it).
				var to_me := global_position - (body as Node3D).global_position
				if (-(body as Node3D).global_transform.basis.z).dot(to_me.normalized()) < -0.3:
					dmg *= 2.0
			var res: String = body.take_hit(dmg, float(job["atk_posture"]) * POSTURE_MULT[flow_tier()], self)
			_after_hit(res)


## Dashing THROUGH an enemy cuts it: you never stop, enemies are speed-bumps that pay you for passing.
func _dash_strike() -> void:
	for body in melee_area.get_overlapping_bodies():
		if body in dash_hit or not body.is_in_group("enemy") or not body.has_method("take_hit"):
			continue
		dash_hit.append(body)
		var dmg := float(job["atk_damage"]) * 1.2 * _level_mult() * DMG_MULT[flow_tier()]
		_after_hit(body.take_hit(dmg, float(job["atk_posture"]) * 1.5 * POSTURE_MULT[flow_tier()], self))


func _after_hit(res: String) -> void:
	sparks.restart()
	# Momentum rules: no freeze-frames while you are fast, and kills REFUND movement.
	var fast := Vector2(velocity.x, velocity.z).length() > run_speed * 0.9 or dash_timer > 0.0
	match res:
		"deathblow":
			hand_anim.play("deathblow", 0.02)
			Game.message.emit("DEATHBLOW")
			if not fast:
				Game.hitstop(0.08)
			_reward_kill()
		"kill":
			if not fast:
				Game.hitstop(0.05)
			_reward_kill()
		"break":
			Game.message.emit("POSTURE BROKEN")
			if not fast:
				Game.hitstop(0.06)
		_:
			if not fast:
				Game.hitstop(0.02)


## A kill gives the dash back and a forward shove, so fighting feeds the run instead of stopping it.
func _reward_kill() -> void:
	dash_cd = 0.0
	air_dashes_left = maxi(air_dashes_left, int(job["air_dashes"]))
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	hv = (hv + fwd.normalized() * 6.0).limit_length(maxf(hv.length() + 3.0, run_speed * 1.15))
	velocity.x = hv.x
	velocity.z = hv.z


# --- abilities (FFT charge time) ---------------------------------------------
func is_casting() -> bool:
	return cast_slot >= 0


func _try_ability(slot: int) -> void:
	if is_casting() or ability_cd[slot] > 0.0 or dash_timer > 0.0:
		return
	var ab: Dictionary = job["abilities"][slot]
	var ct := float(ab["ct"]) * CT_MULT[flow_tier()]  # Flow shortens charge time
	if ct > 0.0:
		cast_slot = slot
		cast_time = 0.0
		cast_total = ct
		hand_anim.play("cast", 0.1)
	else:
		_resolve_ability(slot)


func _cancel_cast() -> void:
	if is_casting():
		cast_slot = -1
		hand_anim.play("idle", 0.1)


func _resolve_ability(slot: int) -> void:
	var ab: Dictionary = job["abilities"][slot]
	ability_cd[slot] = float(ab["cd"])
	var power := float(ab["power"])
	var posture_dmg := float(ab["posture"]) * POSTURE_MULT[flow_tier()]
	var lm := _level_mult() * DMG_MULT[flow_tier()]
	var fwd := -camera.global_transform.basis.z
	hand_anim.play("cast_release" if float(ab["ct"]) > 0.0 else "ability_quick", 0.02)
	match String(ab["kind"]):
		"heal":
			var boost := 1.5 if job_id == &"white_mage" and flow_tier() >= 2 else 1.0
			hp = minf(hp + power * lm * boost, max_hp)
			fx_anim.play("heal")
		"guard":
			buff_guard = float(ab["dur"])
			buff_guard_power = power
			Game.buff_changed.emit(&"guard", true)
		"haste":
			buff_haste = float(ab["dur"])
			haste_mult = power
			Game.buff_changed.emit(&"haste", true)
		"step":
			invuln = maxf(invuln, 0.4)
			_start_dash(fwd, float(ab["dur"]), power)
		"blink":
			_blink(fwd, power)
		"bolt":
			_hitscan(power * lm, posture_dmg, 60.0)
		"thrust":
			_hitscan(power * lm, posture_dmg, 6.5)
		"bash":
			for body in melee_area.get_overlapping_bodies():
				if body.is_in_group("enemy") and body.has_method("take_hit"):
					body.velocity += fwd * 9.0  # shove
					_after_hit(body.take_hit(power * lm, posture_dmg, self))
		"wave":
			for e in get_tree().get_nodes_in_group("enemy"):
				var to: Vector3 = (e as Node3D).global_position + Vector3.UP - camera.global_position
				# dot(a, b) > cos(15 deg): enemy is inside a 15 degree cone around the crosshair
				if to.length() < 22.0 and fwd.dot(to.normalized()) > 0.966:
					_spawn_beam(camera.global_transform * Vector3(0.3, -0.25, -0.9), (e as Node3D).global_position + Vector3.UP)
					_after_hit(e.take_hit(power * lm, posture_dmg, self))
		"leap":
			var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
			velocity = flat * 9.0 + Vector3.UP * 21.0
			leaping = true
			leap_t = 0.0
			leap_power = power * lm
			leap_posture = posture_dmg
			wall_running = false


func _hitscan(dmg: float, posture_dmg: float, reach: float) -> void:
	var muzzle := camera.global_transform * Vector3(0.3, -0.25, -0.9)
	var to := camera.global_position + (-camera.global_transform.basis.z) * reach
	var target: Object = null
	aim_ray.force_raycast_update()
	if aim_ray.is_colliding():
		var p := aim_ray.get_collision_point()
		if camera.global_position.distance_to(p) <= reach:
			to = p
			target = aim_ray.get_collider()
	_spawn_beam(muzzle, to)
	if target and target.is_in_group("enemy") and target.has_method("take_hit"):
		_after_hit(target.take_hit(dmg, posture_dmg, self))


func _blink(dir: Vector3, dist: float) -> void:
	var from := global_position + Vector3.UP
	var to := from + dir * dist
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		to = hit["position"] + hit["normal"] * 0.6
	global_position = to - Vector3.UP
	fov_anim.play("dash")
	invuln = maxf(invuln, 0.15)
	if job_id == &"black_mage" and flow_tier() >= 2:
		invuln = maxf(invuln, 0.4)  # perk: blink is safe and refunds air dashes
		air_dashes_left = int(job["air_dashes"])


func _land_slam() -> void:
	leaping = false
	shockwave.global_position = global_position + Vector3.UP * 0.1
	fx_anim.play("shockwave")
	shake_anim.play("slam")
	var radius := 10.0 if job_id == &"dragoon" and flow_tier() >= 2 else 6.5
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Node3D).global_position.distance_to(global_position) < radius:
			_after_hit(e.take_hit(leap_power, leap_posture, self))
	Game.hitstop(0.06)


func _spawn_beam(from: Vector3, to: Vector3) -> void:
	var beam := BEAM_SCENE.instantiate()
	get_tree().current_scene.add_child(beam)
	beam.setup(from, to)


# --- defense (Sekiro posture) --------------------------------------------------
## Enemies call this at the strike frame of an attack.
## Returns: "deflected" | "blocked" | "hit" | "evaded" | "mikiri"
func receive_attack(dmg: float, posture_dmg: float, attacker: Node3D, unblockable: bool = false) -> String:
	if not alive:
		return "evaded"
	if unblockable and dash_timer > 0.0:
		Game.message.emit("MIKIRI!")  # dodge into a perilous thrust = enemy posture break
		_gain_flow(20.0)
		return "mikiri"
	if invuln > 0.0:
		return "evaded"
	var to_attacker := attacker.global_position - global_position
	to_attacker.y = 0.0
	var in_front := (-global_transform.basis.z).dot(to_attacker.normalized()) > 0.1
	var mitigation := 1.0
	if buff_guard > 0.0:
		mitigation = 1.0 - buff_guard_power
	if job_id == &"knight" and flow_tier() >= 2:
		mitigation *= 0.75  # perk: Wraith Knight is hard to hurt
	if guarding and in_front and not unblockable:
		if guard_time <= float(job["deflect_window"]):
			_on_perfect_deflect()
			return "deflected"
		_add_posture(posture_dmg * mitigation)
		hand_anim.play("block_hit", 0.02)
		sparks.restart()
		Game.deflected.emit(false)
		take_damage(dmg * 0.12 * mitigation)
		return "blocked"
	take_damage(dmg * mitigation)
	return "hit"


func _on_perfect_deflect() -> void:
	sparks.restart()
	hand_anim.play("deflect_perfect", 0.0)
	shake_anim.play("jolt")
	posture = maxf(posture - 12.0, 0.0)
	_gain_flow(12.0)
	Game.deflected.emit(true)
	Game.hitstop(0.08)


func _add_posture(amount: float) -> void:
	posture += amount
	posture_regen_delay = 1.2
	if posture >= max_posture:
		posture = max_posture * 0.4
		stun = 1.4
		guarding = false
		hand_anim.play("hurt", 0.02)
		Game.posture_broken.emit()
		flow = maxf(flow - 50.0, 0.0)
		Game.message.emit("YOUR POSTURE BROKE")


func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	flow = maxf(flow - 35.0, 0.0)
	_cancel_cast()
	shake_anim.play("hurt")
	if not guarding:
		hand_anim.play("hurt", 0.02)
	Game.hurt.emit(amount)
	posture_regen_delay = 1.5
	if hp <= 0.0:
		die("slain")


# --- death / respawn (Ghost Runner: instant restart at the checkpoint) ---------
func die(reason: String = "slain") -> void:
	if not alive:
		return
	alive = false
	Game.deaths += 1
	Game.player_died.emit(reason)
	shake_anim.play("hurt")
	await get_tree().create_timer(0.35).timeout
	respawn(true)


func respawn(reset_enemies: bool = true) -> void:
	global_position = Game.checkpoint_pos
	rotation = Vector3(0.0, Game.checkpoint_yaw, 0.0)
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	hp = max_hp
	posture = 0.0
	stun = 0.0
	invuln = 0.6
	dash_timer = 0.0
	dash_cd = 0.0
	sliding = false
	wall_running = false
	leaping = false
	cast_slot = -1
	guarding = false
	buff_guard = 0.0
	buff_haste = 0.0
	ability_cd = [0.0, 0.0]
	air_dashes_left = int(job["air_dashes"])
	alive = true
	flow = 0.0
	if wraith:
		wraith = false
		Game.buff_changed.emit(&"wraith", false)
	roll_anim.play("roll_reset", 0.0)
	fov_anim.play("respawn")
	hand_anim.play("equip")
	if reset_enemies:
		get_tree().call_group("enemy", "reset_to_home")


# --- jobs ----------------------------------------------------------------------
# --- Flow ---------------------------------------------------------------------
## Tier 0..3 (3 = Wraith). Higher tiers shorten charge times, raise damage and posture
## damage, speed up cooldowns, and from tier 2 unlock a per-job perk (see receive_attack,
## _on_swing_hit, _try_attack, _resolve_ability, _blink, _land_slam).
func flow_tier() -> int:
	if flow >= 99.0:
		return 3
	return int(flow / 33.4)


func _gain_flow(amount: float) -> void:
	flow = minf(flow + amount, 100.0)
	flow_hold = 0.8


func _update_flow(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > run_speed * 0.9:
		var over := clampf((hspeed - run_speed * 0.9) / (run_speed * 0.6), 0.0, 1.0)
		var rate := 6.0 + 14.0 * over
		if wall_running:
			rate += 12.0
		elif sliding:
			rate += 6.0
		elif dash_timer > 0.0:
			rate += 10.0
		_gain_flow(rate * delta)
	else:
		flow_hold -= delta
		if flow_hold <= 0.0:
			var drain := 6.0 if hspeed > run_speed * 0.5 else 18.0
			flow = maxf(flow - drain * delta, 0.0)
	var now := flow >= 99.0
	if now != wraith:
		wraith = now
		Game.buff_changed.emit(&"wraith", now)
		if now:
			Game.message.emit("WRAITH FLOW")


func _level_mult() -> float:
	return 1.0 + 0.1 * float(int(Game.job_level[job_id]) - 1)


func apply_job(id: StringName, fresh: bool = false) -> void:
	var ratio := 1.0
	if not fresh and max_hp > 0.0:
		ratio = hp / max_hp
	job_id = id
	job = JobData.JOBS[id]
	Game.current_job = id
	var lm := _level_mult()
	max_hp = float(job["hp"]) * lm
	max_posture = float(job["posture"]) * lm
	hp = max_hp * ratio
	posture = 0.0
	run_speed = BASE_SPEED * float(job["move"])
	jump_velocity = float(job["jump"])
	air_dashes_left = int(job["air_dashes"])
	ability_cd = [0.0, 0.0]
	cast_slot = -1
	buff_guard = 0.0
	buff_haste = 0.0
	leaping = false
	for w in weapons.get_children():
		w.visible = String(w.name) == String(job["weapon"])
	hand_anim.play("equip")
	Game.job_changed.emit(id)


func _cycle_job() -> void:
	var i := JobData.ORDER.find(job_id)
	apply_job(JobData.ORDER[(i + 1) % JobData.ORDER.size()])
	Game.message.emit("%s  (%s)" % [job["name"], job["role"]])


func _on_enemy_killed(deathblow: bool, _jp: int) -> void:
	# Ghost Runner rule: a kill refunds your mobility.
	_gain_flow(25.0 if deathblow else 15.0)
	dash_cd = 0.0
	air_dashes_left = int(job["air_dashes"])
	if deathblow:
		hp = minf(hp + max_hp * 0.2, max_hp)


func _on_hand_finished(anim_name: StringName) -> void:
	match anim_name:
		&"deflect", &"deflect_perfect", &"block_hit":
			hand_anim.play("deflect_hold" if guarding else "idle", 0.05)
		&"idle", &"deflect_hold", &"cast":
			pass
		_:
			hand_anim.play("deflect_hold" if guarding else "idle", 0.1)
