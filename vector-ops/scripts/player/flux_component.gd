class_name FluxComponent
extends Node
## Flux = health + stamina + energy (Milestone 1). Server-authoritative.
##
## max_flux       capacity from loadout weight
## active_flux    spendable + regenerating pool (actions drain it)
## fractured_flux permanent loss; lowers the cap active flux can regen to
## Total Flux = max_flux - fractured_flux. At 0 the player is Ejected.
##
## Damage drains Active first, then spills into Fractured. Aegis converts
## incoming damage into Active Flux cost and never protects Fractured Flux.

const REGEN_RATE := 5.0
const REGEN_DELAY := 0.5 # pause after taking damage
const SPEND_PAUSE := 0.4 # pause after ANY Flux spend (shooting, sprint, shield...)
const SPRINT_COST := 3.0
const AEGIS_COST := 2.0 # upkeep per second
const SWITCH_COST := 3.0 # rotating a hand to its next module
const BLOCK_RATIO := 0.6 # Active Flux paid per point of blocked damage
const SHIELD_ARC_DOT := 0.707 # 45 degrees either side of facing (90 degree arc)
const SHIELD_RAISE_MS := 250 # shield only blocks once it has finished raising
const BREAK_MULT := 2.5 # Edge hits cost the shield this much more...
const AEGIS_LOCK_MS := 1000 # ...and lock Aegis out for this long
const LEG_SLOW_MS := 2000
const ARM_OFF_MS := 500
const DEFLECT_MS := 350 # Edge swing window that reflects Kinetic rounds
const GHOST_COST := 1.5 # upkeep per second
const MIRAGE_COST := 1.0
const STEALTH_ON_COST := 3.0
const SIG_USE := 6.0 # radar signature (seconds) left by using any other module
const SIG_BOLT := 12.0
const STILL_SPEED := 0.4 # m/s below which you count as standing still
const STILL_TIME := 0.4 # seconds of stillness before the bonus applies
const STILL_REGEN_MULT := 3.0
const HEAL_TIME := 0.4 # seconds the Heal needs: quick, but a hit still cancels it
const HEAL_MOVE_LIMIT := 2.5 # metres you may drift (walking is fine) before it is cancelled
const FALL_KILL_Y := -6.0 # below this height (arena floor is y = 0) you fell off the map

var max_flux: float = 100.0
var active_flux: float = 100.0
var fractured_flux: float = 0.0
var ejected: bool = false
var shield_on: bool = false
var slot0: int = 0 # equipped slot, right hand
var slot1: int = 0 # equipped slot, left hand
# limb / shield status (replicated, derived on the server)
var shield_locked: bool = false
var slowed: bool = false
var arm0_off: bool = false
var arm1_off: bool = false
# stealth (replicated): 0 none, 1 Ghost (hidden from radar), 2 Mirage (invisible body)
var stealth: int = 0
var radar_visible: bool = true
# Heal (replicated): one use per round, refills Active Flux up to regen_cap()
var heal_used: bool = false
var healing: bool = false

# server-only state
var heal_t: float = 0.0
var _heal_origin: Vector3 = Vector3.ZERO
var _heal_log_mark: int = 0
var signature: float = 0.0
var still_t: float = 0.0
var _prev_pos: Vector3 = Vector3.ZERO
var last_spend_ms: int = 0
var deflect_until: int = 0
var sprinting: bool = false
var regen_pause: float = 0.0
var spent_log: Dictionary = {}
var damage_log: Array = []
var killer_info: Dictionary = {}
var kill_log: Dictionary = {} # weapon -> kills this round
var rotations: int = 0
var shield_breaks: int = 0
var shield_up_ms: int = 0
var shield_lock_until: int = 0
var leg_until: int = 0
var arm_until: Array = [0, 0]

var player: Node = null


