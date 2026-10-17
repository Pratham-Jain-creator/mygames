extends RefCounted
## (No class_name on purpose: users preload this script, so a fresh checkout works
##  without the editor having to rebuild the global class cache first.)
## Pure data of the guided tutorial: the fixed card order and every bot step.
## The TutorialDirector (scenes/tutorial) plays these; nothing here touches the UI.
##
## Step keys:
##   text    bbcode shown by the bot. {score} / {quota} / {health} are filled at runtime.
##   expect  what the player must do to continue:
##             next        press NEXT (or Space)
##             card        select the node given in `card` ([type, value])
##             execute / skip / weapon (the FIREWALL toggle) / deck_open / deck_close / subs_open / subs_close
##             turn_done   (bot hides) wait for the turn animation to finish
##   target  UI element to spotlight (see ServerScreen.tut_target) or "card"
##   lit     (card steps) UI element kept bright as well, e.g. "room" so the player sees ALL the Nodes they choose among
##   card    [NodeType, value] of the card to spotlight / require
##   dock    "top" | "bottom" bot position (auto from the spotlight otherwise)
##   do      action when the step starts: deal | level_skirmish
##   hide    hide the bot panel during this step

const QUOTA := 600

const C_DATA := "[color=#66FCF1]"
const C_ICE := "[color=#FF003C]"
const C_BREACH := "[color=#FFB400]"
const C_COOL := "[color=#00FA9A]"
const C_DAEMON := "[color=#FF00FF]"
const C_MONEY := "[color=#FFD866]"
const C_END := "[/color]"


## Draw order of the whole tutorial (spec[0] is drawn first):
##   Turn 1 : Siphon 8, Glitch 6, Firewall 4, Patch 5   (the Patch becomes the Stash)
##   Turn 2 : Glitch 12/13/14 (+ Stash Patch)           -> the player EJECTS this room
##   Turn 3 : Glitch 4, Patch 7, Siphon 12, Siphon 5    (Firewall OFF: damage is power)
static func deck_order() -> Array:
	var D := Enums.NodeType.DATA
	var I := Enums.NodeType.ICE
	var B := Enums.NodeType.BREACH
	var C := Enums.NodeType.COOLANT
	return [
		[D, 8], [I, 6], [B, 4], [C, 5],
		[I, 12], [I, 13], [I, 14],
		[I, 4], [C, 7], [D, 12], [D, 5],
	]


