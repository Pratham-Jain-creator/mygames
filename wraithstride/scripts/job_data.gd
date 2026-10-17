extends RefCounted
## Static FFT-style job table. Jobs change the parkour feel (move / jump / air dashes),
## the combat feel (posture, deflect window, attack speed) and two charge-time abilities.
##
## ability.kind -> effect (implemented in player.gd):
##   heal   restore HP            guard  damage + posture reduction buff
##   bolt   ranged hitscan spell  bash   melee posture burst
##   step   i-frame super dash    haste  run speed buff
##   leap   FFT "Jump": launch, hold Ctrl to dive, AoE on landing
##   thrust long-reach stab       wave   piercing cone of force
##   blink  teleport along aim
## ct = charge time (seconds, interrupted by damage), cd = cooldown.

const MAX_LEVEL := 5

const ORDER: Array[StringName] = [
	&"knight", &"white_mage", &"black_mage", &"thief", &"dragoon", &"monk",
]

const JOBS := {
	&"knight": {
		"name": "Knight", "role": "Tank", "weapon": "Sword", "color": Color(0.75, 0.8, 0.92),
		"hp": 160, "posture": 150, "move": 0.86, "jump": 8.6, "air_dashes": 1,
		"deflect_window": 0.24, "atk_damage": 30, "atk_posture": 28, "atk_cd": 0.55, "dash_cd": 1.2,
		"abilities": [
			{"name": "Iron Bulwark", "kind": "guard", "ct": 0.0, "cd": 8.0, "power": 0.75, "dur": 3.0, "posture": 0},
			{"name": "Shield Bash", "kind": "bash", "ct": 0.2, "cd": 4.0, "power": 20, "dur": 0.0, "posture": 45},
		],
	},
	&"white_mage": {
		"name": "White Mage", "role": "Healer", "weapon": "Staff", "color": Color(0.7, 1.0, 0.8),
		"hp": 90, "posture": 80, "move": 1.0, "jump": 9.0, "air_dashes": 1,
		"deflect_window": 0.16, "atk_damage": 14, "atk_posture": 10, "atk_cd": 0.45, "dash_cd": 1.0,
		"abilities": [
			{"name": "Cure", "kind": "heal", "ct": 0.8, "cd": 5.0, "power": 45, "dur": 0.0, "posture": 0},
			{"name": "Protect", "kind": "guard", "ct": 0.4, "cd": 10.0, "power": 0.5, "dur": 6.0, "posture": 0},
		],
	},
	&"black_mage": {
		"name": "Black Mage", "role": "Ranged DPS", "weapon": "Rod", "color": Color(0.8, 0.6, 1.0),
		"hp": 80, "posture": 70, "move": 1.0, "jump": 9.0, "air_dashes": 2,
		"deflect_window": 0.16, "atk_damage": 14, "atk_posture": 10, "atk_cd": 0.45, "dash_cd": 1.0,
		"abilities": [
			{"name": "Fire", "kind": "bolt", "ct": 0.7, "cd": 2.5, "power": 45, "dur": 0.0, "posture": 15},
			{"name": "Blink", "kind": "blink", "ct": 0.0, "cd": 3.0, "power": 12, "dur": 0.0, "posture": 0},
		],
	},
	&"thief": {
		"name": "Thief", "role": "Speedster", "weapon": "Dagger", "color": Color(1.0, 0.85, 0.4),
		"hp": 100, "posture": 90, "move": 1.2, "jump": 9.5, "air_dashes": 2,
		"deflect_window": 0.14, "atk_damage": 18, "atk_posture": 14, "atk_cd": 0.32, "dash_cd": 0.7,
		"abilities": [
			{"name": "Vanish", "kind": "step", "ct": 0.0, "cd": 4.0, "power": 52, "dur": 0.28, "posture": 0},
			{"name": "Haste", "kind": "haste", "ct": 0.3, "cd": 9.0, "power": 1.5, "dur": 4.0, "posture": 0},
		],
	},
	&"dragoon": {
		"name": "Dragoon", "role": "Aerial Bruiser", "weapon": "Spear", "color": Color(0.5, 0.75, 1.0),
		"hp": 120, "posture": 110, "move": 1.0, "jump": 11.0, "air_dashes": 1,
		"deflect_window": 0.18, "atk_damage": 26, "atk_posture": 22, "atk_cd": 0.6, "dash_cd": 1.0,
		"abilities": [
			{"name": "Jump", "kind": "leap", "ct": 0.4, "cd": 6.0, "power": 40, "dur": 0.0, "posture": 40},
			{"name": "Lancet Thrust", "kind": "thrust", "ct": 0.15, "cd": 3.5, "power": 35, "dur": 0.0, "posture": 30},
		],
	},
	&"monk": {
		"name": "Monk", "role": "Brawler", "weapon": "Fists", "color": Color(1.0, 0.6, 0.35),
		"hp": 130, "posture": 120, "move": 1.08, "jump": 9.5, "air_dashes": 1,
		"deflect_window": 0.2, "atk_damage": 20, "atk_posture": 20, "atk_cd": 0.28, "dash_cd": 0.9,
		"abilities": [
			{"name": "Wave Fist", "kind": "wave", "ct": 0.3, "cd": 4.0, "power": 30, "dur": 0.0, "posture": 25},
			{"name": "Chakra", "kind": "heal", "ct": 0.5, "cd": 8.0, "power": 30, "dur": 0.0, "posture": 0},
		],
	},
}
