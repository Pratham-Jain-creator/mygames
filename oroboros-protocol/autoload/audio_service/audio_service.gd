extends Node
## Autoload: procedural placeholder SFX (no audio assets needed).
## Usage: AudioService.play("click", pitch_scale)

const MIX_RATE := 22050
const POOL_SIZE := 8

const MUSIC_PATH := "res://assets/music/grand_project-code-unknown_medium.mp3"
const MUSIC_DB := -12.0

var enabled := true
var music_enabled := true
var _music: AudioStreamPlayer
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	enabled = bool(MetaSave.get_value("settings", "sfx", true))
	music_enabled = bool(MetaSave.get_value("settings", "music", true))
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	#                       name        dur   freq  noise decay
	_streams["click"] = _make(0.045, 1500.0, 0.15, 60.0)
	_streams["select"] = _make(0.07, 900.0, 0.1, 40.0)
	_streams["deselect"] = _make(0.06, 600.0, 0.1, 45.0)
	_streams["thunk"] = _make(0.14, 140.0, 0.25, 22.0)
	_streams["hit"] = _make(0.22, 90.0, 0.85, 14.0)
	_streams["heal"] = _make(0.18, 1100.0, 0.0, 12.0)
	_streams["tick"] = _make(0.03, 2200.0, 0.2, 90.0)
	_streams["deny"] = _make(0.12, 220.0, 0.35, 25.0)
	_streams["buy"] = _make(0.16, 1300.0, 0.05, 14.0)
	_streams["break"] = _make(0.3, 300.0, 0.9, 10.0)
	_streams["slam"] = _make(0.2, 70.0, 0.5, 12.0)
	_start_music()


## Background music: one looping stream on an autoload, so it never restarts
## or stops when scenes change.
func _start_music() -> void:
	var stream: AudioStreamMP3 = null
	if ResourceLoader.exists(MUSIC_PATH):
		stream = load(MUSIC_PATH) as AudioStreamMP3
	if stream == null and FileAccess.file_exists(MUSIC_PATH):
		stream = AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes(MUSIC_PATH)
	if stream == null:
		push_warning("Music not found: " + MUSIC_PATH)
		return
	stream.loop = true
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = MUSIC_DB
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_music.finished.connect(_music.play)  # safety net if loop is ignored
	_music.stream_paused = not music_enabled
	_music.play()


func set_music_enabled(v: bool) -> void:
	music_enabled = v
	MetaSave.set_value("settings", "music", v)
	if _music != null:
		_music.stream_paused = not v


func set_enabled(v: bool) -> void:
	enabled = v
	MetaSave.set_value("settings", "sfx", v)


func play(sfx: String, pitch := 1.0, vol_db := 0.0) -> void:
	if not enabled or not _streams.has(sfx):
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _streams[sfx]
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.volume_db = -8.0 + vol_db
	p.play()


func _make(duration: float, freq: float, noise: float, decay: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * decay)
		var tone := sin(TAU * freq * t)
		var s := (tone * (1.0 - noise) + (randf() * 2.0 - 1.0) * noise) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w
