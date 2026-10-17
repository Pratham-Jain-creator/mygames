class_name BotBrain
extends Node
## Server-side bot AI. Writes into the same Cmd struct a human's input fills, so
## bots use exactly the same movement, modules and Flux costs.
##
## Two layers:
##   - BotTeam (shared blackboard): who the team knows about, who to focus, and the
##     team plan (ADVANCE / PUSH / HOLD / REGROUP).
##   - this brain: turns the plan into movement for the bot's ROLE (sniper holds
##     range, brawler closes in, anchor stays with the group and builds cover,
##     flankers circle once the team has contact) and uses every module it owns.
##
## Each hand holds several modules. Every think tick each module gets a score for
## the current situation (_score); when the other slot clearly beats the active
## one the bot rotates to it (costs Flux, rate-limited), just like a player would.

const MIRAGE_SPOT_RANGE := 5.0 # a Mirage user is only noticed this close
const GHOST_SPOT_RANGE := 20.0 # a Ghost user off the radar is only noticed this close
const THINK_EVERY := 0.2
const ROTATE_GAP := 2.5 # seconds between rotations of one hand
const SWITCH_MARGIN := 2.0 # a module must out-score the active one by this much
const FAR := 1.0e6

enum Role { RIFLE, SNIPER, BRAWLER, ANCHOR }

var player: Node
var nav: NavigationAgent3D
var role: int = Role.RIFLE
var flanker: bool = false
var tm: Dictionary = {}
var target: Node = null
var tpos: Vector3 = Vector3.ZERO # where we believe the target is
var can_see: bool = false
var dist: float = 99.0
var hurt_t: float = 0.0

var _owned: Array = []
var _think_t: float = 0.0
var _strafe: float = 1.0
var _strafe_t: float = 0.0
var _aim_err: Vector2 = Vector2.ZERO
var _flank_side: float = 1.0
var _spread_off: Vector3 = Vector3.ZERO
var _mode: String = "patrol"
var _goal: Vector3 = Vector3.ZERO
var _sprint_goal: bool = false
var _patrol_goal: Vector3 = Vector3.ZERO
var _search_seen: Vector3 = Vector3(FAR, FAR, FAR)
var _patrol_t: float = 0.0
var _cd: Array = [0.0, 0.0] # per-hand "don't use again yet"
var _rot_t: Array = [0.0, 0.0]
var _util_cd: float = 0.0
var _scope_t: float = 0.0
var _burst_on: bool = true
var _burst_t: float = 0.5
var _lob: bool = false
var _lob_mod: Module = null
var _want_yaw: float = 0.0
var _want_pitch: float = 0.0
var _yaw_err: float = 1.0
var _pitch_err: float = 1.0
var _stuck_t: float = 0.0
var _stuck_from: Vector3 = Vector3.ZERO


func setup(p: Node) -> void:
	player = p
	nav = p.get_node("NavAgent")
	name = "Brain"
	_think_t = randf() * THINK_EVERY
	_flank_side = 1.0 if randf() < 0.5 else -1.0
	_spread_off = Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
	for h in 2:
		for m in p.modules[h]:
			if m != null:
				_owned.append(m.data.id)
	var first: String = String(p.slot_ids[0][0])
	if "bolt" in _owned:
		role = Role.SNIPER
	elif first == "edge":
		role = Role.BRAWLER
	elif "blast" in _owned or "bunker" in _owned:
		role = Role.ANCHOR
	flanker = role == Role.BRAWLER or ("shift" in _owned and role == Role.RIFLE)


func on_event(kind: String, _data: Dictionary) -> void:
	if kind == "hurt":
		hurt_t = 2.5


func _physics_process(delta: float) -> void:
	var c = player.cmd
	c.clear_fire()
	c.jump = false
	if player.flux.ejected or GameState.phase != GameState.Phase.LIVE:
		c.move = Vector2.ZERO
		c.sprint = false
		return
	hurt_t = maxf(0.0, hurt_t - delta)
	_util_cd -= delta
	_strafe_t -= delta
	_burst_t -= delta
	if _burst_t <= 0.0:
		_burst_on = not _burst_on
		_burst_t = randf_range(0.5, 0.9) if _burst_on else randf_range(0.2, 0.4)
	for h in 2:
		_cd[h] = float(_cd[h]) - delta
		_rot_t[h] = float(_rot_t[h]) - delta
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = THINK_EVERY
		_patrol_t += THINK_EVERY
		_think()
	_pick_lob()
	_aim(delta)
	_use_modules(delta)
	_move(delta)


