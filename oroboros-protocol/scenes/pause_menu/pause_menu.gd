extends Control
## In-game settings overlay (works on every run screen): RESUME, CRT / SFX / MUSIC
## toggles, NEW GAME and ABANDON RUN. Instance it as a last child of a BaseScreen.
## All motion lives in the AnimationPlayer ("open" / "close"); this script plays names.

signal opened
signal closed

## Set by the owning screen: returns true when the menu may open right now.
var can_open := Callable()
## The guided tutorial hides NEW GAME (it would silently replace the tutorial run).
var tutorial_mode := false

var _open := false
var _armed: ActionButton = null
var _texts: Dictionary = {}     # ActionButton -> its normal label

@onready var _gear: ActionButton = %GearButton
@onready var _overlay: Control = %Overlay
@onready var _panel: PanelContainer = %Panel
@onready var _resume: ActionButton = %ResumeButton
@onready var _crt: ActionButton = %CrtButton
@onready var _sfx: ActionButton = %SfxButton
@onready var _music: ActionButton = %MusicButton
@onready var _new_game: ActionButton = %NewGameButton
@onready var _menu: ActionButton = %MenuButton
@onready var _anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	z_index = 50   # overlays always draw above raised (selected / hovered) Node cards
	_gear.activated.connect(func(_s): toggle())
	_resume.activated.connect(func(_s): close())
	_crt.activated.connect(_on_crt)
	_sfx.activated.connect(_on_sfx)
	_music.activated.connect(_on_music)
	_new_game.activated.connect(func(_s): _confirm(_new_game, _do_new_game))
	_menu.activated.connect(func(_s): _confirm(_menu, _do_menu))
	_gear.set_tip("SETTINGS [P]", "Resume, start a new game, CRT / SFX / music, or leave the run.")
	_resume.set_tip("RESUME", "Close this menu and keep playing. Esc works too.")
	_new_game.set_tip("NEW GAME", "Throw this run away and start a fresh one. Asks for a second click.")
	_menu.set_tip("MAIN MENU", "Leave this run and return to the title screen. Asks for a second click.")
	for b: ActionButton in [_new_game, _menu]:
		_texts[b] = b.text
	_refresh_toggles()


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	if can_open.is_valid() and not can_open.call():
		AudioService.play("deny")
		return
	_open = true
	_new_game.visible = not tutorial_mode
	_refresh_toggles()
	_disarm()
	_panel.pivot_offset = _panel.size * 0.5
	_anim.play(&"open")
	AudioService.play("click")
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_disarm()
	_anim.play(&"close")
	AudioService.play("click", 0.85)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("clear_selection") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
	elif not _open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		open()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- toggles
func _on_crt(_s: InteractiveControl) -> void:
	PostFX.set_crt_enabled(not PostFX.is_crt_enabled())
	_refresh_toggles()


func _on_sfx(_s: InteractiveControl) -> void:
	AudioService.set_enabled(not AudioService.enabled)
	_refresh_toggles()
	AudioService.play("click")


func _on_music(_s: InteractiveControl) -> void:
	AudioService.set_music_enabled(not AudioService.music_enabled)
	_refresh_toggles()


func _refresh_toggles() -> void:
	_crt.text = "CRT: %s" % ("ON" if PostFX.is_crt_enabled() else "OFF")
	_sfx.text = "SFX: %s" % ("ON" if AudioService.enabled else "OFF")
	_music.text = "MUSIC: %s" % ("ON" if AudioService.music_enabled else "OFF")


# ------------------------------------------------------- two-click actions
func _confirm(btn: ActionButton, action: Callable) -> void:
	if _armed == btn:
		_disarm()
		action.call()
		return
	_disarm()
	_armed = btn
	btn.text = "CLICK AGAIN TO CONFIRM"
	get_tree().create_timer(3.0).timeout.connect(func():
		if _armed == btn:
			_disarm())


func _disarm() -> void:
	if _armed != null and is_instance_valid(_armed):
		_armed.text = _texts.get(_armed, _armed.text)
	_armed = null


func _do_new_game() -> void:
	_open = false
	RunState.start_new_run()
	SceneManager.go(SceneManager.NETWORK_MAP)


func _do_menu() -> void:
	_open = false
	RunState.tutorial = false
	RunState.active = false
	SceneManager.go(SceneManager.MAIN_MENU)
