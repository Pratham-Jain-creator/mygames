extends Control
## End of run: victory or defeat summary.

@onready var _result: Label = %ResultLabel
@onready var _reason: Label = %ReasonLabel
@onready var _stats: RichTextLabel = %StatsText
@onready var _new_run: ActionButton = %NewRunButton
@onready var _menu: ActionButton = %MenuButton
@onready var _anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	var won: bool = RunState.result == "win"
	_result.text = "CORE BREACHED" if won else "SERVER DESTROYED"
	_result.add_theme_color_override("font_color", Enums.COL_COOLANT if won else Enums.COL_ICE)
	_reason.text = RunState.result_reason
	_reason.visible = won or RunState.death_report.is_empty()
	var s := RunState.stats
	var daemon_names: Array = []
	for d in RunState.daemons:
		var def: Dictionary = DaemonDB.get_def(d.id)
		daemon_names.append("[color=#%s]%s[/color]" % [Enums.RARITY_COLORS[def.rarity].to_html(false), def.name])
	var lines: Array = []
	if not won and not RunState.death_report.is_empty():
		lines.append_array(_trace_log(RunState.death_report))
		lines.append("")
	lines.append_array([
		"[color=#66FCF1]NETWORK REACHED[/color]  %d / %d" % [mini(RunState.network, RunState.FINAL_NETWORK), RunState.FINAL_NETWORK],
		"[color=#66FCF1]SERVERS CLEARED[/color]  %d" % int(s.get("servers_cleared", 0)),
		"[color=#66FCF1]BEST TURN[/color]  %s" % Fmt.big(int(s.get("best_turn", 0))),
		"[color=#66FCF1]SERVER DAMAGE[/color]  %d" % int(s.get("damage_taken", 0)),
		"[color=#66FCF1]TAILBYTES SIZE[/color]  %d" % RunState.deck.size(),
		"[color=#FF00FF]DAEMONS[/color]  %s" % (", ".join(daemon_names) if not daemon_names.is_empty() else "none"),
	])
	_stats.text = "\n".join(lines)
	_new_run.activated.connect(func(_s):
		RunState.start_new_run()
		SceneManager.go(SceneManager.NETWORK_MAP))
	_menu.activated.connect(func(_s): SceneManager.go(SceneManager.MAIN_MENU))
	_anim.play(&"intro")
	if not won:
		PostFX.impact()


## The post-mortem: where, how close, what killed you, and what would have saved you.
func _trace_log(r: Dictionary) -> Array:
	var out: Array = []
	var where := "NETWORK %d // %s" % [int(r.network), String(Progression.KIND_NAMES[int(r.kind)])]
	if String(r.boss) != "":
		where += "  (%s)" % BossDB.name_of(String(r.boss)).to_upper()
	out.append("[color=#FF003C]TRACE LOG[/color]")
	out.append("[color=#FF003C]LOCATION[/color]  %s" % where)
	var quota := maxi(1, int(r.quota))
	var pct := clampi(int(100.0 * float(r.score) / float(quota)), 0, 100)
	var cells := pct / 5
	out.append("[color=#FF003C]PROGRESS[/color]  [%s%s] %d%%   %s / %s bytes, turn %d" % [
		"=".repeat(cells), "-".repeat(20 - cells), pct, Fmt.big(int(r.score)), Fmt.big(quota), int(r.turns)])
	var tip := ""
	if bool(r.exhausted):
		out.append("[color=#FF003C]CAUSE[/color]  The Tailbytes ran out %s bytes short of the Threshold." % Fmt.big(maxi(0, quota - int(r.score))))
		tip = "Every Eject and every Node you skip burns Tailbytes. Purge weak Nodes in the shop so your deck deals better."
	else:
		var h: Dictionary = r.hit
		if h.has("value"):
			var v := int(h.value)
			if bool(h.weapon_used):
				out.append("[color=#FF003C]CAUSE[/color]  Your Protocol ran a Glitch %d. It tore through the Firewall (Strength %d) and corrupted the Server for %d." % [v, int(h.strength), int(h.dmg)])
				tip = "The Firewall held, but not enough: it only cuts the corruption by its Strength. A stronger Firewall or an earlier Patch would have kept the Server alive."
			elif bool(h.weapon_present):
				out.append("[color=#FF003C]CAUSE[/color]  Your Protocol ran a Glitch %d, above the Firewall's Ceiling (%d), so the Server took the full %d." % [v, int(h.ceiling), v])
				tip = "A Firewall only blocks Glitches at or below its Ceiling, and the Ceiling falls with every hit. Save a fresh Firewall for the big Glitches."
			else:
				out.append("[color=#FF003C]CAUSE[/color]  Your Protocol ran a Glitch %d with no Firewall up. The Server took %d corruption." % [v, int(h.dmg)])
				tip = "Equip a Firewall before you resolve a Glitch (the order you click is the order they resolve)."
		elif h.is_empty():
			out.append("[color=#FF003C]CAUSE[/color]  The Server's Integrity hit 0 and it crashed.")
		elif h.has("source"):
			out.append("[color=#FF003C]CAUSE[/color]  %s for %d Integrity." % [_source_text(String(h.source)), int(h.dmg)])
			tip = "That corruption ignores the Firewall, so Integrity is the only buffer. Patches and healing Daemons matter here."
		if int(r.flees_left) > 0 and h.has("value"):
			tip = "You still had %d Eject%s left. Ejecting that room would have skipped the Glitch (it costs no turn)." % [int(r.flees_left), "" if int(r.flees_left) == 1 else "s"]
	if pct >= 75 and not bool(r.exhausted):
		out.append("[color=#FFB400]SO CLOSE[/color]  %d bytes from clearing it." % maxi(0, quota - int(r.score)))
	if tip != "":
		out.append("[color=#00FA9A]NEXT TIME[/color]  %s" % tip)
	return out


func _source_text(src: String) -> String:
	match src:
		"needle": return "The Needle spiked the Server when you Ejected"
		"leak": return "The Sentinel's drain bled the Server out"
		"blood_magic": return "Thermal Runaway corrupted the Server as its price"
	return "The Server took damage from %s" % src
