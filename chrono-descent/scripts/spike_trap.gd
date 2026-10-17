extends Area2D
## Floor spike trap. Cycles: HIDDEN -> WARNING (spikes start to rise, telegraph) -> ACTIVE
## (spikes up, hurts the player) -> LOWERING -> HIDDEN. Placed by the level director at "trap"
## spawn points. Each trap starts at a random point of the cycle so a room's traps don't pulse
## in unison. All timings are exported, so trap variants are just different scene values.

enum Phase { HIDDEN, WARNING, ACTIVE, LOWERING }

const PEAKS_DIR := "res://assets/sprites/dungeon_set/2D Pixel Dungeon Asset Pack/items and trap_animation/peaks/peaks_%d.png"
## The sheet's frames: 1 = spikes fully up, 2 = lowering, 3 = retracted (holes), 4 = rising.
const FRAME_FOR_PHASE := {Phase.HIDDEN: 3, Phase.WARNING: 4, Phase.ACTIVE: 1, Phase.LOWERING: 2}

@export var damage: int = 6
@export var knockback_force: float = 140.0
@export var hidden_time: float = 2.2
@export var warning_time: float = 0.55
@export var active_time: float = 0.7
@export var lowering_time: float = 0.2
## While the spikes are up, bodies standing on them are hit again at this interval. The default
## is longer than active_time, so a trap hits once per activation (the knockback also pushes
## the victim off the spikes).
@export var hit_interval: float = 1.0
@export var randomize_start: bool = true
## Seconds until the first warning. Used by SpikePattern to choreograph tiles (>= 0 overrides
## randomize_start).
@export var start_offset: float = -1.0

var phase: Phase = Phase.HIDDEN

var _textures: Dictionary = {}
var _phase_time: float = 0.0
var _hit_cooldown: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	for i in range(1, 5):
		_textures[i] = load(PEAKS_DIR % i)
	if start_offset >= 0.0:
		_phase_time = start_offset
	elif randomize_start:
		_phase_time = randf() * hidden_time
	_set_phase(Phase.HIDDEN, _phase_time)


func _physics_process(delta: float) -> void:
	_phase_time -= delta
	if phase == Phase.ACTIVE:
		_hit_cooldown -= delta
		if _hit_cooldown <= 0.0:
			_strike()
	if _phase_time <= 0.0:
		_set_phase(Phase.values()[(phase + 1) % Phase.size()])


func _set_phase(new_phase: Phase, time_left: float = -1.0) -> void:
	phase = new_phase
	sprite.texture = _textures.get(FRAME_FOR_PHASE[phase])
	match phase:
		Phase.HIDDEN:
			_phase_time = time_left if time_left >= 0.0 else hidden_time
		Phase.WARNING:
			_phase_time = warning_time
		Phase.ACTIVE:
			_phase_time = active_time
			_hit_cooldown = 0.0 # hit whoever is already standing here right away
		Phase.LOWERING:
			_phase_time = lowering_time


func _strike() -> void:
	_hit_cooldown = hit_interval
	for body in get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage, global_position, knockback_force)
