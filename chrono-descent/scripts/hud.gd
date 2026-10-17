extends CanvasLayer
## Player HUD: health bar, damage flash, death overlay, minimap, interact prompt, gauntlet banner,
## quit button (fullscreen) and a hold-to-quit that works on keyboard and controller.
##
## Entry points used by the level generator:
##   initialize(health_component)     - bind the health bar (and interaction prompt) to the player
##   setup_minimap(rooms, player)     - start tracking the dungeon on the minimap

const OVERLAY_FADE_IN: float = 0.6
const OVERLAY_FADE_OUT: float = 0.5
const DAMAGE_FLASH_TIME: float = 0.3
## Hold the "exit" action (Esc / controller Start) this long to quit.
const QUIT_HOLD_TIME: float = 1.0
const BANNER_CLEARED_TIME: float = 2.5
const BANNER_ACTIVE_COLOR := Color(1.0, 0.3, 0.25)
const BANNER_CLEARED_COLOR := Color(0.45, 1.0, 0.5)
const BOSS_BAR_SCENE: PackedScene = preload("res://scenes/ui/boss_bar.tscn")

@onready var health_bar: PixelBar = $Root/Panel/HealthBar
@onready var health_label: Label = $Root/Panel/HealthBar/HealthLabel
@onready var damage_flash: ColorRect = $DamageFlash
@onready var death_overlay: ColorRect = $DeathOverlay
@onready var quit_button: Button = $Root/QuitButton
@onready var room_count_label: Label = $Root/RoomCount
@onready var map_hint: Label = $Root/MapHint
@onready var interact_prompt: Label = $Root/InteractPrompt
@onready var gauntlet_banner: Label = $Root/GauntletBanner
@onready var hold_quit_label: Label = $Root/HoldQuit
@onready var floor_label: Label = $Root/FloorLabel
@onready var timer_label: Label = $Root/TimerLabel
@onready var title_card: Label = $Root/TitleCard
@onready var title_sub: Label = $Root/TitleSub
@onready var run_hud = $Root/RunHud
@onready var toasts: VBoxContainer = $Root/Toasts
@onready var armor_label: Label = $Root/ArmorLabel
# Untyped on purpose: Minimap is a plain script on a Control, so its members are looked up dynamically.
@onready var minimap = $Root/Minimap

var _last_health: int = 0
var _overlay_tween: Tween
var _banner_tween: Tween
var _interact_target: Node2D
var _quit_hold: float = 0.0
var _dungeon_ui: bool = false
var _title_tween: Tween
## The boss bar + cinematic overlay (letterbox, vignette), shown during boss fights. Untyped on purpose: its
## functions live in its own script (scripts/ui/boss_bar.gd), not on Control.
var boss_bar
## Seconds left at which the timer turns red and pulses.
const TIMER_WARNING: float = 60.0


func _ready() -> void:
	quit_button.pressed.connect(_on_quit_pressed)
	minimap.discovery_changed.connect(_on_discovery_changed)
	GameManager.player_died.connect(_on_player_died)
	GameManager.player_respawned.connect(_on_player_respawned)
	GameManager.gauntlet_changed.connect(_on_gauntlet_changed)
	GameManager.room_banner.connect(_on_room_banner)
	boss_bar = BOSS_BAR_SCENE.instantiate()
	add_child(boss_bar)
	GameManager.boss_started.connect(_on_boss_started)
	GameManager.boss_health_changed.connect(boss_bar.set_health)
	GameManager.boss_announce.connect(boss_bar.announce)
	GameManager.boss_ended.connect(boss_bar.hide_boss)
	GameManager.toast_requested.connect(func(text: String, icon: Texture2D, color: Color) -> void: toasts.push(text, icon, color))
	InputHints.device_changed.connect(func(_pad: bool) -> void: _refresh_hints())
	_refresh_quit_button()
	_refresh_hints()


func _process(delta: float) -> void:
	_refresh_quit_button() # cheap poll: also catches F11 / Alt+Enter fullscreen toggles
	_update_hold_to_quit(delta)
	_update_interact_prompt()
	_update_level_timer()


