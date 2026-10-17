extends CharacterBody2D

# Keyboard / gamepad speed (unchanged from before)
const SPEED = 450.0

# Mouse / touch tuning
const POINTER_MAX_SPEED = 1400.0   # fastest the rocket may chase the pointer
const POINTER_GAIN = 14.0          # how snappily it closes the gap to the target
const STOP_DISTANCE = 3.0          # close enough -> stop (avoids jitter)
const TOUCH_SENSITIVITY = 1.6      # finger sweep distance -> rocket distance
const MAX_TOUCH_LEAD = 220.0       # target may not run further ahead than this
const TURN_SPEED = 14.0            # how fast the rocket rotates to face its heading
const PLAY_AREA = Rect2(-540, -290, 1080, 580)  # keeps the target inside the walls

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

var target_position: Vector2
var pointer_active := false        # true while mouse/touch is steering
var look_dir := Vector2.ZERO       # smoothed direction of pointer movement


func _ready() -> void:
	target_position = global_position


func _input(event: InputEvent) -> void:
	# --- Mouse: the rocket goes wherever the cursor is ---
	# Touches are also turned into fake mouse events by Godot (device == -1);
	# ignore those so touching the screen never teleports the rocket.
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		target_position = _clamp_target(get_global_mouse_position())
		pointer_active = true
		_update_look_dir(event.relative)

	# --- Touch: sweeping a finger nudges the rocket, no teleporting ---
	elif event is InputEventScreenDrag and event.index == 0:
		var nudge: Vector2 = event.relative * TOUCH_SENSITIVITY
		var new_target := target_position + nudge
		# Don't let the target race far ahead of the rocket
		var lead := new_target - global_position
		if lead.length() > MAX_TOUCH_LEAD:
			new_target = global_position + lead.limit_length(MAX_TOUCH_LEAD)
		target_position = _clamp_target(new_target)
		pointer_active = true
		_update_look_dir(event.relative)


func _update_look_dir(relative: Vector2) -> void:
	# Direction of mouse/finger movement decides where the rocket faces.
	if relative.length() > 1.5:
		var dir := relative.normalized()
		look_dir = dir if look_dir == Vector2.ZERO else look_dir.lerp(dir, 0.35).normalized()


func _clamp_target(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, PLAY_AREA.position.x, PLAY_AREA.end.x),
		clampf(p.y, PLAY_AREA.position.y, PLAY_AREA.end.y))


func _physics_process(delta: float) -> void:
	var key_x := Input.get_axis("move_left", "move_right")
	var key_y := Input.get_axis("move_up", "move_down")

	if key_x != 0.0 or key_y != 0.0:
		# Keyboard / gamepad takes over (and wins until the mouse moves again)
		pointer_active = false
		target_position = global_position
		velocity = Vector2(key_x, key_y) * SPEED
		look_dir = velocity.normalized()
	elif pointer_active:
		var to_target := target_position - global_position
		if to_target.length() > STOP_DISTANCE:
			velocity = (to_target * POINTER_GAIN).limit_length(POINTER_MAX_SPEED)
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO

	# Rotate smoothly toward the heading. The sprite faces UP, hence + PI/2.
	if look_dir != Vector2.ZERO:
		rotation = lerp_angle(rotation, look_dir.angle() + PI / 2.0, clampf(TURN_SPEED * delta, 0.0, 1.0))

	move_and_slide()