# --- thinking (every 0.2 s) -----------------------------------------------------

func _think() -> void:
	tm = BotTeam.of(get_tree(), player.team)
	var near: Node = null
	var nd: float = INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.team == player.team or p.flux.ejected:
			continue
		var d: float = player.global_position.distance_to(p.global_position)
		if _hidden(p, d):
			continue
		if d < nd:
			near = p
			nd = d
	var foc: Variant = tm.get("focus", null)
	target = null
	if near != null and nd < 14.0:
		target = near # self-defence beats the team's focus
	elif is_instance_valid(foc) and not foc.flux.ejected:
		target = foc
	elif near != null:
		target = near
	can_see = false
	if target != null:
		var real: Vector3 = target.global_position
		var q := PhysicsRayQueryParameters3D.create(player.eye_pos(), real + Vector3(0, 1.2, 0), 1)
		var clear: bool = player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		can_see = clear and not _hidden(target, player.global_position.distance_to(real))
		var fp: Vector3 = tm.get("focus_pos", real)
		tpos = real if (can_see or target != foc) else fp
		dist = player.global_position.distance_to(tpos)
	_aim_err = Vector2(randf_range(-0.05, 0.05), randf_range(-0.04, 0.04))
	if _strafe_t <= 0.0:
		_strafe = 1.0 if randf() < 0.5 else -1.0
		_strafe_t = randf_range(0.8, 1.8)
	_decide()
	_manage_hands()
	nav.target_position = _goal


## Bots can't see through stealth: Mirage hides you beyond a few metres, Ghost (off the radar) beyond ~20 m.
func _hidden(p: Node, d: float) -> bool:
	if p.flux.stealth == 2:
		return d > MIRAGE_SPOT_RANGE
	if p.flux.stealth == 1 and not p.flux.radar_visible:
		return d > GHOST_SPOT_RANGE
	return false


## Preferred distance band (min, max) for this role under the team plan.
func _band(plan: int) -> Vector2:
	var lo: float = 8.0
	var hi: float = 22.0
	match role:
		Role.SNIPER:
			lo = 26.0
			hi = 55.0
		Role.BRAWLER:
			lo = 0.0
			hi = 3.5
		Role.ANCHOR:
			lo = 14.0
			hi = 30.0
	if plan == BotTeam.Plan.PUSH:
		hi *= 0.8
	elif plan == BotTeam.Plan.HOLD:
		lo *= 1.2
		hi *= 1.3
	return Vector2(lo, hi)


## Where to go and how: sets _mode ("patrol", "close", "hold", "back", "regroup") and _goal.
func _decide() -> void:
	var here: Vector3 = player.global_position
	var f: FluxComponent = player.flux
	var plan: int = tm.get("plan", BotTeam.Plan.ADVANCE)
	var cent: Vector3 = tm.get("centroid", here)
	var mates: int = tm.get("allies", 1)
	_mode = "patrol"
	_sprint_goal = false
	_goal = here
	if target == null:
		_goal = _patrol(here, cent, mates)
		_sprint_goal = here.distance_to(_goal) > 25.0 and f.active_flux > f.max_flux * 0.6
		return
	var band: Vector2 = _band(plan)
	var beaten: bool = f.active_flux < f.max_flux * 0.22 and not _heal_ready()
	if beaten or plan == BotTeam.Plan.REGROUP:
		if mates > 1 and here.distance_to(cent) > 7.0:
			_mode = "regroup"
			_goal = cent
		else:
			_mode = "back" if can_see else "hold"
		return
	if can_see:
		if dist > band.y:
			_mode = "close"
			_goal = tpos
			_sprint_goal = role == Role.BRAWLER and dist > 9.0 and f.active_flux > f.max_flux * 0.4
		elif dist < band.x:
			_mode = "back"
		else:
			_mode = "hold"
		return
	# no line of sight: go to where it was last seen. Flankers circle once a teammate has contact.
	_mode = "close"
	_goal = tpos
	if flanker and plan == BotTeam.Plan.PUSH and bool(tm.get("focus_seen", false)) and dist > 16.0:
		var fpnt: Vector3 = _flank_point(cent)
		if here.distance_to(fpnt) > 5.0:
			_goal = fpnt
	elif role == Role.ANCHOR and mates > 1 and here.distance_to(cent) > 16.0:
		_goal = cent # support stays with the group
	_sprint_goal = dist > 30.0 and f.active_flux > f.max_flux * 0.6


