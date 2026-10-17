extends Control
## Title screen: new run, guided tutorial, "?" rules reference, settings toggles.

@onready var _new_run: ActionButton = %NewRunButton
@onready var _tutorial: ActionButton = %TutorialButton
@onready var _rules: ActionButton = %RulesButton
@onready var _crt: ActionButton = %CrtButton
@onready var _sfx: ActionButton = %SfxButton
@onready var _music: ActionButton = %MusicButton
@onready var _quit: ActionButton = %QuitButton
@onready var _close: ActionButton = %CloseButton
@onready var _stats: Label = %StatsLabel
@onready var _how_panel: PanelContainer = %HowToPanel
@onready var _how_text: RichTextLabel = %Text
@onready var _anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	_how_text.text = Fmt.rich(_rules_text())
	# Phones: a fat scrollbar (finger drag also scrolls: the text lets touches through).
	var sc := _how_text.get_parent() as ScrollContainer
	if sc != null:
		sc.get_v_scroll_bar().custom_minimum_size.x = 26.0 if InteractiveControl.is_touch_ui() else 14.0
	_new_run.activated.connect(_on_new_run)
	_tutorial.activated.connect(_on_tutorial)
	_rules.activated.connect(func(_s): _anim.play(&"how_show"))
	_close.activated.connect(func(_s): _anim.play(&"how_hide"))
	_crt.activated.connect(_on_crt)
	_sfx.activated.connect(_on_sfx)
	_music.activated.connect(_on_music)
	_quit.activated.connect(func(_s): get_tree().quit())
	_quit.visible = not OS.has_feature("web")
	_refresh_toggles()
	var runs: int = int(MetaSave.get_value("stats", "runs", 0))
	var wins: int = int(MetaSave.get_value("stats", "wins", 0))
	var best: int = int(MetaSave.get_value("stats", "best_network", 0))
	_stats.text = "RUNS %d  |  WINS %d  |  BEST NETWORK %d" % [runs, wins, best]
	_new_run.set_tip("INITIATE NEW RUN", "A fresh Tailbytes of 52 Nodes, a Server with 10 Integrity and Ø%d Nullcoin. 8 Networks stand between you and the core." % (RunState.START_MONEY))
	_tutorial.set_tip("TUTORIAL", "A guide bot teaches every rule on a scripted run. Only the highlighted controls work. New here? Start with this.")
	_rules.set_tip("RULES", "The full written rules: the story, Nodes, Firewalls, Overclock, Subroutines, Daemons, the Black Market and more.")
	if not bool(MetaSave.get_value("tutorial", "done", false)):
		_tutorial.text = "TUTORIAL  (START HERE)"
	_anim.play(&"intro")
	PostFX.power_on()   # CRT switch-on at game start (does nothing when CRT is off)


func _on_new_run(_s: InteractiveControl) -> void:
	RunState.start_new_run()
	SceneManager.go(SceneManager.NETWORK_MAP)


func _on_tutorial(_s: InteractiveControl) -> void:
	RunState.start_new_run(true)
	SceneManager.go(SceneManager.SERVER)


func _on_crt(_s: InteractiveControl) -> void:
	PostFX.set_crt_enabled(not PostFX.is_crt_enabled())
	_refresh_toggles()


func _on_sfx(_s: InteractiveControl) -> void:
	AudioService.set_enabled(not AudioService.enabled)
	_refresh_toggles()


func _on_music(_s: InteractiveControl) -> void:
	AudioService.set_music_enabled(not AudioService.music_enabled)
	_refresh_toggles()


func _refresh_toggles() -> void:
	_crt.text = "CRT: %s" % ("ON" if PostFX.is_crt_enabled() else "OFF")
	_sfx.text = "SFX: %s" % ("ON" if AudioService.enabled else "OFF")
	_music.text = "MUSIC: %s" % ("ON" if AudioService.music_enabled else "OFF")


