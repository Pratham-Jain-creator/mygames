extends Control
## Root of scenes/ui/hud.tscn - the in-match HUD. The layout is all in the scene;
## this script only feeds it numbers: score/timer, announcements, the dual-layer
## Flux bar, the crosshair spread, the two hand cards and the post-round report.
## (The radar and the hand cards have their own scripts.)

const WARN_PERIOD := 0.7

@onready var overlay: HudOverlay = %Overlay
@onready var _round: Label = %RoundLabel
@onready var _alpha_score: Label = %AlphaScore
@onready var _bravo_score: Label = %BravoScore
@onready var _alpha_alive: Label = %AlphaAlive
@onready var _bravo_alive: Label = %BravoAlive
@onready var _timer: Label = %TimerLabel
@onready var _announce: Label = %CenterAnnouncement
@onready var _eject: Label = %EjectBanner
@onready var _count: Label = %CountdownLabel
@onready var _count_hint: Label = %CountdownHint
@onready var _ping_hint: Label = %PingHint
@onready var _death: Label = %DeathLabel
@onready var _debuff: Label = %DebuffLabel
@onready var _stealth_label: Label = %StealthLabel
@onready var _stealth_tint: ColorRect = %StealthTint
@onready var _report_panel: PanelContainer = %ReportPanel
@onready var _report: Label = %ReportLabel
@onready var _crosshair: Control = %Crosshair
@onready var _tick_top: ColorRect = %TickTop
@onready var _tick_bottom: ColorRect = %TickBottom
@onready var _tick_left: ColorRect = %TickLeft
@onready var _tick_right: ColorRect = %TickRight
@onready var _flux_now: Label = %FluxCurrentLabel
@onready var _active_stat: Label = %ActiveStat
@onready var _fractured_stat: Label = %FracturedStat
@onready var _active_bar: ProgressBar = %ActiveBar
@onready var _fractured_bar: ProgressBar = %FracturedBar
@onready var _right_card: Control = %RightHandCard
@onready var _left_card: Control = %LeftHandCard

var _death_text: String = ""
var _warn_t: float = 0.0
var _gap: float = 4.0
var _active_shown: float = -1.0
var _clock: float = 0.0


