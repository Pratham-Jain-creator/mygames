extends Node
## Global game state (autoload "GameManager"): the player, permadeath, and the signals that tie the
## systems together. The Game scene owns the flow; this node is the shared mailbox.
##
## Death is permanent: when the player dies (or the dungeon shifts while they are outside a safe
## room) the HUD shows YOU DIED, then the player is revived back in the base with the whole run
## reset. Game listens for player_respawned to tear the dungeon down.

signal player_died
signal player_respawned
## Gauntlet (locked-door wave fight) progress for the HUD. active=false + cleared=true = won.
signal gauntlet_changed(wave: int, total_waves: int, active: bool, cleared: bool)
## A staircase was used (from the base or from an extraction room). Game decides where it leads.
signal descend_requested
## The stairs up (in a start room) were used.
signal ascend_requested
## Chronos was defeated on the final floor.
signal game_won

## Small pop-up message at the bottom of the screen ("+3 SLIME CORE", "THE CANTEEN IS EMPTY").
signal toast_requested(text: String, icon: Texture2D, color: Color)
## A station (the workbench, the stash) was used: Game opens its screen.
signal open_station_requested(source: Node)
## The memory echo was used: reveal the whole floor on the minimap.
signal reveal_map_requested
## The game is about to quit: Game saves what needs saving.
signal save_requested
## An enemy died (for kill-based effects and ash drops).
signal enemy_killed(enemy: Node)
## A line of text for a room's own challenge ("SURVIVE 0:42"); empty text hides it.
signal room_banner(text: String, color: Color)
## Something (the Shortcut Shaft, the Deserter's Chute) sends the player to another floor (0 = the base).
signal travel_requested(depth: int)

## Boss fights, for the HUD. boss_started opens the boss bar (title card, letterbox, vignette);
## boss_health_changed carries the SHARED health pool of everything the boss has split into;
## boss_announce flashes a line of text ("THE QUEEN SPLITS!"); boss_ended closes the bar.
signal boss_started(title: String, subtitle: String, color: Color)
signal boss_health_changed(current: int, maximum: int, fragments: int)
signal boss_announce(text: String)
signal boss_ended(defeated: bool)

## Seconds between dying and being moved back to the base.
const RESPAWN_DELAY: float = 2.0

## 0 = in the base, 1..10 = dungeon floor.
var current_depth: int = 0
## Seconds left on the current floor's timer (mirrored from the Level by Game, for the HUD).
var level_time_left: float = 0.0
var extracted_loot: int = 0

var player: CharacterBody2D
## The pop-up list rooms use to offer choices (owned by Game).
var choice_menu: ChoiceMenu
## The Chrono-Sanctuary stops the floor timer while the player is inside.
var timer_paused: bool = false
## Where the player is revived after dying (the base spawn point).
var hub_position: Vector2 = Vector2.ZERO

var _is_respawning: bool = false
var _hit_stop_active: bool = false
var _shake_tween: Tween


## Called by Game once the player has been placed in the base.
func register_player(new_player: CharacterBody2D, hub_spawn: Vector2) -> void:
	player = new_player
	hub_position = hub_spawn
	_is_respawning = false
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	if health and not health.died.is_connected(_on_player_died):
		health.died.connect(_on_player_died)


## Kills the player regardless of invincibility (e.g. caught outside a safe room when the
## dungeon shifts).
func kill_player() -> void:
	if not is_instance_valid(player):
		return
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.take_damage(health.max_health * 10)


## Starts a fresh run: loot and depth are lost with the death.
func reset_run() -> void:
	current_depth = 0
	level_time_left = 0.0
	extracted_loot = 0
	timer_paused = false


func _on_player_died() -> void:
	if _is_respawning or not is_instance_valid(player):
		return
	_is_respawning = true
	player_died.emit()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if is_instance_valid(player):
		player.respawn(hub_position)
	_is_respawning = false
	player_respawned.emit()


# ------------------------------------------------------------------ game feel

## Freezes the game for a few frames when a hit lands. Makes attacks feel heavy.
func hit_stop(duration: float = 0.045) -> void:
	if _hit_stop_active:
		return
	_hit_stop_active = true
	Engine.time_scale = 0.05
	# The timer ignores time_scale (4th argument), otherwise it would never finish.
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hit_stop_active = false


## Shakes the player's camera. strength is in pixels.
func shake_camera(strength: float = 3.0, duration: float = 0.2) -> void:
	if not is_instance_valid(player):
		return
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps := maxi(int(duration / 0.03), 2)
	for i in steps:
		var falloff := 1.0 - float(i) / float(steps)
		var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * falloff
		_shake_tween.tween_property(camera, "offset", jitter, duration / float(steps))
	_shake_tween.tween_property(camera, "offset", Vector2.ZERO, 0.03)
