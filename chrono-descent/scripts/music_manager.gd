extends Node
## Background music, registered as the autoload "Music".
##
##   base room  -> "Time for Adventure"     (assets/music/time_for_adventure.mp3)
##   dungeon    -> "Dungeon"                (assets/music/dungeon.mp3)
##
## Game switches the track when the player enters the base or a floor. The two tracks crossfade, and
## each one loops forever: the stream is set to loop AND a track that ever reports "finished" is
## restarted, so the music cannot stop by accident.
## To add a track: put the file in assets/music, add it to TRACKS, then call Music.play(&"name").

const TRACKS: Dictionary = {
	&"base": preload("res://assets/music/time_for_adventure.mp3"),
	&"dungeon": preload("res://assets/music/dungeon.mp3"),
}
const FADE_TIME: float = 1.2
## Resting volume of a playing track.
const VOLUME_DB: float = -8.0
const SILENT_DB: float = -60.0
## The BOSS theme: drop a file called boss.mp3 into assets/music and it plays in boss fights. Without it the dungeon
## track plays faster and louder, so a boss fight still feels different.
const BOSS_FILE: String = "res://assets/music/boss.mp3"
const BOSS_FALLBACK_PITCH: float = 1.12
const BOSS_FALLBACK_BOOST_DB: float = 2.5

var current: StringName = &""

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps playing whatever pauses
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Player%d" % i
		player.volume_db = SILENT_DB
		player.finished.connect(_on_finished.bind(player))
		add_child(player)
		_players.append(player)
	for track in TRACKS.values():
		track.loop = true
	play(&"base")


## Fades to a track (does nothing if it is already the one playing). Names: base, dungeon, boss.
func play(track: StringName) -> void:
	if track == current:
		return
	var stream: AudioStream
	var pitch := 1.0
	var boost := 0.0
	if track == &"boss":
		if ResourceLoader.exists(BOSS_FILE):
			stream = load(BOSS_FILE) as AudioStream
			if stream != null and "loop" in stream:
				stream.set("loop", true)
		if stream == null:
			stream = TRACKS[&"dungeon"]
			pitch = BOSS_FALLBACK_PITCH
			boost = BOSS_FALLBACK_BOOST_DB
	elif TRACKS.has(track):
		stream = TRACKS[track]
	else:
		return
	current = track
	var old := _players[_active]
	_active = 1 - _active
	var incoming := _players[_active]
	incoming.stream = stream
	incoming.pitch_scale = pitch
	incoming.volume_db = SILENT_DB
	incoming.play()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(incoming, "volume_db", VOLUME_DB + boost, FADE_TIME)
	if old.playing:
		_tween.tween_property(old, "volume_db", SILENT_DB, FADE_TIME)
		_tween.chain().tween_callback(old.stop)


## A track ended although it should loop forever: start it again.
func _on_finished(player: AudioStreamPlayer) -> void:
	if player == _players[_active] and player.stream != null:
		player.play()
