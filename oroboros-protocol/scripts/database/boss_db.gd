class_name BossDB
extends RefCounted
## Sentinel (Black-ICE) Server modifiers.
## Every Sentinel has a difficulty tier: SIMPLE, HARD or VERY_HARD.
## A run draws its Sentinels by Network: 1-3 SIMPLE, 4-6 HARD, 7-8 VERY_HARD (no repeats).
## Past Network 8 (endless) they come from the whole pool at random, never repeating until all have appeared.

enum Tier { SIMPLE, HARD, VERY_HARD }
const TIER_NAMES := ["SIMPLE", "HARD", "VERY HARD"]

## id -> {name, desc, tier, quota (Threshold multiplier, default 1.0)}
const BOSSES := {
	# ------------------------------------------------------------------ SIMPLE
	"wall": {"name": "The Wall", "tier": 0, "desc": "Node values cannot exceed 10."},
	"leech": {"name": "The Leech", "tier": 0, "desc": "Patch Nodes no longer restore Integrity."},
	"furnace": {"name": "The Furnace", "tier": 0, "desc": "Firewalls degrade by double the normal amount."},
	"static": {"name": "The Static", "tier": 0, "desc": "Siphon values are reduced by 1 (minimum 1)."},
	"frost": {"name": "The Frost", "tier": 0, "desc": "Your first turn in this Server scores half."},
	"tax": {"name": "The Tax Man", "tier": 0, "desc": "You lose Ø3 when this Server starts (down to Ø0)."},
	"sponge": {"name": "The Sponge", "tier": 0, "desc": "Newly equipped Firewalls have 2 less Strength."},
	"drought": {"name": "The Drought", "tier": 0, "desc": "Patch Nodes restore only half their value (rounded down)."},
	"shackle": {"name": "The Shackle", "tier": 0, "desc": "You can Eject only once this Server."},
	"hound": {"name": "The Hound", "tier": 0, "desc": "The Threshold is 15% higher.", "quota": 1.15},
	# -------------------------------------------------------------------- HARD
	"needle": {"name": "The Needle", "tier": 1, "desc": "Ejecting a room deals 5 unmitigated Integrity damage to the Server."},
	"void": {"name": "The Void", "tier": 1, "desc": "Base Bytes from Subroutines is reduced to 0."},
	"mirror": {"name": "The Mirror", "tier": 1, "desc": "All Glitch values are doubled."},
	"cipher": {"name": "The Cipher", "tier": 1, "desc": "Node values are hidden (types stay visible). The one Node you stash is revealed. Track the Tailbytes to deduce the rest."},
	"leak": {"name": "The Leak", "tier": 1, "desc": "The Server loses 1 Integrity at the start of every turn."},
	"choke": {"name": "The Choke", "tier": 1, "desc": "A single turn can score at most 45% of the Threshold."},
	"sieve": {"name": "The Sieve", "tier": 1, "desc": "Siphons score their face value instead of double."},
	"phantom": {"name": "The Phantom", "tier": 1, "desc": "From turn 2 on, Node values are hidden (types stay visible)."},
	"undertow": {"name": "The Undertow", "tier": 1, "desc": "A Stashed Node gains +3 value for every turn it stays."},
	"rollback": {"name": "The Rollback", "tier": 1, "desc": "Firmware Updates are disabled: every Subroutine plays at level 0."},
	"gag": {"name": "The Gag", "tier": 1, "desc": "Your first (leftmost) Daemon is disabled."},
	"toll": {"name": "The Toll Booth", "tier": 1, "desc": "Ejecting costs Ø3. You cannot Eject without it."},
	# --------------------------------------------------------------- VERY HARD
	"lock": {"name": "The Lock", "tier": 2, "desc": "You cannot Stash Nodes. You must play exactly the first 3 you click; the rest are lost."},
	"famine": {"name": "The Famine", "tier": 2, "desc": "You get only 3 turns in this Server."},
	"shatter": {"name": "The Shatter", "tier": 2, "desc": "A Firewall that takes any hit breaks completely."},
	"plague": {"name": "The Plague", "tier": 2, "desc": "All Glitches get +3 value."},
	"warden": {"name": "The Warden", "tier": 2, "desc": "You cannot Eject."},
	"null": {"name": "The Null", "tier": 2, "desc": "Subroutines give nothing: no Base Bytes and no Overclock. Only Nodes and Daemons score."},
	"reaper": {"name": "The Reaper", "tier": 2, "desc": "Integrity cannot be restored by anything."},
	"hemorrhage": {"name": "The Hemorrhage", "tier": 2, "desc": "The Server loses 1 Integrity at the start of every turn, and Patch Nodes restore only half."},
	"tyrant": {"name": "The Tyrant", "tier": 2, "desc": "The Threshold is 35% higher.", "quota": 1.35},
	"purge": {"name": "The Purge", "tier": 2, "desc": "Your first two (leftmost) Daemons are disabled."},
}


static func ids_in_tier(tier: int) -> Array:
	var out: Array = []
	for id in BOSSES:
		if int(BOSSES[id].tier) == tier:
			out.append(id)
	return out


static func tier_of(id: String) -> int:
	return int(BOSSES[id].tier) if BOSSES.has(id) else 0


static func tier_name(id: String) -> String:
	return TIER_NAMES[tier_of(id)]


## The tier a given Network draws from: 1-3 simple, 4-6 hard, 7+ very hard.
static func tier_for_network(network: int) -> int:
	if network <= 3:
		return Tier.SIMPLE
	if network <= 6:
		return Tier.HARD
	return Tier.VERY_HARD


## One Sentinel for each of the 8 Networks, drawn from the matching tier without repeats.
static func build_order() -> Array:
	var pools := [ids_in_tier(0), ids_in_tier(1), ids_in_tier(2)]
	for p in pools:
		p.shuffle()
	var out: Array = []
	for net in range(1, 9):
		out.append(pools[tier_for_network(net)].pop_back())
	return out


## Endless: any Sentinel not seen yet this run; when all have appeared the cycle restarts
## (but never repeats the one just used).
static func next_endless(used: Array) -> String:
	var fresh: Array = []
	for id in BOSSES:
		if not used.has(id):
			fresh.append(id)
	if fresh.is_empty():
		var last: String = used[used.size() - 1] if not used.is_empty() else ""
		for id in BOSSES:
			if id != last:
				fresh.append(id)
	return fresh.pick_random()


static func quota_mult(id: String) -> float:
	return float(BOSSES[id].get("quota", 1.0)) if BOSSES.has(id) else 1.0


static func name_of(id: String) -> String:
	return BOSSES[id].name if BOSSES.has(id) else ""


static func desc_of(id: String) -> String:
	return BOSSES[id].desc if BOSSES.has(id) else ""