func build_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":max_flux", ":active_flux", ":fractured_flux", ":ejected", ":shield_on", ":slot0", ":slot1",
			":shield_locked", ":slowed", ":arm0_off", ":arm1_off", ":stealth", ":radar_visible", ":heal_used", ":healing"]:
		var np := NodePath(prop)
		cfg.add_property(np)
		cfg.property_set_replication_mode(np, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = cfg
	add_child(sync)


func slot_of(hand: int) -> int:
	return slot0 if hand == 0 else slot1


func set_slot(hand: int, s: int) -> void:
	if hand == 0:
		slot0 = s
	else:
		slot1 = s


func hand_off(hand: int) -> bool:
	return arm0_off if hand == 0 else arm1_off


func total_flux() -> float:
	return maxf(0.0, max_flux - fractured_flux)


func regen_cap() -> float:
	return maxf(0.0, max_flux - fractured_flux)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var now: int = Time.get_ticks_msec()
	shield_locked = now < shield_lock_until
	slowed = now < leg_until
	arm0_off = now < int(arm_until[0])
	arm1_off = now < int(arm_until[1])
	if ejected or GameState.phase != GameState.Phase.LIVE:
		return
	if player != null and player.global_position.y < FALL_KILL_Y:
		fall_eject()
		return
	_stealth_tick(delta)
	if healing:
		_heal_tick(delta)
	# standing still (on the ground, not sprinting) speeds up regeneration
	var moved: float = Vector2(player.global_position.x - _prev_pos.x, player.global_position.z - _prev_pos.z).length() / maxf(delta, 0.0001)
	var rose: float = absf(player.global_position.y - _prev_pos.y)
	_prev_pos = player.global_position
	if moved < STILL_SPEED and rose < 0.05 and not sprinting:
		still_t += delta
	else:
		still_t = 0.0
	if regen_pause > 0.0:
		regen_pause -= delta
	if shield_on:
		drain(AEGIS_COST * delta, "aegis")
		if active_flux <= 0.0:
			shield_on = false
	if sprinting:
		drain(SPRINT_COST * delta, "sprint")
		if active_flux <= 0.0:
			sprinting = false
	# no regen while spending, shielding or sprinting
	if regen_pause <= 0.0 and not shield_on and not sprinting:
		var mult: float = STILL_REGEN_MULT if still_t >= STILL_TIME else 1.0
		active_flux = minf(active_flux + REGEN_RATE * mult * delta, regen_cap())


## Server: begins the channel. Returns false (nothing happens) if it is used up, running, or pointless.
func start_heal() -> bool:
	if ejected or heal_used or healing or player == null:
		return false
	if active_flux >= regen_cap() - 3.0:
		return false # nothing worth healing
	if not player.on_ground or sprinting:
		return false
	healing = true
	heal_t = HEAL_TIME
	_heal_origin = player.global_position
	_heal_log_mark = damage_log.size()
	shield_on = false
	var p: Vector3 = player.global_position + Vector3(0, 1.2, 0)
	player.fx_play.rpc("heal", p, p)
	return true


func _heal_tick(delta: float) -> void:
	var drift: float = Vector2(player.global_position.x - _heal_origin.x, player.global_position.z - _heal_origin.z).length()
	var hurt: bool = damage_log.size() != _heal_log_mark
	if hurt or drift > HEAL_MOVE_LIMIT or sprinting or not _has_equipped("heal") or not player.on_ground:
		healing = false
		player.send_event("deny", {})
		return
	heal_t -= delta
	if heal_t <= 0.0:
		healing = false
		heal_used = true
		active_flux = regen_cap()
		regen_pause = 0.0
		var p: Vector3 = player.global_position + Vector3(0, 1.2, 0)
		player.fx_play.rpc("heal", p, p + Vector3.UP * 0.01)


func _has_equipped(id: String) -> bool:
	for h in 2:
		var m = player.active_module(h)
		if m != null and m.data.id == id:
			return true
	return false


func _stealth_tick(delta: float) -> void:
	# the stealth module must stay equipped (in an active slot) to keep working
	if stealth == 1 and not _has_equipped("ghost"):
		stealth = 0
	elif stealth == 2 and not _has_equipped("mirage"):
		stealth = 0
	if stealth != 0:
		# stealth upkeep does not stop regeneration, it just eats into it
		drain((GHOST_COST if stealth == 1 else MIRAGE_COST) * delta, "ghost" if stealth == 1 else "mirage", false)
		if active_flux <= 0.0:
			stealth = 0
	if shield_on:
		signature = maxf(signature, SIG_USE)
	# the signature only fades while Ghost is running
	if stealth == 1:
		signature = maxf(0.0, signature - delta)
	radar_visible = stealth != 1 or signature > 0.0


## Ghost / Mirage toggle. Turning one on turns the other off.
func toggle_stealth(mode: int) -> void:
	if stealth == mode:
		stealth = 0
		return
	if not spend(STEALTH_ON_COST, "stealth"):
		return
	stealth = mode


func is_deflecting(from_pos: Vector3) -> bool:
	if Time.get_ticks_msec() >= deflect_until or player == null:
		return false
	var facing: Vector3 = -player.head.global_transform.basis.z
	var to_a: Vector3 = from_pos - player.global_position
	to_a.y = 0.0
	facing.y = 0.0
	if to_a.length() < 0.01 or facing.length() < 0.01:
		return true
	return facing.normalized().dot(to_a.normalized()) > 0.5


## Discrete cost. Returns false (and spends nothing) if Active Flux is short.
func spend(amount: float, reason: String) -> bool:
	if ejected or active_flux < amount:
		return false
	active_flux -= amount
	last_spend_ms = Time.get_ticks_msec()
	regen_pause = maxf(regen_pause, SPEND_PAUSE)
	spent_log[reason] = float(spent_log.get(reason, 0.0)) + amount
	if reason == "rotate":
		rotations += 1
	return true


## Continuous cost (sprint / aegis upkeep).
func drain(amount: float, reason: String, pause: bool = true) -> void:
	var taken := minf(amount, active_flux)
	active_flux -= taken
	if pause:
		regen_pause = maxf(regen_pause, SPEND_PAUSE)
	spent_log[reason] = float(spent_log.get(reason, 0.0)) + taken


func set_shield(on: bool) -> void:
	if on == shield_on:
		return
	if on and (shield_locked or active_flux <= 1.0):
		return
	shield_on = on
	if on:
		shield_up_ms = Time.get_ticks_msec()


## Leg hits slow you, arm hits switch that hand off briefly.
func apply_limb(zone: String) -> void:
	if ejected:
		return
	var now: int = Time.get_ticks_msec()
	match zone:
		"leg":
			leg_until = now + LEG_SLOW_MS
		"arm_r":
			arm_until[0] = now + ARM_OFF_MS
		"arm_l":
			arm_until[1] = now + ARM_OFF_MS


func _fx(kind: String) -> void:
	if player != null:
		var p: Vector3 = player.global_position + Vector3(0, 1.2, 0)
		player.fx_play.rpc(kind, p, p)


## All damage routes through here (Task 1.3). Server only.
func take_damage(amount: float, attacker: Node, source: String, from_pos: Vector3,
		zone: String = "torso", shield_break: bool = false) -> Dictionary:
	if ejected or not multiplayer.is_server():
		return {}
	var dist := 0.0
	if player != null:
		dist = player.global_position.distance_to(from_pos)
	var entry := {
		"attacker": attacker.display_name if attacker != null else "?",
		"src": source,
		"amount": amount,
		"blocked": false,
		"broke": false,
		"spill": 0.0,
		"dist": dist,
		"zone": zone,
		"exhausted": active_flux <= 0.01,
	}
	var remaining := amount
	var now: int = Time.get_ticks_msec()
	if shield_on and active_flux > 0.0 and _shielded_from(from_pos) and now >= shield_up_ms + SHIELD_RAISE_MS:
		var ratio := BLOCK_RATIO * (BREAK_MULT if shield_break else 1.0)
		var cost := amount * ratio
		regen_pause = maxf(regen_pause, REGEN_DELAY)
		if active_flux >= cost:
			active_flux -= cost
			spent_log["aegis_blocks"] = float(spent_log.get("aegis_blocks", 0.0)) + cost
			entry["blocked"] = true
			if shield_break:
				entry["broke"] = true
				shield_breaks += 1
				shield_on = false
				shield_lock_until = now + AEGIS_LOCK_MS
				_fx("sbreak")
			else:
				_fx("block")
			damage_log.append(entry)
			return {"blocked": true, "broke": shield_break}
		# overwhelmed: the shield eats what Active Flux it can, then collapses
		var absorbed := minf(amount, active_flux / ratio)
		spent_log["aegis_blocks"] = float(spent_log.get("aegis_blocks", 0.0)) + absorbed * ratio
		active_flux = maxf(0.0, active_flux - absorbed * ratio)
		remaining = amount - absorbed
		shield_on = false
		shield_lock_until = now + AEGIS_LOCK_MS
		shield_breaks += 1
		entry["broke"] = true
		_fx("sbreak")

	var from_active := minf(remaining, active_flux)
	active_flux -= from_active
	var spill := remaining - from_active
	fractured_flux = minf(fractured_flux + spill, max_flux)
	active_flux = minf(active_flux, regen_cap())
	regen_pause = REGEN_DELAY
	entry["spill"] = spill
	damage_log.append(entry)

	if fractured_flux >= max_flux - 0.001:
		_eject(attacker, source, dist)
	return {"blocked": false, "spill": spill}


## Is Aegis up and facing `from_pos`? (used by the Seeker, which is stopped outright)
func shield_stops(from_pos: Vector3) -> bool:
	return shield_on and active_flux > 0.0 and _shielded_from(from_pos)


func _shielded_from(from_pos: Vector3) -> bool:
	if player == null:
		return false
	var head: Node3D = player.head
	var facing: Vector3 = -head.global_transform.basis.z
	var to_attacker: Vector3 = (from_pos - player.global_position)
	if to_attacker.length() < 0.01:
		return true
	return facing.dot(to_attacker.normalized()) > SHIELD_ARC_DOT


## Fell off the edge of the map: instant Eject, no attacker. Server only.
func fall_eject() -> void:
	if ejected or not multiplayer.is_server():
		return
	fractured_flux = max_flux
	_eject(null, "fall", 0.0)
	killer_info["name"] = "the arena edge"
	if player != null:
		player.send_event("ejected_by", {"name": "the arena edge", "src": "fall", "dist": 0.0})


func _eject(attacker: Node, source: String, dist: float) -> void:
	ejected = true
	active_flux = 0.0
	healing = false
	shield_on = false
	sprinting = false
	stealth = 0
	killer_info = {
		"name": attacker.display_name if attacker != null else "unknown",
		"src": source,
		"dist": dist,
	}
	if attacker != null and attacker != player and "flux" in attacker:
		attacker.flux.kill_log[source] = int(attacker.flux.kill_log.get(source, 0)) + 1
		GameState.record_kill(attacker, source)
	if player != null:
		var kn: String = "yourself" if attacker == player else String(killer_info["name"])
		player.send_event("ejected_by", {"name": kn, "src": source, "dist": dist})


## Plain-language post-round explanation (Task 7.2).
func build_report() -> String:
	var lines: PackedStringArray = []
	if ejected:
		lines.append("You were EJECTED by %s's %s from %d m away." % [
			killer_info.get("name", "?"), killer_info.get("src", "?"), int(killer_info.get("dist", 0.0))])
	else:
		lines.append("You survived with %d / %d total Flux (Active %d, Fractured %d)." % [
			int(total_flux()), int(max_flux), int(active_flux), int(fractured_flux)])

	lines.append("Your kills this round: %s." % GameState.kills_text(kill_log))
	var taken: Dictionary = {}
	var zones: Dictionary = {}
	var blocked_n := 0
	var blocked_dmg := 0.0
	var exhausted_hits := 0
	for e in damage_log:
		if e["blocked"]:
			blocked_n += 1
			blocked_dmg += e["amount"]
			continue
		var key: String = "%s (%s)" % [e["src"], e["attacker"]]
		var rec: Array = taken.get(key, [0, 0.0])
		rec[0] += 1
		rec[1] += e["amount"]
		taken[key] = rec
		zones[e["zone"]] = int(zones.get(e["zone"], 0)) + 1
		if e["exhausted"]:
			exhausted_hits += 1
	if taken.is_empty() and blocked_n == 0:
		lines.append("You took no damage.")
	else:
		var parts: PackedStringArray = []
		for k in taken:
			parts.append("%dx %s for %d" % [taken[k][0], k, int(taken[k][1])])
		if not parts.is_empty():
			lines.append("Damage taken: " + ", ".join(parts) + ".")
		if blocked_n > 0:
			lines.append("Aegis blocked %d hits (%d damage) for %d Flux." % [
				blocked_n, int(blocked_dmg), int(float(spent_log.get("aegis_blocks", 0.0)))])
	var zparts: PackedStringArray = []
	for z in zones:
		if z != "torso":
			zparts.append("%d %s" % [zones[z], String(z).replace("_", " ")])
	if not zparts.is_empty():
		lines.append("Hit locations: " + ", ".join(zparts) + ".")
	lines.append("%d Flux was permanently Fractured." % int(fractured_flux))

	var total_spent := 0.0
	for k in spent_log:
		total_spent += spent_log[k]
	if total_spent > 0.0:
		var sp: PackedStringArray = []
		for k in spent_log:
			if spent_log[k] >= 1.0:
				sp.append("%s %d" % [String(k).capitalize().replace("_", " "), int(spent_log[k])])
		lines.append("Flux you spent: " + ", ".join(sp) + " (total %d)." % int(total_spent))

	lines.append("")
	lines.append("What to learn:")
	var tips := 0
	if exhausted_hits > 0:
		lines.append("- %d hit(s) landed while your Active Flux was empty. Those went straight into Fractured Flux." % exhausted_hits)
		tips += 1
	if shield_breaks > 0:
		lines.append("- Your Aegis broke %d time(s). Edge hits cost the shield 2.5x and lock it out - strafe, shoot or Blink away from melee." % shield_breaks)
		tips += 1
	if float(spent_log.get("aegis", 0.0)) > 20.0:
		lines.append("- Holding Aegis cost %d Flux just to keep it up. Drop it when nobody is shooting at you." % int(spent_log["aegis"]))
		tips += 1
	if float(spent_log.get("sprint", 0.0)) > 20.0:
		lines.append("- Sprinting cost %d Flux and blocks regeneration. Move on foot near enemies; sprint only to cross open ground." % int(spent_log["sprint"]))
		tips += 1
	if rotations >= 4:
		lines.append("- You rotated equipment %d times (%d Flux). Pick the right module before the fight." % [rotations, rotations * int(SWITCH_COST)])
		tips += 1
	var loadout_w: float = maxf(0.0, 100.0 - max_flux)
	if loadout_w > 12.0:
		lines.append("- Your loadout cost %d Max Flux in weight. Heavier hands mean less life." % int(loadout_w))
		tips += 1
	var mobility := float(spent_log.get("boost", 0.0)) + float(spent_log.get("shift", 0.0))
	if mobility > 40.0:
		lines.append("- Mobility cost %d Flux. Repositioning spends life." % int(mobility))
		tips += 1
	if int(zones.get("head", 0)) >= 2:
		lines.append("- You took %d headshots. Keep moving and break line of sight instead of standing still." % int(zones["head"]))
		tips += 1
	if ejected:
		var src: String = killer_info.get("src", "")
		var d: float = killer_info.get("dist", 0.0)
		if src == "Kinetic" and d < 8.0:
			lines.append("- You were shot at close range. Edge beats Kinetic inside 6 m - close the gap or break line of sight.")
			tips += 1
		elif src == "Kinetic" and d > 25.0:
			lines.append("- You were picked off from %d m. Break the sightline sooner." % int(d))
			tips += 1
		elif src == "Edge":
			lines.append("- You were cut down in melee. Keep range - Aegis will not hold against Edge.")
			tips += 1
	if tips == 0:
		lines.append("- No obvious Flux misuse. Positioning and timing decided this round.")
	return "\n".join(lines)
