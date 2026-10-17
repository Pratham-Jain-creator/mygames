extends EnemyBase
class_name RangedEnemy
## Ranged enemy used for the Skeleton Archer, the Mage and the Ghast. Their looks come from the
## AnimatedSprite2D in each scene; everything else (range, cooldown, projectile style, spread, homing...) is an exported parameter.
##
## Intention: keep a comfortable distance (back away if you get close, approach if you are far),
## stop and telegraph (tinted, aiming at you), then shoot, then recover.

@export_group("Shooting")
@export var projectile_scene: PackedScene = preload("res://scenes/enemies/projectile.tscn")
@export var projectile_style: Projectile.Style = Projectile.Style.ARROW
@export var projectile_speed: float = 150.0
@export var projectile_damage: int = 8
@export var projectile_knockback: float = 100.0
@export var projectile_life: float = 3.0
## Projectiles per attack (the mage fires a spread).
@export var shots: int = 1
@export var spread_degrees: float = 0.0
## Radians/second the projectile can steer toward the player (the ghast's fireballs). 0 = straight.
@export var homing_turn: float = 0.0
@export var muzzle_offset: Vector2 = Vector2(0, 4)
@export var requires_line_of_sight: bool = true
@export_group("Spacing")
## Back away when the player is closer than this.
@export var keep_distance_min: float = 70.0

var _strafe: float = 1.0


func _enter_state(s: State) -> void:
	super(s)
	if s == State.ATTACK:
		_fire()
	if s == State.CHASE:
		_strafe = 1.0 if randf() < 0.5 else -1.0


func _update_chase(_delta: float) -> void:
	var to := _to_player()
	_face(to)
	var d := to.length()
	var clear := (not requires_line_of_sight) or _has_line_of_sight()
	if d <= attack_range and clear and _cooldown <= 0.0:
		_change_state(State.WINDUP)
		return
	var dir := to.normalized()
	if d < keep_distance_min:
		velocity = -dir * move_speed                       # too close: back away
	elif d > attack_range * 0.85 or not clear:
		velocity = dir * move_speed                         # too far / blocked: approach
	else:
		velocity = dir.orthogonal() * move_speed * 0.4 * _strafe  # in position: strafe a little


func _has_line_of_sight() -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, player.global_position, 1)
	q.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _fire() -> void:
	if projectile_scene == null or player == null:
		return
	var base_dir := _to_player().normalized()
	var origin := global_position + muzzle_offset
	for i in shots:
		var offset := 0.0
		if shots > 1:
			offset = deg_to_rad(spread_degrees) * (float(i) / float(shots - 1) - 0.5)
		var p := projectile_scene.instantiate() as Projectile
		p.setup(base_dir.rotated(offset), projectile_speed, int(ceil(projectile_damage * damage_multiplier)), projectile_knockback, projectile_style, homing_turn, projectile_life, player)
		get_parent().add_child(p)
		p.global_position = origin
