class_name Blade
extends Node2D
## The prisoner's sword. There is ONE weapon; the Weapon Mold boon room switches its FORM, and each form uses one of
## the prisoner's three attack animations: SWEEP (wide arc), JAB (long narrow thrust), SLAM (heavy ground smash).
## RunData.FORMS holds the numbers.
##
## A swing is a plain geometric test, no physics areas: while the attack animation is on its ACTIVE frames, every
## enemy inside the fan (or, for the slam, inside the impact circle) is hit once. The animation's own slash arcs
## are the visuals; a faint flash shows the exact area that hurts.

signal hit_landed(enemy: Node2D)

const HIT_STOP: float = 0.04
## Enemy bodies are not points: this much is added to the reach.
const ENEMY_RADIUS: float = 9.0
## The body steps into the blow.
const LUNGE_SPEED: float = 70.0

var attacking: bool = false

var _player: CharacterBody2D
var _anim: AnimatedSprite2D
var _form: Dictionary = {}
var _form_id: StringName = &"sweep"
var _facing: Vector2 = Vector2.DOWN
var _cooldown: float = 0.0
var _hit: Dictionary = {}      # instance id -> true, who this swing has hit already
var _swish: Polygon2D
var _active_now: bool = false
var _lunged: bool = false

# the sword overlay (your sword sprites, drawn in the prisoner's own 64 px cell so they sit on him exactly)
## How much bigger than the character the slash effect is drawn (the sword itself is never scaled).
const VFX_SCALE: float = 2.4
enum Pose { SHEATHED, SWING, READY, SHEATHING }
## Seconds the sword stays drawn after a swing before it is put away.
const READY_HOLD: float = 0.4
const SHEATHE_FPS: float = 32.0
var _pose: Pose = Pose.SHEATHED
var _hold: float = 0.0
var _sheathe_time: float = 0.0
var _swing_dir: String = "down"
var _sword_sprite: AnimatedSprite2D
var _vfx_sprite: AnimatedSprite2D
var _vfx_frames: SpriteFrames


func setup(player: CharacterBody2D, anim: AnimatedSprite2D) -> void:
	_player = player
	_anim = anim
	_swish = Polygon2D.new()
	_swish.color = Color(1, 1, 1, 0.0)
	_swish.z_index = 4
	add_child(_swish)
	_sword_sprite = AnimatedSprite2D.new()
	_sword_sprite.sprite_frames = SpriteLib.sword()
	_sword_sprite.z_index = 1
	add_child(_sword_sprite)
	_vfx_frames = SpriteLib.sword_vfx()
	_vfx_sprite = AnimatedSprite2D.new()
	_vfx_sprite.sprite_frames = _vfx_frames
	_vfx_sprite.z_index = 2
	_vfx_sprite.visible = false
	add_child(_vfx_sprite)


## The sheet's four views for the prisoner's eight facings.
func _view_of(facing_name: String) -> String:
	if facing_name.contains("left"):
		return "left"
	if facing_name.contains("right"):
		return "right"
	return facing_name


func _set_frame(sprite: AnimatedSprite2D, anim_name: String, frame: int) -> void:
	if not sprite.sprite_frames.has_animation(anim_name):
		return
	if sprite.animation != anim_name or sprite.is_playing():
		sprite.animation = anim_name
		sprite.stop()
	sprite.frame = clampi(frame, 0, sprite.sprite_frames.get_frame_count(anim_name) - 1)