# ------------------------------------------------------------------ public API

func initialize(health: HealthComponent) -> void:
	health_bar.max_value = health.max_health
	health_bar.value = health.current_health
	health_bar.settle()
	_last_health = health.current_health
	_set_health_label(health.current_health, health.max_health)
	if not health.health_changed.is_connected(_on_health_changed):
		health.health_changed.connect(_on_health_changed)
	# The player is the health component's parent: listen to what it can interact with.
	var owner_node := health.get_parent()
	if owner_node and owner_node.has_signal("interactable_changed"):
		owner_node.interactable_changed.connect(func(target: Node2D) -> void: _interact_target = target)
	run_hud.bind(owner_node)
	if not Run.changed.is_connected(_update_armor):
		Run.changed.connect(_update_armor)
	_update_armor()


func setup_minimap(rooms: Array, tracked: Node2D) -> void:
	minimap.setup(rooms, tracked)


func clear_minimap() -> void:
	minimap.clear()


## The floor number, timer and minimap only make sense inside the dungeon, not in the base.
func set_dungeon_ui(shown: bool) -> void:
	_dungeon_ui = shown
	for control in [floor_label, timer_label, minimap, map_hint, room_count_label]:
		control.visible = shown


## Big centred text for a few seconds ("FLOOR 3", "THE DUNGEON SHIFTS").
func show_title(text: String, subtitle: String = "", seconds: float = 2.5) -> void:
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	title_card.text = text
	title_sub.text = subtitle
	title_card.visible = true
	title_sub.visible = subtitle != ""
	_title_tween = create_tween().set_parallel(true)
	_title_tween.tween_property(title_card, "modulate:a", 1.0, 0.4)
	_title_tween.tween_property(title_sub, "modulate:a", 1.0, 0.4)
	_title_tween.chain().tween_interval(seconds)
	_title_tween.chain().tween_property(title_card, "modulate:a", 0.0, 0.8)
	_title_tween.parallel().tween_property(title_sub, "modulate:a", 0.0, 0.8)
	_title_tween.chain().tween_callback(func() -> void:
		title_card.visible = false
		title_sub.visible = false)


## Countdown for the current floor. Turns red and pulses in the last minute.
func _update_level_timer() -> void:
	if not _dungeon_ui:
		return
	var seconds := maxf(GameManager.level_time_left, 0.0)
	floor_label.text = "FLOOR %d" % GameManager.current_depth
	timer_label.text = "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
	if seconds <= TIMER_WARNING:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.25 + 0.25 * pulse, 0.2))
	else:
		timer_label.add_theme_color_override("font_color", Color.WHITE)


# ------------------------------------------------------------------ health

func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = clampi(current, 0, maximum)
	_set_health_label(current, maximum)
	if current < _last_health:
		damage_flash.modulate.a = 1.0
		create_tween().tween_property(damage_flash, "modulate:a", 0.0, DAMAGE_FLASH_TIME)
	_last_health = current


func _set_health_label(current: int, maximum: int) -> void:
	health_label.text = "%d / %d" % [maxi(current, 0), maximum]


func _update_armor() -> void:
	var info: Dictionary = RunData.ARMOR[Run.armor]
	armor_label.text = "%s  |  DAMAGE TAKEN %d%%" % [String(info["name"]).to_upper(), int(round(Run.damage_taken_mult() * 100.0))]


# ------------------------------------------------------------------ death / respawn overlay

func _on_player_died() -> void:
	_fade_overlay(1.0, OVERLAY_FADE_IN)


func _on_player_respawned() -> void:
	_fade_overlay(0.0, OVERLAY_FADE_OUT)


func _fade_overlay(target_alpha: float, duration: float) -> void:
	if _overlay_tween and _overlay_tween.is_valid():
		_overlay_tween.kill()
	death_overlay.visible = true
	_overlay_tween = create_tween()
	_overlay_tween.tween_property(death_overlay, "modulate:a", target_alpha, duration)
	if target_alpha <= 0.0:
		_overlay_tween.tween_callback(func() -> void: death_overlay.visible = false)