## The written rules. Subroutine numbers are read from SubroutineDB so they never go stale.
func _rules_text() -> String:
	var subs := ""
	for id in SubroutineDB.ORDER:
		var d: Dictionary = SubroutineDB.SUBS[id]
		subs += "   [color=#FF00FF]%s[/color]  (%s)  +%d Base Bytes, +%d Overclock;  each Firmware level: +%d Base, +%d Overclock\n" % [
			d.name, d.text, int(d.base), int(d.mult), int(d.lvl_base), int(d.lvl_mult)]
	var fb: Dictionary = SubroutineDB.SUBS["fragment"]
	subs += "   [color=#FF00FF]%s[/color]  (%s)  +%d Base Bytes\n" % [fb.name, fb.text, int(fb.base)]

	return """[color=#66FCF1][b]THE STORY[/b][/color]
You are an Operator breaking into Servers one by one. The password to each next Server is hidden in the Server's data, so you plant your [b]OROBOROS PROTOCOL[/b] inside it to [b]siphon bytes[/b]. There is a catch: the Protocol is a snake eating its own tail. It can siphon the Server dry, or it can [b]corrupt and destroy[/b] it. A Server that is online lets you siphon for longer; a destroyed Server gives you nothing, ever. You are not fighting the Server: you are [b]managing the damage your own Protocol causes[/b].

[color=#66FCF1][b]THE GOAL[/b][/color]
Clear 8 Networks of 3 Servers each. To clear a Server, siphon its [b]THRESHOLD[/b] in bytes. You lose if the Server's [b]Integrity[/b] reaches 0 (it crashes) or if you run out of Nodes in your [b]Tailbytes[/b] before reaching the threshold.

[color=#66FCF1][b]THE BYTE EQUATION[/b][/color]
Every turn you siphon [b]Base Bytes x Overclock[/b].
Base Bytes = Subroutine Base + the value of each Node you resolve (Siphons count double) + Daemon bonuses.
Overclock = 1 + the Overclock you earned this Server + Subroutine Overclock + Daemon bonuses.
Daemons apply left to right, so put the + effects before the x effects (drag Daemons to reorder them).

[color=#66FCF1][b]A TURN[/b][/color]
1. The Server deals you a room of [b]4 Nodes[/b] drawn from your Tailbytes.
2. You pick [b]exactly 3[/b] and the order to resolve them. The unpicked Node goes to your [b]Stash[/b] and is forced into the next room.
3. Press EXECUTE. Nodes resolve in order, then your bytes are counted.
There is no turn limit, but clearing a Server within 4 turns pays a FAST-CLEAR bonus in Nullcoin (Ø).
[b]EJECT[/b]: if you select nothing you may Eject. The whole room (Stash included) is discarded for the rest of this Server and a fresh room is dealt. It costs no turn but burns Nodes, and you cannot Eject twice in a row.

[color=#66FCF1][b]THE 4 KINDS OF NODES[/b][/color]
[color=#66FCF1]SIPHON[/color]  mines raw bytes: its value x2 as Base Bytes.
[color=#FF003C]GLITCH[/color]  your Protocol corrupting the Server: damages its Integrity by the Glitch's value.
[color=#FFB400]FIREWALL[/color]  a barrier; resolving it equips it (replacing the old one) and it blocks Glitch damage.
[color=#00FA9A]PATCH[/color]  repairs the Server's Integrity by its value (never above the maximum).
Hover a card (long-press on a phone) to read its full description. Cards can carry modifiers: E encrypted, Z zipped (+10 Base), H overclocked (+1 Overclock), $ gold (earns money).

[color=#FFB400][b]FIREWALLS[/b][/color]
Its value is its [b]Base Strength[/b]: Glitch damage = Glitch value - Strength (never below 0). Strength never drops. Its [b]Target Ceiling[/b] starts unlimited and drops to (Glitch value - 1) after each Glitch it holds back, so afterwards it can only block weaker Glitches. When the ceiling reaches 1 the Firewall breaks. Contain the big Glitches first! Use the FIREWALL button to switch it OFF and let Glitches hit in full.

[color=#FF003C][b]THE OVERCLOCK ENGINE[/b][/color]
Every instance of unblocked Integrity damage [b]overclocks the Server[/b]: +1 Overclock for the rest of the Server. Letting Glitches hurt it on purpose and repairing it with Patches is the heart of the game. Keep Integrity above 0!

[color=#FF00FF][b]SUBROUTINES (COMBOS)[/b][/color]
The 3 Nodes you resolve form a Subroutine that gives Base Bytes and Overclock:
""" + subs + """The [b]SUBROUTINES[/b] button in a Server shows their current values, including your Firmware Update levels.

[color=#FF00FF][b]DAEMONS[/b][/color]
Passive permanent upgrades (max 5 slots). Buy them in the Black Market, sell the ones you outgrow. Read each one: they define your build. Drag a Daemon onto another slot to reorder them.

[color=#FFD866][b]RUN STRUCTURE AND THE BLACK MARKET[/b][/color]
Each Network: a Proxy Server, a Mainframe (1.5x threshold) and a Sentinel Server (2x threshold, with a disruptive special rule). Clearing a Server pays money and opens the [b]Black Market[/b]: Daemons, Firmware Updates (level up a Subroutine), Executables (one-use tools in your 3 slots), Corruptions, and one permanent Root Access offer per Network. Rerolling costs money.

[color=#C5C6C7][b]KEYS[/b][/color]  Space/Enter: Execute   F: Eject   Esc: Clear selection / close   D: Tailbytes tracker   S: Subroutines"""