## The sword is drawn from the scabbard on his right hip when he attacks, swings fast with the slash effect over it, is held
## drawn for a moment (so a combo never re-sheathes in between) and then slides back in. Facing left, the scabbard is
## drawn BEHIND his body (his right side is turned away from us). The effect is rotated to the attack direction.
func _process(delta: float) -> void:
	if _player == null or _sword_sprite == null:
		return
	var dead: bool = _player.is_dead
	_sword_sprite.visible = not dead
	_vfx_sprite.visible = false
	if dead:
		return
	# the overlays are locked to the body sprite
	_sword_sprite.position = _anim.position
	_sword_sprite.scale = _anim.scale
	_vfx_sprite.position = _anim.position
	_vfx_sprite.scale = _anim.scale * VFX_SCALE
	var ranged := bool(RunData.FORMS[Run.form].get("ranged", false)) if not attacking else bool(_form.get("ranged", false))
	var swinging := attacking and not ranged and _anim.animation.begins_with("attack_")
	var view := _swing_dir if swinging else _view_of(_player.facing_name())
	_sword_sprite.z_index = -1 if (view == "left" and _pose == Pose.SHEATHED) else 1
	if swinging:
		_pose = Pose.SWING
	elif _pose == Pose.SWING:
		_pose = Pose.READY
		_hold = READY_HOLD
	match _pose:
		Pose.SWING:
			# one frame ahead, so the blade is already forward when the damage frames come
			var frame := int(float(_anim.frame + 1) * 6.0 / float(_form["frames"]))
			_set_frame(_sword_sprite, "swing_%s" % view, frame)
			_vfx_sprite.visible = true
			_vfx_sprite.rotation = _facing.angle()
			_set_frame(_vfx_sprite, "stab" if _form_id == &"jab" else "arc", frame)
		Pose.READY:
			var ready_name := "ready_%s" % view
			if _sword_sprite.animation != ready_name or not _sword_sprite.is_playing():
				_sword_sprite.play(ready_name)
			_hold -= delta
			if _hold <= 0.0:
				_pose = Pose.SHEATHING
				_sheathe_time = 0.0
		Pose.SHEATHING:
			_sheathe_time += delta
			var sheathe_frame := int(_sheathe_time * SHEATHE_FPS)
			if sheathe_frame >= 8:
				_pose = Pose.SHEATHED
			else:
				_set_frame(_sword_sprite, "sheathe_%s" % view, sheathe_frame)
		_:
			pass
	if _pose == Pose.SHEATHED:
		# follows the body's step cycle so the scabbard bobs with him
		_sword_sprite.z_index = -1 if view == "left" else 1
		_set_frame(_sword_sprite, "sheathed_%s" % view, _anim.frame % 4)


## A little spark where a blow lands.
func _hit_effect(at: Vector2) -> void:
	var spark := AnimatedSprite2D.new()
	spark.sprite_frames = _vfx_frames
	spark.scale = Vector2(0.55, 0.55)
	spark.z_index = 8
	_player.get_parent().add_child(spark)
	spark.global_position = at + Vector2(0, -6)
	spark.animation_finished.connect(spark.queue_free)
	spark.play("hit_down")


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not attacking:
		return
	if not _anim.animation.begins_with("attack_"):
		attacking = false
		return
	var frame := _anim.frame
	var active: Array = _form["active"]
	var is_active := frame >= int(active[0]) and frame <= int(active[1])
	if is_active:
		if not _lunged:
			_lunged = true
			if bool(_form.get("ranged", false)):
				_fire_arrow()
			else:
				_player.lunge(_facing * LUNGE_SPEED)
				if _form_id == &"slam":
					_flash_area()
		if not bool(_form.get("ranged", false)):
			_strike()
	if _anim.frame >= int(_form["frames"]) - 1 and not _anim.is_playing():
		attacking = false


func can_attack() -> bool:
	return not attacking and _cooldown <= 0.0


## Starts a swing along `facing` (the 8-way snapped facing). The cooldown is fitted by the form and swing speed.
func swing(facing: Vector2) -> bool:
	if not can_attack():
		return false
	_form_id = Run.form
	_form = RunData.FORMS[_form_id]
	_facing = facing.normalized()
	var speed := 1.0 + Run.stat(&"attack_speed")
	_cooldown = float(_form["cooldown"]) / speed
	attacking = true
	_lunged = false
	_hit.clear()
	_swing_dir = _view_of(_player.facing_name())
	_player.play_attack(String(_form["anim"]), int(_form["frames"]), float(_form["cooldown"]) * 0.95 / speed)
	return true


func cancel() -> void:
	attacking = false


## A dash may cut the recovery short once the last active frame has passed.
func can_cancel() -> bool:
	if not attacking:
		return true
	return _anim.frame > int((_form["active"] as Array)[1])


func trigger_cooldown(seconds: float) -> void:
	_cooldown = maxf(_cooldown, seconds)


func damage_for(target: Node) -> int:
	var amount := float(RunData.BASE_SWORD_DAMAGE) * float(_form.get("dmg", 1.0)) * (1.0 + Run.stat(&"damage"))
	if target is EnemyBase and ((target as EnemyBase).is_elite or target is BossBase):
		amount *= 1.0 + Run.stat(&"elite_dmg")
	return maxi(1, int(round(amount)))


