extends Node
## Global one-shot sound player, registered as the autoload "Audio".
##
## Why this exists: when an enemy owns its AudioStreamPlayer and is queue_free()'d on death,
## the sound is cut off together with it (the killing blow was silent). Sounds played through
## this node are owned by the node instead, so they always finish, no matter what happened
## to whoever asked for them. A fixed pool also avoids creating a node per sound.
##
## Usage:
##     Audio.play_2d(stream, global_position, -6.0, 1.2)   # positional (world) sound
##     Audio.play(stream, -4.0)                            # non-positional (UI / player) sound

const POOL_SIZE_2D: int = 16
const POOL_SIZE_FLAT: int = 6

@export var max_distance_2d: float = 900.0

var _pool_2d: Array[AudioStreamPlayer2D] = []
var _pool_flat: Array[AudioStreamPlayer] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE_2D:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = max_distance_2d
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_SIZE_FLAT:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_flat.append(p)


## Plays a positional sound at a world position. pitch_variance adds a little random
## detune so repeated hits don't sound mechanical.
func play_2d(stream: AudioStream, world_position: Vector2, volume_db: float = 0.0, pitch: float = 1.0, pitch_variance: float = 0.06) -> void:
	if stream == null:
		return
	var p := _acquire_2d()
	p.stream = stream
	p.global_position = world_position
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch + randf_range(-pitch_variance, pitch_variance), 0.05)
	p.play()


## Plays a non-positional sound (player feedback, UI).
func play(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0, pitch_variance: float = 0.0) -> void:
	if stream == null:
		return
	var p := _acquire_flat()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch + randf_range(-pitch_variance, pitch_variance), 0.05)
	p.play()


## Number of sounds currently playing (handy for debugging and tests).
func playing_count() -> int:
	var n := 0
	for p in _pool_2d:
		if p.playing:
			n += 1
	for p in _pool_flat:
		if p.playing:
			n += 1
	return n


func _acquire_2d() -> AudioStreamPlayer2D:
	for p in _pool_2d:
		if not p.playing:
			return p
	return _pool_2d[0] # every voice busy: steal one


func _acquire_flat() -> AudioStreamPlayer:
	for p in _pool_flat:
		if not p.playing:
			return p
	return _pool_flat[0]
