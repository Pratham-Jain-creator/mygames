class_name BotTeam
extends RefCounted
## Shared "blackboard" for the bots of one team (server only). Bots do not each
## hunt the nearest enemy on their own: once every 0.4 s one call to of() looks at
## the whole team and works out
##   - intel:    which enemies the team knows about (seen by any teammate, or on
##               the radar within RADAR_RANGE), and where they were last seen
##   - focus:    the one enemy everybody should shoot (weakest, close to the group)
##   - plan:     ADVANCE (look for them), PUSH (attack together), HOLD (outnumbered
##               but healthy: keep range, use cover) or REGROUP (hurt or scattered:
##               gather at the team's centre)
## BotBrain reads this and decides what its own role does about it.

enum Plan { ADVANCE, PUSH, HOLD, REGROUP }

const THINK_EVERY := 0.4
const INTEL_TTL := 5.0 # seconds an unseen enemy stays "known"
const SIGHT_RANGE := 70.0
const RADAR_RANGE := 40.0
const SPREAD_LIMIT := 28.0 # allies further apart than this are told to gather
const FOCUS_STICKY := 30.0 # score bonus for keeping the current focus

static var _round: int = -1
static var _teams: Dictionary = {}


## The team's current picture: {time, centroid, plan, focus, focus_pos, focus_seen, search, allies, enemies}.
static func of(tree: SceneTree, team: int) -> Dictionary:
	if GameState.round_number != _round:
		_round = GameState.round_number
		_teams.clear()
	var now: float = Time.get_ticks_msec() / 1000.0
	var t: Dictionary = _teams.get(team, {})
	if t.is_empty() or now - float(t["time"]) >= THINK_EVERY:
		t = _think(tree, team, now, t)
		_teams[team] = t
	return t


static func _think(tree: SceneTree, team: int, now: float, old: Dictionary) -> Dictionary:
	var allies: Array = []
	var enemies: Array = []
	for p in tree.get_nodes_in_group("players"):
		if p.flux.ejected:
			continue
		if p.team == team:
			allies.append(p)
		else:
			enemies.append(p)

	var intel: Dictionary = old.get("intel", {})
	for e in enemies:
		var seen: bool = false
		var on_radar: bool = false
		for a in allies:
			var d: float = a.global_position.distance_to(e.global_position)
			if _spots(a, e, d):
				seen = true
				break
			if d < RADAR_RANGE and e.flux.radar_visible:
				on_radar = true
		if seen or on_radar:
			intel[e.get_instance_id()] = {"node": e, "pos": e.global_position, "time": now, "seen": seen}
	for k in intel.keys():
		var node: Variant = intel[k]["node"]
		if not is_instance_valid(node) or node.flux.ejected:
			intel.erase(k)

	var centroid := Vector3.ZERO
	var frac := 0.0
	for a in allies:
		centroid += a.global_position
		frac += a.flux.active_flux / maxf(a.flux.max_flux, 1.0)
	if not allies.is_empty():
		centroid /= float(allies.size())
		frac /= float(allies.size())
	var spread := 0.0
	for a in allies:
		spread = maxf(spread, a.global_position.distance_to(centroid))

	# focus: the weakest enemy the team knows about, near the group, sticking with the old choice
	var old_focus: Variant = old.get("focus", null)
	var focus: Node = null
	var focus_rec: Dictionary = {}
	var best: float = INF
	for k in intel:
		var rec: Dictionary = intel[k]
		if now - float(rec["time"]) > INTEL_TTL:
			continue
		var e: Node = rec["node"]
		var score: float = e.flux.total_flux() + 0.6 * Vector3(rec["pos"]).distance_to(centroid)
		if is_instance_valid(old_focus) and e == old_focus:
			score -= FOCUS_STICKY
		if not bool(rec["seen"]):
			score += 15.0 # prefer someone we can actually see
		if score < best:
			best = score
			focus = e
			focus_rec = rec

	var plan: int = Plan.ADVANCE
	if focus != null:
		if (allies.size() < enemies.size() and frac < 0.5) or frac < 0.3:
			plan = Plan.REGROUP
		elif spread > SPREAD_LIMIT and allies.size() > 1:
			plan = Plan.REGROUP
		elif allies.size() >= enemies.size():
			plan = Plan.PUSH
		else:
			plan = Plan.HOLD

	return {
		"time": now, "intel": intel, "centroid": centroid, "plan": plan,
		"focus": focus, "focus_pos": focus_rec.get("pos", centroid), "focus_seen": bool(focus_rec.get("seen", false)),
		"search": _search_point(tree, team, intel), "allies": allies.size(), "enemies": enemies.size(),
	}


## Can `a` see enemy `e` (stealth rules included)?
static func _spots(a: Node, e: Node, d: float) -> bool:
	if d > SIGHT_RANGE:
		return false
	if e.flux.stealth == 2 and d > BotBrain.MIRAGE_SPOT_RANGE:
		return false
	if e.flux.stealth == 1 and not e.flux.radar_visible and d > BotBrain.GHOST_SPOT_RANGE:
		return false
	var q := PhysicsRayQueryParameters3D.create(a.eye_pos(), e.global_position + Vector3(0, 1.2, 0), 1)
	return a.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Where to look when nobody is known: the freshest stale sighting, else the enemy spawn.
static func _search_point(tree: SceneTree, team: int, intel: Dictionary) -> Vector3:
	var newest: float = -1.0
	var pos := Vector3.ZERO
	for k in intel:
		if float(intel[k]["time"]) > newest:
			newest = float(intel[k]["time"])
			pos = intel[k]["pos"]
	if newest >= 0.0:
		return pos
	var pts: Array = tree.get_nodes_in_group("spawn_%d" % (1 - team))
	if pts.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for m in pts:
		c += (m as Node3D).global_position
	return c / float(pts.size())