func _snap(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), p)


## A point off to the side of the target, so the group and the flanker hit from two directions.
func _flank_point(cent: Vector3) -> Vector3:
	var axis: Vector3 = tpos - cent
	axis.y = 0.0
	if axis.length() < 1.0:
		return tpos
	axis = axis.normalized()
	var perp := Vector3(-axis.z, 0.0, axis.x) * _flank_side
	return _snap(tpos + perp * 14.0 - axis * 2.0)


## No contact: sweep to the last sighting (or the enemy spawn), then roam. Stay with the team.
func _patrol(here: Vector3, cent: Vector3, mates: int) -> Vector3:
	var s: Vector3 = tm.get("search", here)
	if s.distance_to(_search_seen) > 8.0:
		_search_seen = s
		_patrol_goal = _snap(s + _spread_off)
		_patrol_t = 0.0
	elif here.distance_to(_patrol_goal) < 6.0 or _patrol_t > 30.0:
		_patrol_goal = NavigationServer3D.map_get_random_point(nav.get_navigation_map(), 1, true)
		_patrol_t = 0.0
	if mates > 1 and here.distance_to(cent) > 24.0:
		return cent # don't run ahead of the group
	return _patrol_goal


# --- hands: pick the best module for the situation -------------------------------

func _ally_near(p: Vector3, r: float) -> bool:
	for a in get_tree().get_nodes_in_group("players"):
		if a.team == player.team and not a.flux.ejected and a.global_position.distance_to(p) < r:
			return true
	return false


func _heal_ready() -> bool:
	var f: FluxComponent = player.flux
	return "heal" in _owned and not f.heal_used


func _heal_wanted() -> bool:
	var f: FluxComponent = player.flux
	return _heal_ready() and not f.healing and f.regen_cap() - f.active_flux > 28.0 and hurt_t < 1.0


func _afford(am: Module) -> bool:
	return player.flux.active_flux >= am.data.cost + player.flux.max_flux * 0.1


func _ready_to_use(am: Module) -> bool:
	return am.cooldown_ratio() < 0.02


## How useful module `id` is right now (0 = pointless, 10 = exactly what is needed).
func _score(id: String) -> float:
	var f: FluxComponent = player.flux
	var engaged: bool = target != null and can_see
	var low: bool = f.active_flux < f.max_flux * 0.3
	var known: bool = target != null
	match id:
		"kinetic":
			if not engaged:
				return 2.0
			if dist < 6.0 and "edge" in _owned:
				return 3.0
			return 3.5 if role == Role.BRAWLER else 5.0
		"edge":
			if known and dist < 5.5:
				return 9.0
			if role == Role.BRAWLER and known and dist < 14.0:
				return 6.0
			return 1.0
		"aegis":
			if f.shield_locked:
				return 0.0
			if engaged and hurt_t > 0.2:
				return 8.0
			return 6.0 if (engaged and low) else 1.0
		"boost":
			return 6.0 if (engaged and hurt_t > 1.5) else 1.0
		"shift":
			if f.stealth == 0 and engaged and (role == Role.BRAWLER or flanker) and dist > 10.0 and dist < 22.0:
				return 6.5
			return 1.0
		"blast":
			return 7.0 if (engaged and dist >= 8.0 and dist <= 38.0) else 1.0
		"seeker":
			return 6.0 if (engaged and dist >= 8.0 and dist <= 42.0) else 1.0
		"bolt":
			if engaged and dist >= 16.0:
				return 9.5 if role == Role.SNIPER else 8.5
			return 1.0
		"bunker":
			return 5.0 if (known and dist < 32.0 and _util_cd <= 0.0 and f.active_flux > f.max_flux * 0.4) else 0.5
		"heal":
			return 10.0 if _heal_wanted() else -1.0
		"ghost":
			if f.stealth == 1:
				return 3.0 if engaged else 5.0
			return 5.5 if (not engaged and f.active_flux > f.max_flux * 0.5) else 1.0
		"mirage":
			if f.stealth == 2:
				return 4.0 if (engaged and dist < 5.0) else 5.0
			return 5.5 if (not engaged and f.active_flux > f.max_flux * 0.5) else 1.0
	return 1.0


