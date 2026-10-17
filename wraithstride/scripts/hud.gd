extends CanvasLayer
## HUD logic. Layout, colours and every fade/flash live in hud.tscn (AnimationPlayer).
## This script only feeds numbers into the widgets and triggers animations from Game signals.

const JobData = preload("res://scripts/job_data.gd")
const TIER_COLORS: Array[Color] = [
	Color(0.55, 0.65, 0.75), Color(0.45, 0.9, 1.0), Color(0.7, 0.6, 1.0), Color(1.0, 0.5, 1.0),
]

@onready var job_label: Label = $Root/TopLeft/JobLabel
@onready var hp_bar: ProgressBar = $Root/TopLeft/HpBar
@onready var posture_bar: ProgressBar = $Root/TopLeft/PostureBar
@onready var flow_bar: ProgressBar = $Root/TopLeft/FlowBar
@onready var depth_label: Label = $Root/TopRight/DepthLabel
@onready var timer_label: Label = $Root/TopRight/TimerLabel
@onready var jp_label: Label = $Root/TopRight/JpLabel
@onready var ability_1: Label = $Root/Bottom/Ability1
@onready var ability_2: Label = $Root/Bottom/Ability2
@onready var dash_label: Label = $Root/Bottom/DashLabel
@onready var cast_bar: ProgressBar = $Root/CastBar
@onready var prompt: Label = $Root/Prompt
@onready var banner: Label = $Root/Banner
@onready var anim: AnimationPlayer = $AnimationPlayer

var player: Node = null


func _ready() -> void:
	Game.hurt.connect(func(_a: float) -> void: anim.play("flash_damage"))
	Game.deflected.connect(func(perfect: bool) -> void:
		if perfect:
			anim.play("flash_deflect"))
	Game.message.connect(_show_banner)
	Game.buff_changed.connect(func(kind: StringName, active: bool) -> void:
		anim.play("%s_%s" % [kind, "on" if active else "off"]))
	Game.player_died.connect(func(_r: String) -> void: anim.play("flash_damage"))
	Game.level_cleared.connect(_on_cleared)


func _show_banner(text: String) -> void:
	banner.text = text
	anim.play("banner")


func _on_cleared(t: float) -> void:
	banner.text = "DUNGEON CLEARED   %s   deaths: %d" % [_fmt(t), Game.deaths]
	anim.play("banner_hold")


func _fmt(t: float) -> String:
	return "%02d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return
	var p := player
	var job: Dictionary = p.job
	if job.is_empty():
		return
	var id: StringName = p.job_id
	job_label.text = "%s  Lv%d  [%s]" % [job["name"], int(Game.job_level[id]), job["role"]]
	job_label.modulate = job["color"]
	hp_bar.max_value = p.max_hp
	hp_bar.value = p.hp
	posture_bar.max_value = p.max_posture
	posture_bar.value = p.posture
	flow_bar.value = p.flow
	flow_bar.modulate = TIER_COLORS[p.flow_tier()]
	depth_label.text = "Depth %dm / %dm" % [int(Game.depth), int(Game.depth_total)]
	timer_label.text = _fmt(Game.run_time)
	jp_label.text = "JP %d   deaths %d" % [int(Game.job_jp[id]), Game.deaths]
	ability_1.text = _ability_text("Q", job["abilities"][0], p.ability_cd[0])
	ability_2.text = _ability_text("E", job["abilities"][1], p.ability_cd[1])
	dash_label.text = "[Shift] Dash  %s" % ("ready" if p.dash_cd <= 0.0 else "%.1fs" % p.dash_cd)
	cast_bar.visible = p.is_casting()
	if cast_bar.visible:
		cast_bar.max_value = p.cast_total
		cast_bar.value = p.cast_time
	prompt.visible = p.near_crystal
	prompt.text = "[F]  Change Job"


func _ability_text(key: String, ab: Dictionary, cd: float) -> String:
	var status := "ready" if cd <= 0.0 else "%.1fs" % cd
	var ct := float(ab["ct"])
	var charge := "  (ct %.1fs)" % ct if ct > 0.0 else ""
	return "[%s] %s%s  %s" % [key, ab["name"], charge, status]
