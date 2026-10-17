class_name Sfx
extends RefCounted
## Procedural placeholder sounds (Task 8.2). No audio assets required.

const SOUND_DIR := "res://assets/sounds/"
const FILE_SOUNDS := {
	"beep1": "beep1.mp3", # countdown tick
	"beep2": "beep2.mp3", # countdown end / FIGHT
	# optional: drop files with these names into assets/sounds to replace the built-in motion sounds
	"step_walk": "step_walk.mp3",
	"step_run": "step_run.mp3",
	"slide": "slide.mp3",
	"jump": "jump.mp3",
	"land": "land.mp3",
}

static var _cache: Dictionary = {}


## Loads an audio file from assets/sounds; null if it is missing or not imported yet.
static func file_stream(file: String, looped: bool = false) -> AudioStream:
	var key := "file:" + file + (":loop" if looped else "")
	if _cache.has(key):
		return _cache[key]
	var path := SOUND_DIR + file
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
		if s != null and looped:
			s = s.duplicate() # keep the shared import untouched
			if s is AudioStreamMP3:
				(s as AudioStreamMP3).loop = true
			elif s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
	_cache[key] = s
	return s


static func stream(kind: String) -> AudioStream:
	if FILE_SOUNDS.has(kind):
		var fs := file_stream(FILE_SOUNDS[kind])
		if fs != null:
			return fs
	if _cache.has(kind):
		return _cache[kind]
	var s: AudioStreamWAV
	match kind:
		"shot": s = _make(260.0, 0.14, 26.0, 0.55, -900.0)
		"hit": s = _make(1500.0, 0.09, 30.0, 0.0, 0.0)
		"kill": s = _make(900.0, 0.24, 11.0, 0.0, 700.0)
		"hurt": s = _make(160.0, 0.22, 12.0, 0.35, -60.0)
		"block": s = _make(700.0, 0.12, 22.0, 0.3, 0.0)
		"warn": s = _make(520.0, 0.2, 8.0, 0.0, 0.0)
		"swing": s = _make(300.0, 0.18, 14.0, 0.7, 800.0)
		"boost": s = _make(120.0, 0.35, 6.0, 0.4, 500.0)
		"shift": s = _make(1200.0, 0.25, 12.0, 0.1, -900.0)
		"eject": s = _make(400.0, 0.6, 4.0, 0.2, -300.0)
		"head": s = _make(2200.0, 0.14, 16.0, 0.0, 600.0)
		"sbreak": s = _make(900.0, 0.4, 7.0, 0.5, -1400.0)
		"heart": s = _make(55.0, 0.2, 14.0, 0.0, -20.0)
		"hum": s = _make_loop()
		"boom": s = _make(75.0, 0.55, 6.0, 0.65, -40.0)
		"bolt": s = _make(140.0, 0.4, 8.0, 0.5, -90.0)
		"bunker": s = _make(180.0, 0.18, 14.0, 0.6, 0.0)
		"stealth": s = _make(700.0, 0.25, 9.0, 0.0, -450.0)
		"step_walk": s = _make(95.0, 0.10, 34.0, 0.30, -40.0) # soft heel thud
		"step_run": s = _make(135.0, 0.12, 26.0, 0.50, -70.0) # harder, sharper strike
		"slide": s = _make(320.0, 0.85, 3.2, 0.92, -150.0) # long scrape
		"jump": s = _make(170.0, 0.16, 15.0, 0.30, 280.0) # push-off
		"land": s = _make(65.0, 0.26, 13.0, 0.55, -25.0) # heavy impact
		"beep1": s = _make(880.0, 0.12, 14.0, 0.0, 0.0)
		"beep2": s = _make(1320.0, 0.35, 6.0, 0.0, 0.0)
		_: s = _make(440.0, 0.1, 20.0, 0.0, 0.0)
	_cache[kind] = s
	return s


static func _make(freq: float, dur: float, decay: float, noise: float, sweep: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * decay)
		phase += TAU * maxf(20.0, freq + sweep * t) / float(rate)
		var v := sin(phase) * (1.0 - noise) + (randf() * 2.0 - 1.0) * noise
		data.encode_s16(i * 2, int(clampf(v * env, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Exactly one second of 110 Hz + 165 Hz so it loops seamlessly.
static func _make_loop() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate * 2)
	for i in rate:
		var t := float(i) / float(rate)
		var v := sin(TAU * 110.0 * t) * 0.5 + sin(TAU * 165.0 * t) * 0.3 + sin(TAU * 220.0 * t) * 0.1
		data.encode_s16(i * 2, int(v * 14000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = rate
	return w


static func play_3d(ctx: Node, kind: String, pos: Vector3, db: float = 0.0, max_dist: float = 45.0, pitch: float = 1.0) -> void:
	var scene := ctx.get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(kind)
	p.volume_db = db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 8.0
	scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


static func play_ui(ctx: Node, kind: String, db: float = 0.0) -> void:
	var scene := ctx.get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream(kind)
	p.volume_db = db
	scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