func _ready() -> void:
	GameState.report_received.connect(func(t: String) -> void: _report.text = t)
	GameState.local_hurt.connect(func(p: Vector3, b: bool) -> void: overlay.add_indicator(p, b))
	GameState.local_hit.connect(func(k: bool, _b: bool, z: String) -> void: overlay.show_hit(k, z))
	GameState.local_killed.connect(func(k: String, s: String, d: float) -> void:
		_death_text = "ELIMINATED BY %s\nwith %s  (%d m)" % [k.to_upper(), s, int(d)])


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_report_panel.visible = false
		return
	_clock += delta
	var phase: int = GameState.phase

	# score strip
	var secs: int = int(ceil(GameState.time_left))
	_round.text = "ROUND %d" % GameState.round_number
	_alpha_score.text = "ALPHA  %d" % GameState.score_a
	_bravo_score.text = "%d  BRAVO" % GameState.score_b
	_timer.text = "%d:%02d" % [int(secs / 60.0), secs % 60]
	_timer.modulate = Color(1.0, 0.45, 0.45) if (phase == GameState.Phase.LIVE and secs <= 10) else Color.WHITE
	_update_alive()

	_announce.text = GameState.announce
	_report_panel.visible = (phase == GameState.Phase.ROUND_END or phase == GameState.Phase.MATCH_END) and _report.text != ""
	if phase == GameState.Phase.COUNTDOWN:
		_report.text = ""

	var lp: Node = GameState.get_local_player()
	var ejected: bool = lp != null and lp.flux.ejected
	_eject.visible = ejected
	var counting: bool = phase == GameState.Phase.COUNTDOWN
	_count.visible = counting
	_count_hint.visible = counting
	_count_hint.text = "%s / %s: change what's in your left / right hand" % [ControlHints.key(&"rotate_left"), ControlHints.key(&"rotate_right")]
	_eject.text = "EJECTED - spectating (%s: next target)" % ControlHints.key(&"spectate_next")
	_ping_hint.text = "%s: SPECTATE" % ControlHints.key(&"spectate_next").to_upper()
	if counting:
		_count.text = str(maxi(1, int(ceil(GameState.countdown_left))))
		_death_text = ""
	_death.visible = ejected and _death_text != ""
	_death.text = _death_text

	if lp == null:
		_stealth_label.visible = false
		_stealth_tint.visible = false
		_crosshair.visible = false
		_debuff.text = ""
		_active_bar.value = 0
		_fractured_bar.value = 0
		_flux_now.text = ""
		_active_stat.text = ""
		_fractured_stat.text = ""
		return
	var f: FluxComponent = lp.flux

	_update_crosshair(lp, delta)

	# stealth indicator: label above the Flux bar + a faint tint over the screen while cloaked
	var cloak: int = 0 if f.ejected else f.stealth
	_stealth_label.visible = cloak != 0
	_stealth_tint.visible = cloak == 2
	if cloak == 2:
		_stealth_label.text = "MIRAGE ACTIVE - you are cloaked"
		_stealth_label.add_theme_color_override("font_color", Color(0.85, 0.6, 1.0))
	elif cloak == 1:
		_stealth_label.text = "GHOST ACTIVE - hidden from radar"
		_stealth_label.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))

	# debuffs
	var dbs: PackedStringArray = []
	if f.slowed:
		dbs.append("LEG HIT - SLOWED")
	if f.arm0_off:
		dbs.append("RIGHT ARM DISABLED")
	if f.arm1_off:
		dbs.append("LEFT ARM DISABLED")
	if f.shield_locked:
		dbs.append("AEGIS BROKEN")
	_debuff.text = "   |   ".join(dbs)

	# dual-layer Flux bar: cyan Active over a dark "capacity" bar whose right end
	# is eaten by Fractured Flux
	if _active_shown < 0.0:
		_active_shown = f.active_flux
	_active_shown = lerpf(_active_shown, f.active_flux, clampf(delta * 14.0, 0.0, 1.0))
	_active_bar.max_value = f.max_flux
	_fractured_bar.max_value = f.max_flux
	_active_bar.value = _active_shown
	_fractured_bar.value = f.max_flux - f.fractured_flux
	_flux_now.text = " %d / %d" % [int(f.total_flux()), int(f.max_flux)]
	_active_stat.text = "ACTIVE %d" % int(f.active_flux)
	_fractured_stat.text = "FRACTURED %d" % int(f.fractured_flux)

	# low-Flux warning (pulsing number + beep)
	var low: bool = not f.ejected and (f.total_flux() < f.max_flux * 0.3 or (f.active_flux < 8.0 and phase == GameState.Phase.LIVE))
	_flux_now.modulate = Color(1.0, 0.4, 0.4).lerp(Color.WHITE, 0.5 + 0.5 * sin(_clock * 10.0)) if low else Color.WHITE
	_warn_t -= delta
	if low and _warn_t <= 0.0:
		_warn_t = WARN_PERIOD
		Sfx.play_ui(self, "warn", -6.0)

	# hand cards
	_right_card.refresh(lp, counting)
	_left_card.refresh(lp, counting)


func _update_alive() -> void:
	var up: Array = [0, 0]
	var all: Array = [0, 0]
	for p in get_tree().get_nodes_in_group("players"):
		var t: int = clampi(int(p.team), 0, 1)
		all[t] += 1
		if not p.flux.ejected:
			up[t] += 1
	_alpha_alive.text = "%d/%d" % [up[0], all[0]]
	_bravo_alive.text = "%d/%d" % [up[1], all[1]]


## Crosshair ticks spread with the weapon's accuracy cone; hidden while scoped
## (the overlay draws the scope instead).
func _update_crosshair(lp: Node, delta: float) -> void:
	var show_it: bool = not lp.flux.ejected and not lp.scoped
	_crosshair.visible = show_it
	if not show_it:
		return
	_gap = lerpf(_gap, 4.0 + float(lp.spread_deg) * 7.0, clampf(delta * 18.0, 0.0, 1.0))
	var tl: float = 5.0
	_tick_top.offset_top = -(_gap + tl)
	_tick_top.offset_bottom = -_gap
	_tick_bottom.offset_top = _gap
	_tick_bottom.offset_bottom = _gap + tl
	_tick_left.offset_left = -(_gap + tl)
	_tick_left.offset_right = -_gap
	_tick_right.offset_left = _gap
	_tick_right.offset_right = _gap + tl