static func steps() -> Array:
	var D := Enums.NodeType.DATA
	var I := Enums.NodeType.ICE
	var B := Enums.NodeType.BREACH
	var C := Enums.NodeType.COOLANT
	return [
		# ------------------------------------------------------------ story + goal
		{"text": "Welcome, Operator. I am [b]NODE-9[/b]. You planted your " + C_DAEMON + "OROBOROS PROTOCOL" + C_END + " inside this Server to [b]siphon bytes[/b]. But it is a snake eating its tail: it drains the Server, and its [b]Glitches can also destroy it[/b].", "target": "none", "dock": "bottom"},
		{"text": "[b]THE GOAL[/b]\nSiphon the [b]THRESHOLD[/b] in bytes before the Server dies or your Nodes run out. Clear Servers, earn Nullcoin (Ø), survive [b]8 Networks[/b].", "target": "quota"},
		{"text": "[b]THE BYTE ENGINE[/b]\nEvery turn scores  " + C_DATA + "BASE BYTES" + C_END + "  x  " + C_DAEMON + "OVERCLOCK" + C_END + ". Everything in this game adds to one of them or multiplies them.", "target": "score"},
		{"text": "[b]SERVER INTEGRITY[/b]\nThe Server's health: [b]10[/b] to start. Glitches damage it, " + C_COOL + "Patches" + C_END + " repair it. At [b]0 the run ends[/b]. A little damage is actually [b]useful[/b]: you will see why.", "target": "rig"},
		# ------------------------------------------------------------ the room
		{"text": "[b]THE ROOM[/b]\nYour [b]Tailbytes[/b] is a deck of 52 Nodes. Every turn you are dealt [b]4[/b] of them. You [b]resolve 3[/b]; the one you leave goes to your [b]Stash[/b] and comes back next turn.", "target": "room"},
		{"text": "[b]4 KINDS OF NODE[/b] (hover any card to read it)\n" + C_DATA + "SIPHON" + C_END + " mines bytes (value x2).   " + C_ICE + "GLITCH" + C_END + " damages the Server.\n" + C_BREACH + "FIREWALL" + C_END + " blocks Glitch damage.   " + C_COOL + "PATCH" + C_END + " repairs Integrity.", "target": "room", "dock": "bottom"},
		# ------------------------------------------------------------ first play
		{"text": "Choose [b]3 of these 4[/b]. They resolve in the [b]order you click[/b]. Start with the " + C_BREACH + "FIREWALL 4" + C_END + ": a Firewall must be equipped [b]before[/b] the Glitch it should block.", "expect": "card", "target": "card", "lit": "room", "card": [B, 4]},
		{"text": "Now the " + C_ICE + "GLITCH 6" + C_END + ". The Firewall subtracts its Strength: 6 - 4 = [b]2 damage[/b]. [b]Any damage gives +1 OVERCLOCK for the rest of the Server.[/b]", "expect": "card", "target": "card", "lit": "room", "card": [I, 6]},
		{"text": "Last, the " + C_DATA + "SIPHON 8" + C_END + " for bytes (8 x 2 = 16). The Patch stays behind in your Stash.", "expect": "card", "target": "card", "lit": "room", "card": [D, 8]},
		{"text": "[b]SUBROUTINE[/b]\nYour 3 Nodes form a combo, like a poker hand: [b]Surgical Strike[/b] (1 Firewall + 1 Glitch + 1 Siphon). It adds free Base Bytes [b]and[/b] Overclock.", "target": "score"},
		{"text": "[b]DAEMONS[/b]\nPermanent upgrades (max 5) you buy later. " + C_DAEMON + "FLOPPY DISK" + C_END + " gives [b]+4 Base Bytes per Node[/b]. They fire left to right, and you can drag them to reorder.", "target": "daemons"},
		{"text": "Press [b]EXECUTE[/b] to run your 3 Nodes!", "expect": "execute", "target": "execute"},
		{"expect": "turn_done", "hide": true, "text": ""},
		# ------------------------------------------------------------ after turn 1
		{"text": "[b]WHAT HAPPENED[/b]\nThe Glitch dealt 2 damage, so you gained [b]+1 Overclock[/b]. Integrity is now {health}. Your Firewall keeps its Strength, but its [b]ceiling drops to 5[/b]: it only blocks Glitches up to the ceiling.", "target": "weapon", "dock": "bottom"},
		# ------------------------------------------------------------ the eject
		{"do": "deal", "text": "Uh-oh: " + C_ICE + "GLITCH 12, 13 and 14" + C_END + ". Your Firewall cannot block them, and taking two would crash the Server.\n\n[b]EJECT[/b] throws away the whole room and deals a fresh one. It costs no turn, but you only get a few per Server. Press [b]EJECT[/b].", "expect": "skip", "target": "skip"},
		# ------------------------------------------------------------ damage is power
		{"text": "[b]DAMAGE IS POWER[/b]\nThis " + C_ICE + "GLITCH 4" + C_END + " is weak: your Firewall would erase it. But damage gives Overclock! Switch the Firewall [b]OFF[/b] so the Server takes the full hit. Press [b]FIREWALL: AUTO[/b].", "expect": "weapon", "target": "weapon_toggle"},
		{"text": "Take the hit first: select the " + C_ICE + "GLITCH 4" + C_END + ".", "expect": "card", "target": "card", "lit": "room", "card": [I, 4]},
		{"text": "Then repair it with the " + C_COOL + "PATCH 7" + C_END + ". [b]Damage first, repair after.[/b] That is the secret of the engine.", "expect": "card", "target": "card", "lit": "room", "card": [C, 7]},
		{"text": "Finish with the " + C_DATA + "SIPHON 12" + C_END + " for the big bytes.", "expect": "card", "target": "card", "lit": "room", "card": [D, 12]},
		{"text": "Press [b]EXECUTE[/b]!", "expect": "execute", "target": "execute"},
		{"expect": "turn_done", "hide": true, "text": ""},
		# ------------------------------------------------------------ wrap up
		{"text": "Bytes {score} / {quota}. You just did what winning runs do: [b]took damage on purpose for Overclock, repaired it, then siphoned.[/b] Clear a Server within 4 turns for a bonus.", "target": "quota", "dock": "bottom"},
		{"text": "[b]THE RUN[/b]\nEach Network has 3 Servers: Proxy, Mainframe and a Sentinel with a nasty special rule. Between Servers, spend Ø in the Black Market on Daemons, Firmware (levels up Subroutines) and Executables (one-use tools).", "target": "none", "dock": "bottom"},
		{"text": "[b]REMEMBER[/b]\n- Resolve 3 of 4 Nodes; the 4th is Stashed.\n- Firewall first, biggest Glitch first.\n- Damage raises Overclock; Patches keep the Server alive.\n- Check TAILBYTES and SUBROUTINES often.\n\nThat is everything, Operator. Hit [b]INITIATE NEW RUN[/b] when you are ready.", "target": "none", "dock": "bottom"},
	]
