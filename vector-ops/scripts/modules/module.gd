class_name Module
extends Node
## Base class for every module (Task 3.1). All modules share one lifecycle:
##   activate() / deactivate()          - equipped/unequipped
##   controller_update(delta)           - runs on the peer controlling the player
##   server_use(args)                   - runs on the server when a request arrives
## Each module sits in one hand: 0 = right hand (left mouse), 1 = left hand
## (right mouse). Both hands are live at the same time. Each hand has several
## slots; only the module in the hand's current slot is active.

var player: Node = null
var data: ModuleData = null
var hand: int = 0
var slot_index: int = 0
var is_active: bool = false


func setup(p: Node, h: int, s: int) -> void:
	player = p
	hand = h
	slot_index = s
	name = "Mod_%d_%d_%s" % [h, s, data.id]


func activate() -> void:
	is_active = true
	_on_activate()


func deactivate() -> void:
	is_active = false
	_on_deactivate()


func _on_activate() -> void:
	pass


func _on_deactivate() -> void:
	pass


func controller_update(_delta: float) -> void:
	pass


func server_use(_args: Dictionary) -> void:
	pass


## Is this module's mouse button held / just pressed?
func held() -> bool:
	return player.cmd.fire_held[hand]


func pressed() -> bool:
	return player.cmd.fire_pressed[hand]


## A module-specific number from this module's data file (ModuleData.tuning).
func tune(key: StringName) -> float:
	return data.tune(key)


## 0 = ready, 1 = just used. The HUD greys the module's icon by this much.
func cooldown_ratio() -> float:
	return 0.0


func send(args: Dictionary) -> void:
	player.request(hand, data.id, args)


func is_enemy(c: Object) -> bool:
	if c == null or not (c is Node):
		return false
	var n: Node = c
	if not n.is_in_group("players"):
		return false
	return n.team != player.team and not n.flux.ejected


## Random direction inside a cone of `deg` degrees around `dir`.
func cone(dir: Vector3, deg: float) -> Vector3:
	var ang: float = deg_to_rad(deg) * sqrt(randf())
	var rot: float = randf() * TAU
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var b := Basis.looking_at(dir, up)
	return (b * Vector3(sin(ang) * cos(rot), sin(ang) * sin(rot), -cos(ang))).normalized()


## Which body part a world-space hit point falls on (aim skill).
func hit_zone(target: Node, hit_pos: Vector3) -> String:
	var l: Vector3 = target.to_local(hit_pos)
	if l.y >= 1.45:
		return "head"
	if l.y < 0.7:
		return "leg"
	if absf(l.x) > 0.24:
		return "arm_r" if l.x > 0.0 else "arm_l"
	return "torso"


## Server helper: apply damage, limb effects and feedback to both parties.
func hit_player(target: Node, dmg: float, src: String, zone: String = "torso", shield_break: bool = false) -> Dictionary:
	var res: Dictionary = target.flux.take_damage(dmg, player, src, player.global_position, zone, shield_break)
	var blocked: bool = res.get("blocked", false)
	if not blocked:
		target.flux.apply_limb(zone)
	target.send_event("hurt", {"from": player.global_position, "blocked": blocked, "zone": zone})
	player.send_event("hit", {"killed": target.flux.ejected, "blocked": blocked, "zone": zone})
	return res