## Rotate a hand to its other module when that one clearly fits the moment better.
func _manage_hands() -> void:
	var f: FluxComponent = player.flux
	if player.scoped or f.healing or f.active_flux < 6.0:
		return
	var c = player.cmd
	for h in 2:
		if float(_rot_t[h]) > 0.0 or f.hand_off(h):
			continue
		var cur: Module = player.active_module(h)
		if cur == null:
			continue
		var cur_s: float = _score(cur.data.id)
		var best_s: float = cur_s
		for m in player.modules[h]:
			if m != null and m != cur:
				best_s = maxf(best_s, _score(m.data.id))
		if best_s > cur_s + SWITCH_MARGIN:
			c.rotate[h] = true
			_rot_t[h] = ROTATE_GAP


# --- aiming -------------------------------------------------------------------------

## Is a Blast ready to fire? Then the whole aim is lifted to land the lobbed shell.
func _pick_lob() -> void:
	_lob = false
	_lob_mod = null
	if target == null or not can_see or player.scoped:
		return
	if dist < 8.0 or dist > 40.0 or _ally_near(tpos, 6.0):
		return
	for h in 2:
		var am: Module = player.active_module(h)
		if am != null and am.data.id == "blast" and not player.flux.hand_off(h) and _ready_to_use(am) and _afford(am):
			_lob = true
			_lob_mod = am
			return


func _lob_angle(flat: float) -> float:
	var g: float = _lob_mod.tune(&"gravity")
	var v: float = maxf(_lob_mod.tune(&"speed"), 1.0)
	var theta: float = 0.5 * asin(clampf(g * flat / (v * v), 0.0, 0.99))
	return theta - _lob_mod.tune(&"lob")


func _aim(delta: float) -> void:
	var eye: Vector3 = player.eye_pos()
	var look: Vector3
	if target != null:
		look = tpos + Vector3(0, 1.2, 0)
	else:
		var nxt: Vector3 = nav.get_next_path_position()
		look = Vector3(nxt.x, eye.y, nxt.z)
	var to: Vector3 = look - eye
	var flat: float = Vector2(to.x, to.z).length()
	var scale: float = 0.3 if player.scoped else 1.0
	if flat < 0.4:
		_want_yaw = player.yaw
	else:
		_want_yaw = atan2(-to.x, -to.z) + _aim_err.x * scale
	_want_pitch = atan2(to.y, flat) + _aim_err.y * scale
	if _lob:
		_want_pitch += _lob_angle(flat)
	var t: float = clampf((12.0 if player.scoped else 7.0) * delta, 0.0, 1.0)
	player.yaw = lerp_angle(player.yaw, _want_yaw, t)
	player.pitch = clampf(lerpf(player.pitch, _want_pitch, t), -1.4, 1.4)
	_yaw_err = absf(angle_difference(player.yaw, _want_yaw))
	_pitch_err = absf(player.pitch - _want_pitch)


# --- using the modules ----------------------------------------------------------------

func _use_modules(delta: float) -> void:
	var c = player.cmd
	var f: FluxComponent = player.flux
	var engaged: bool = target != null and can_see
	var aimed: bool = _yaw_err < 0.1 and _pitch_err < 0.12
	for h in 2:
		var am: Module = player.active_module(h)
		if am == null or f.hand_off(h):
			continue
		match am.data.id:
			"kinetic":
				c.fire_held[h] = engaged and not _lob and aimed and dist < 45.0 and f.active_flux > am.data.cost + f.max_flux * 0.05 \
						and (_burst_on or dist < 10.0)
			"edge":
				if target != null and dist < am.data.range_m and _yaw_err < 0.5 and _ready_to_use(am) and _afford(am):
					c.fire_pressed[h] = true
			"aegis":
				c.fire_held[h] = engaged and (hurt_t > 0.1 or f.active_flux < f.max_flux * 0.3) and not f.shield_locked and f.active_flux > 8.0
			"boost":
				if engaged and hurt_t > 1.5 and _ready_to_use(am) and _afford(am):
					c.fire_pressed[h] = true
			"shift":
				if engaged and _yaw_err < 0.15 and dist > 10.0 and dist < 22.0 and (role == Role.BRAWLER or flanker) \
						and _ready_to_use(am) and _afford(am):
					c.fire_pressed[h] = true
			"blast":
				if _lob and _lob_mod == am and _yaw_err < 0.05 and _pitch_err < 0.05:
					c.fire_pressed[h] = true
			"seeker":
				if engaged and dist >= 8.0 and dist <= 42.0 and _yaw_err < 0.2 and _ready_to_use(am) and _afford(am):
					c.fire_pressed[h] = true
			"bolt":
				_use_bolt(h, am, engaged, delta)
			"bunker":
				if engaged and dist < 30.0 and _util_cd <= 0.0 and _ready_to_use(am) and _afford(am) and f.active_flux > f.max_flux * 0.4:
					c.fire_pressed[h] = true
					_util_cd = 10.0
			"heal":
				if _heal_wanted() and player.on_ground and not f.sprinting and float(_cd[h]) <= 0.0:
					c.fire_pressed[h] = true
					_cd[h] = 1.0
			"ghost", "mirage":
				if f.stealth == 0 and not engaged and f.active_flux > f.max_flux * 0.5 and float(_cd[h]) <= 0.0:
					c.fire_pressed[h] = true
					_cd[h] = 5.0