## Is a point inside the area of the current swing?
func in_area(point: Vector2) -> bool:
	if bool(_form.get("ranged", false)):
		return false
	var origin := _player.global_position + Vector2(0.0, 2.0)
	var reach := float(_form["reach"]) * (1.0 + Run.stat(&"reach"))
	if _form_id == &"slam":
		return point.distance_to(origin + _facing * reach * 0.8) <= reach + ENEMY_RADIUS
	var to := point - origin
	if to.length() > reach + ENEMY_RADIUS:
		return false
	if to.length() < 4.0:
		return true
	return absf(_facing.angle_to(to)) <= deg_to_rad(float(_form["arc"]) * 0.5)


func _strike() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as EnemyBase
		if enemy == null or enemy._dead or not enemy.is_visible_in_tree():
			continue
		var id := enemy.get_instance_id()
		if _hit.has(id) or not in_area(enemy.global_position):
			continue
		_hit[id] = true
		var amount := damage_for(enemy)
		enemy.take_damage(amount, _player.global_position, float(_form["knock"]))
		var steal := Run.stat(&"lifesteal")
		if steal > 0.0:
			_player.heal_from_hit(int(ceil(float(amount) * steal)))
		hit_landed.emit(enemy)
		_hit_effect(enemy.global_position)
		GameManager.hit_stop(HIT_STOP)
		GameManager.shake_camera(1.6 if _form_id != &"slam" else 3.5, 0.12)


func _fire_arrow() -> void:
	var arrow := Arrow.new()
	arrow.dir = _facing
	arrow.damage = damage_for(null)
	arrow.knock = float(_form["knock"])
	arrow.blade = self
	_player.get_parent().add_child(arrow)
	arrow.global_position = _player.global_position + Vector2(0, -1) + _facing * 9.0
	Audio.play(preload("res://assets/sounds/tap.wav"), -6.0, 1.3)


## A faint flash over the exact area the swing hurts.
func _flash_area() -> void:
	var origin := _player.global_position + Vector2(0.0, 2.0) - global_position
	var reach := float(_form["reach"]) * (1.0 + Run.stat(&"reach"))
	var points := PackedVector2Array()
	if _form_id == &"slam":
		var center := origin + _facing * reach * 0.8
		for i in 24:
			points.append(center + Vector2.from_angle(TAU * float(i) / 24.0) * (reach + ENEMY_RADIUS * 0.5))
	else:
		var half := deg_to_rad(float(_form["arc"]) * 0.5)
		points.append(origin)
		for i in 13:
			points.append(origin + _facing.rotated(lerpf(-half, half, float(i) / 12.0)) * reach)
	_swish.polygon = points
	_swish.color = Color(1, 1, 1, 0.28)
	create_tween().tween_property(_swish, "color:a", 0.0, 0.16)


## An arrow loosed by the bow form: flies straight, stops at walls, hurts the first enemy it touches.
class Arrow extends Node2D:
	var dir: Vector2 = Vector2.RIGHT
	var damage: int = 10
	var knock: float = 90.0
	var blade: Blade
	var _travelled: float = 0.0

	func _ready() -> void:
		z_index = 5

	func _physics_process(delta: float) -> void:
		var step := dir * 320.0 * delta
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, 1)
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			queue_free()
			return
		global_position += step
		_travelled += step.length()
		if _travelled > 240.0:
			queue_free()
			return
		for node in get_tree().get_nodes_in_group("enemy"):
			var enemy := node as EnemyBase
			if enemy == null or enemy._dead or not enemy.is_visible_in_tree():
				continue
			if enemy.global_position.distance_to(global_position) <= 11.0:
				enemy.take_damage(damage, global_position - dir * 12.0, knock)
				if blade != null and is_instance_valid(blade):
					blade.hit_landed.emit(enemy)
				GameManager.hit_stop(0.03)
				queue_free()
				return
		queue_redraw()

	func _draw() -> void:
		var p := dir * 7.0
		draw_line(-p, p, Color(0.75, 0.6, 0.38), 1.6)
		draw_colored_polygon(PackedVector2Array([p + dir * 3.0, p + dir.orthogonal() * 1.6, p - dir.orthogonal() * 1.6]), Color(0.85, 0.88, 0.95))
		draw_line(-p, -p - dir * 3.0 + dir.orthogonal() * 1.8, Color(0.9, 0.9, 0.9), 1.0)
		draw_line(-p, -p - dir * 3.0 - dir.orthogonal() * 1.8, Color(0.9, 0.9, 0.9), 1.0)
