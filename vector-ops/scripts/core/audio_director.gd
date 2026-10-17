extends Node
## Autoload "AudioDirector": the looping background music (starts as soon as the
## game launches, keeps playing through menu, lobby, match and pause) and the
## countdown beeps (beep1 every second, beep2 when the round goes LIVE).
## Sound files live in res://assets/sounds; see Sfx.FILE_SOUNDS.

const MUSIC_FILE := "fps_main_screen_bg.mp3"
const MUSIC_MENU_DB := -8.0
const MUSIC_MATCH_DB := -17.0 # countdown / between rounds
const MUSIC_OFF_DB := -60.0 # live round: silent, so footsteps and gunfire stay readable

var _music: AudioStreamPlayer
var _last_count: int = -1
var _last_phase: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keep playing while the pause menu is open
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.stream = Sfx.file_stream(MUSIC_FILE, true) # looped copy
	_music.volume_db = MUSIC_MENU_DB
	add_child(_music)
	if _music.stream != null:
		_music.play()
		# safety net for stream types without a loop flag
		_music.finished.connect(_music.play)
	else:
		push_warning("AudioDirector: %s not found or not imported yet." % MUSIC_FILE)


func _process(delta: float) -> void:
	var phase: int = GameState.phase
	var in_match: bool = GameState.in_session and phase != GameState.Phase.LOBBY
	var target: float = MUSIC_MATCH_DB if in_match else MUSIC_MENU_DB
	if in_match and phase == GameState.Phase.LIVE:
		target = MUSIC_OFF_DB # no music while the round is actually being fought
	_music.volume_db = lerpf(_music.volume_db, target, clampf(delta * 3.0, 0.0, 1.0))

	if phase == GameState.Phase.COUNTDOWN:
		var n: int = maxi(1, int(ceil(GameState.countdown_left)))
		if n != _last_count:
			_last_count = n
			Sfx.play_ui(self, "beep1", -4.0)
	else:
		if phase == GameState.Phase.LIVE and _last_phase == GameState.Phase.COUNTDOWN:
			Sfx.play_ui(self, "beep2", -2.0)
		_last_count = -1
	_last_phase = phase