## Bolt: stop, scope in, let the aim settle, then fire. Bots can't slide-cancel, so a lost target is dropped explicitly.
func _use_bolt(h: int, am: Module, engaged: bool, delta: float) -> void:
	var c = player.cmd
	if player.scoped:
		_scope_t += delta
		if not engaged and _scope_t > 0.6:
			player.scoped = false
		elif _scope_t > 0.5 and _yaw_err < 0.03 and _pitch_err < 0.03:
			c.fire_pressed[h] = true
		elif _scope_t > 1.6 and engaged and _yaw_err < 0.07:
			c.fire_pressed[h] = true
		elif _scope_t > 3.0:
			player.scoped = false
	else:
		_scope_t = 0.0
		if engaged and dist >= 14.0 and _ready_to_use(am) and _afford(am):
			c.fire_pressed[h] = true # first click: scope in


# --- movement -------------------------------------------------------------------------

func _to_local(dir: Vector3) -> Vector2:
	dir.y = 0.0
	if dir.length() < 0.05:
		return Vector2.ZERO
	dir = dir.normalized()
	var fwd: Vector3 = -player.global_transform.basis.z
	var right: Vector3 = player.global_transform.basis.x
	return Vector2(dir.dot(right), dir.dot(fwd))


func _holding_for_heal() -> bool:
	return "heal" in _owned and (player.flux.healing or (_heal_wanted() and _has_active("heal")))


func _has_active(id: String) -> bool:
	for h in 2:
		var m: Module = player.active_module(h)
		if m != null and m.data.id == id:
			return true
	return false


func _move(delta: float) -> void:
	var c = player.cmd
	var f: FluxComponent = player.flux
	var here: Vector3 = player.global_position
	c.sprint = false
	if player.scoped or _holding_for_heal():
		c.move = Vector2.ZERO
		return
	var tdir := Vector3.ZERO
	if target != null:
		tdir = tpos - here
		tdir.y = 0.0
		if tdir.length() > 0.1:
			tdir = tdir.normalized()
	var perp := Vector3(-tdir.z, 0.0, tdir.x) * _strafe
	var w := Vector3.ZERO
	match _mode:
		"hold":
			w = perp
		"back":
			w = -tdir + perp * 0.6
		_:
			var nxt: Vector3 = nav.get_next_path_position()
			var step: Vector3 = nxt - here
			step.y = 0.0
			if nav.is_navigation_finished() or step.length() < 0.2:
				step = _goal - here
				step.y = 0.0
			if step.length() > 0.1:
				w = step.normalized()
			if _mode == "close" and can_see and role != Role.BRAWLER:
				w += perp * 0.5 # don't walk a straight line into fire
	# keep a few metres between teammates so one grenade can't catch everyone
	for a in get_tree().get_nodes_in_group("players"):
		if a == player or a.team != player.team or a.flux.ejected:
			continue
		var off: Vector3 = here - a.global_position
		off.y = 0.0
		var d: float = off.length()
		if d < 3.5 and d > 0.01:
			w += off / d * ((3.5 - d) / 3.5)
	c.move = _to_local(w).limit_length(1.0)
	c.sprint = _sprint_goal and c.move.y > 0.1 and f.active_flux > 5.0
	# stuck against a low obstacle: hop over it
	_stuck_t += delta
	if _stuck_t >= 0.7:
		if w.length() > 0.3 and here.distance_to(_stuck_from) < 0.5 and player.is_on_floor():
			c.jump = true
		_stuck_from = here
		_stuck_t = 0.0