# ------------------------------------------------------------------ interact prompt

## Floats a "[E] OPEN CHEST" prompt over whatever the player can use. The key name follows the
## device in use, so a controller player sees SQUARE.
func _update_interact_prompt() -> void:
	var usable: bool = is_instance_valid(_interact_target) \
			and _interact_target.has_method("can_interact") and _interact_target.can_interact()
	interact_prompt.visible = usable
	if not usable:
		return
	interact_prompt.text = "%s  %s" % [InputHints.get_action_hint(&"interact"), _interact_target.get_prompt()]
	interact_prompt.reset_size()
	var screen_pos := get_viewport().get_canvas_transform() * (_interact_target.global_position + Vector2(0, -26))
	interact_prompt.position = screen_pos - interact_prompt.size * 0.5


# ------------------------------------------------------------------ boss fights

## The boss makes her entrance: the bar and the cinematic bars come in, and the name is shown big.
func _on_boss_started(title: String, subtitle: String, color: Color) -> void:
	gauntlet_banner.visible = false
	boss_bar.show_boss(title, subtitle, color)
	show_title(title, subtitle, 1.4)


# ------------------------------------------------------------------ gauntlet banner

## A line of text under the timer for a room's own challenge ("SURVIVE 0:42"). Empty text hides it.
func _on_room_banner(text: String, color: Color) -> void:
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	gauntlet_banner.visible = text != ""
	gauntlet_banner.text = text
	gauntlet_banner.add_theme_color_override("font_color", color)

func _on_gauntlet_changed(wave: int, total_waves: int, active: bool, cleared: bool) -> void:
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	if active:
		gauntlet_banner.text = "GAUNTLET  WAVE %d/%d" % [wave, total_waves]
		gauntlet_banner.add_theme_color_override("font_color", BANNER_ACTIVE_COLOR)
		gauntlet_banner.visible = true
	elif cleared:
		gauntlet_banner.text = "ROOM CLEARED!"
		gauntlet_banner.add_theme_color_override("font_color", BANNER_CLEARED_COLOR)
		gauntlet_banner.visible = true
		_banner_tween = create_tween()
		_banner_tween.tween_interval(BANNER_CLEARED_TIME)
		_banner_tween.tween_callback(func() -> void: gauntlet_banner.visible = false)
	else:
		gauntlet_banner.visible = false


# ------------------------------------------------------------------ quitting (mouse + keyboard + controller)

func _refresh_quit_button() -> void:
	var mode := DisplayServer.window_get_mode()
	quit_button.visible = mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Hold the "exit" action (Esc / controller Start) for a moment to quit, so a stray press
## can't close the game.
func _update_hold_to_quit(delta: float) -> void:
	if Input.is_action_pressed(&"exit"):
		_quit_hold += delta
	else:
		_quit_hold = maxf(0.0, _quit_hold - delta * 2.0)
	var progress := clampf(_quit_hold / QUIT_HOLD_TIME, 0.0, 1.0)
	hold_quit_label.visible = progress > 0.08
	if hold_quit_label.visible:
		var filled := int(progress * 10.0)
		hold_quit_label.text = "HOLD %s TO QUIT  %s%s" % [InputHints.get_action_hint(&"exit"), "=".repeat(filled), "-".repeat(10 - filled)]
	if progress >= 1.0:
		GameManager.save_requested.emit()
		get_tree().quit()


func _on_quit_pressed() -> void:
	GameManager.save_requested.emit()
	get_tree().quit()


# ------------------------------------------------------------------ minimap

func _on_discovery_changed(discovered: int, total: int) -> void:
	room_count_label.text = "ROOMS %d/%d" % [discovered, total]


func _refresh_hints() -> void:
	map_hint.text = "%s: ZOOM" % InputHints.get_action_hint(&"toggle_map")
