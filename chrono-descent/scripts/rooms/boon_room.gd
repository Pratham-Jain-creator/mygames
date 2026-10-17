class_name BoonRoom
extends Node
## The 15 boon rooms. A boon room is a quiet dead end with a prop to use (a table, a font, a chest...). Most boons have
## a price or a risk. Which one a room is: `kind` (see SpecialRooms.KINDS). Each _build_* function places the props.

const TIME_LOCK_SECONDS: float = 300.0

var room: WFCRoom
var kind: StringName
var cfg: LevelConfig
var generator: Node
var depth: int = 1

var _time_chest: Altar
var _time_chest_open: bool = false


func setup_special(p_room: WFCRoom, p_kind: StringName, p_cfg: LevelConfig, p_generator: Node) -> void:
	room = p_room
	kind = p_kind
	cfg = p_cfg
	generator = p_generator
	depth = cfg.depth
	call("_build_" + String(kind))


func _process(_delta: float) -> void:
	if kind == &"time_locked_chest" and is_instance_valid(_time_chest) and not _time_chest_open:
		var level := RoomKit.level_of(room)
		if level == null:
			return
		var elapsed := cfg.duration - level.time_left
		var left := TIME_LOCK_SECONDS - elapsed
		if left <= 0.0:
			_time_chest.enabled = false
			_time_chest.disabled_prompt = "SEALED FOREVER"
		else:
			_time_chest.prompt = "OPEN  (SEALS IN %d:%02d)" % [int(left) / 60, int(left) % 60]


# ------------------------------------------------------------------ 1. the Grafting Table

func _build_grafting_table() -> void:
	var table := RoomKit.altar(room, &"table", "DRAFT A PARASITIC GRAFT", Color(0.85, 0.3, 0.45), func(_by: Node) -> void: pass)
	table.callback = _use_grafting_table.bind(table)


func _use_grafting_table(_by: Node, table: Altar) -> void:
	if Run.free_slot() < 0:
		RoomKit.toast("EVERY CHARM SLOT IS FULL: CLEANSE A GRAFT FIRST", Color(1.0, 0.5, 0.4))
		return
	var owned: Array[String] = []
	for i in Run.SLOT_COUNT:
		var info := Run.slot_info(i)
		if not info.is_empty() and info["kind"] == "graft":
			owned.append(String(info["id"]))
	var pool: Array = RunData.GRAFTS.keys().filter(func(id: StringName) -> bool: return not owned.has(String(id)))
	var options: Array = []
	var ids: Array = RoomKit.pick_distinct(pool, 3)
	for id: StringName in ids:
		var g: Dictionary = RunData.GRAFTS[id]
		options.append({"name": g["name"], "desc": "%s\nCURSE: %s" % [g["desc"], g["curse"]], "color": g["color"]})
	RoomKit.menu().open("THE GRAFTING TABLE", "A graft takes a charm slot and will not come off until you die or find a Cleansing Pool.", options, func(index: int) -> void:
		if index < 0:
			return
		if Run.add_slotted(ids[index], "graft"):
			RoomKit.toast("GRAFTED: %s" % String(RunData.GRAFTS[ids[index]]["name"]).to_upper(), Color(0.95, 0.4, 0.5))
			Audio.play(preload("res://assets/sounds/power_up.wav"), -4.0, 0.7)
			GameManager.shake_camera(3.0, 0.3)
			RoomKit.use_up(table))


# ------------------------------------------------------------------ 2. the Alchemist's Remains

func _build_alchemist_remains() -> void:
	var remains := RoomKit.altar(room, &"corpse", "SEARCH THE REMAINS", Color(0.5, 0.9, 0.5), func(_by: Node) -> void: pass)
	remains.callback = func(_by: Node) -> void:
		Run.refill_canteen()
		RoomKit.heal(int(float(Run.max_health()) * 0.5))
		RoomKit.toast("THE CANTEEN IS FULL AGAIN", Color(0.5, 1.0, 0.6))
		Audio.play(preload("res://assets/sounds/power_up.wav"), -4.0, 1.2)
		RoomKit.use_up(remains, "PICKED CLEAN")


# ------------------------------------------------------------------ 3. the Weapon Mold

func _build_weapon_mold() -> void:
	var mold := RoomKit.altar(room, &"mold", "RECAST THE SWORD", Color(1.0, 0.6, 0.25), func(_by: Node) -> void: pass)
	mold.callback = func(_by: Node) -> void:
		var ids: Array = []
		var options: Array = []
		for id: StringName in RunData.FORMS:
			if id == Run.form:
				continue
			ids.append(id)
			var f: Dictionary = RunData.FORMS[id]
			options.append({"name": f["name"], "desc": f["desc"], "color": Color(1.0, 0.7, 0.35)})
		RoomKit.menu().open("THE WEAPON MOLD", "Your sword is the %s. Recast it into a form that suits the next fight (until you die)." % String(RunData.FORMS[Run.form]["name"]).to_lower(), options, func(index: int) -> void:
			if index < 0:
				return
			Run.form = ids[index]
			Run.changed.emit()
			RoomKit.toast("THE SWORD IS NOW A %s" % String(RunData.FORMS[ids[index]]["name"]).to_upper(), Color(1.0, 0.7, 0.35))
			Audio.play(preload("res://assets/sounds/explosion.wav"), -8.0, 1.5)
			mold.prompt = "RECAST THE SWORD AGAIN")


# ------------------------------------------------------------------ 4. the Memory Echo

func _build_memory_echo() -> void:
	var echo := RoomKit.altar(room, &"basin", "TAKE THE MEMORY ECHO", Color(0.6, 0.85, 1.0), func(_by: Node) -> void: pass)
	echo.callback = func(_by: Node) -> void:
		Run.echoes += 1
		Run.save_profile()
		RoomKit.toast("MEMORY ECHO: IT KEEPS UNTIL YOU USE IT", Color(0.6, 0.85, 1.0))
		Audio.play(preload("res://assets/sounds/power_up.wav"), -4.0, 1.5)
		RoomKit.use_up(echo, "THE ECHO IS GONE")


# ------------------------------------------------------------------ 5. the Smuggler's Cache

func _build_smugglers_cache() -> void:
	var cache := RoomKit.altar(room, &"chest", "OPEN THE CACHE", Color(1.0, 0.85, 0.4), func(_by: Node) -> void: pass)
	cache.callback = func(_by: Node) -> void:
		RoomKit.use_up(cache, "EMPTY")
		cache.opened = true
		var spawn_at := cache.global_position + Vector2(0, 6)
		Loot.drop_ash(RoomKit.spawned(room), spawn_at, int(round(120.0 * Loot.floor_scale(depth))))
		RoomKit.toast("A FORTUNE IN ASH... AND THEY HEARD IT", Color(1.0, 0.85, 0.4))
		GameManager.shake_camera(4.0, 0.3)
		_spawn_guards(3)


func _spawn_guards(count: int) -> void:
	var points := room.find_spawn_points(count, 56.0, room.get_reserved_points(), 1, 90.0)
	for i in mini(count, points.size()):
		var choice: Dictionary = generator.pick_enemy(int(40.0 * cfg.difficulty))
		if choice.is_empty():
			continue
		var enemy := generator._spawn_enemy(room, choice["path"], points[i], {"is_elite": true}) as EnemyBase
		if enemy != null:
			enemy.wake_up()


# ------------------------------------------------------------------ 6. the Time-Locked Chest

func _build_time_locked_chest() -> void:
	_time_chest = RoomKit.altar(room, &"chest", "OPEN", Color(0.7, 0.5, 1.0), func(_by: Node) -> void: pass)
	_time_chest.callback = func(_by: Node) -> void:
		_time_chest_open = true
		RoomKit.use_up(_time_chest, "EMPTY")
		var at := _time_chest.global_position + Vector2(0, 6)
		Loot.drop_materials(RoomKit.spawned(room), at, 3, depth, RoomKit.tier(depth, 1))
		Loot.drop_ash(RoomKit.spawned(room), at, int(round(60.0 * Loot.floor_scale(depth))))
		if randf() < 0.35:
			Pickup.spawn(RoomKit.spawned(room), at, Pickup.Kind.ECHO, 1)
		RoomKit.toast("RARE LOOT", Color(0.8, 0.6, 1.0))
		Audio.play(preload("res://assets/sounds/coin.wav"), -4.0, 0.7)


# ------------------------------------------------------------------ 7. the Cleansing Pool

func _build_cleansing_pool() -> void:
	var pool := RoomKit.altar(room, &"basin", "CLEANSE A GRAFT", Color(0.5, 0.95, 1.0), func(_by: Node) -> void: pass)
	pool.callback = func(_by: Node) -> void:
		var slots: Array[int] = []
		var options: Array = []
		for i in Run.SLOT_COUNT:
			var info := Run.slot_info(i)
			if not info.is_empty() and info["kind"] == "graft":
				slots.append(i)
				options.append({"name": info["def"]["name"], "desc": "Remove it and free the slot. Its curse leaves with it.", "color": info["def"]["color"]})
		if slots.is_empty():
			RoomKit.toast("YOU CARRY NO GRAFTS", Color(0.8, 0.8, 0.8))
			return
		RoomKit.menu().open("THE CLEANSING POOL", "One graft may be washed away.", options, func(index: int) -> void:
			if index < 0:
				return
			if Run.remove_graft(slots[index]):
				RoomKit.toast("THE GRAFT DISSOLVES", Color(0.5, 0.95, 1.0))
				Audio.play(preload("res://assets/sounds/power_up.wav"), -4.0, 1.4)
				RoomKit.use_up(pool, "THE WATER IS SPENT"))


# ------------------------------------------------------------------ 8. the Anvil of the Predecessor

func _build_anvil_predecessor() -> void:
	var anvil := RoomKit.altar(room, &"anvil", "TEMPER YOUR BLADE", Color(1.0, 0.7, 0.3), func(_by: Node) -> void: pass)
	anvil.callback = func(_by: Node) -> void:
		var options: Array = [
			{"name": "Quench it hot", "desc": "+15% sword damage for the rest of THIS FLOOR (gone if the floor shifts or you leave it).", "color": Color(1.0, 0.6, 0.3)},
			{"name": "Quench it slow", "desc": "+10% sword damage for 30 minutes of play, on any floor.", "color": Color(0.6, 0.85, 1.0)},
		]
		RoomKit.menu().open("THE ANVIL OF THE PREDECESSOR", "", options, func(index: int) -> void:
			if index == 0:
				Run.add_floor_buff("ANVIL: +15% DAMAGE (THIS FLOOR)", {"damage": 0.15})
			elif index == 1:
				Run.add_timed_buff("ANVIL: +10% DAMAGE", {"damage": 0.10}, 1800.0)
			else:
				return
			RoomKit.toast("THE BLADE RINGS TRUE", Color(1.0, 0.8, 0.4))
			Audio.play(preload("res://assets/sounds/explosion.wav"), -8.0, 1.2)
			RoomKit.use_up(anvil, "THE ANVIL IS COLD"))


# ------------------------------------------------------------------ 9. the Cartographer's Corpse

func _build_cartographers_corpse() -> void:
	var corpse := RoomKit.altar(room, &"corpse", "READ THE CARTOGRAPHER'S NOTES", Color(0.9, 0.8, 0.5), func(_by: Node) -> void: pass)
	corpse.callback = func(_by: Node) -> void:
		var pool: Array = SpecialRooms.kinds_of("boon") + SpecialRooms.kinds_of("curse")
		pool = pool.filter(func(k: StringName) -> bool: return k != kind)
		var ids: Array = RoomKit.pick_distinct(pool, 5)
		var options: Array = []
		for id: StringName in ids:
			var info: Dictionary = SpecialRooms.KINDS[id]
			options.append({"name": info["name"], "desc": "%s: %s" % [String(info["family"]).to_upper(), info["tagline"]], "color": SpecialRooms.family_color(info["family"])})
		RoomKit.menu().open("THE CARTOGRAPHER'S NOTES", "Choose ONE room that the dungeon's next shift will make sure to build.", options, func(index: int) -> void:
			if index < 0:
				return
			Run.next_refresh_room = ids[index]
			RoomKit.toast("THE NEXT SHIFT BRINGS: %s" % SpecialRooms.display_name(ids[index]).to_upper(), Color(0.95, 0.85, 0.5))
			RoomKit.use_up(corpse, "THE NOTES ARE READ"))


# ------------------------------------------------------------------ 10. the Bestiary Scholar

func _build_bestiary_scholar() -> void:
	var scholar := RoomKit.altar(room, &"reaper", "TALK TO THE SCHOLAR", Color(0.7, 0.7, 1.0), func(_by: Node) -> void: pass)
	scholar.callback = func(_by: Node) -> void:
		var at := scholar.global_position + Vector2(0, 14)
		Loot.drop_materials(RoomKit.spawned(room), at, 3, depth, RoomKit.tier(depth, 1))
		RoomKit.toast("\"TAKE THESE. I HAVE STUDIED WORSE.\"", Color(0.8, 0.8, 1.0))
		RoomKit.use_up(scholar, "HE RETURNS TO HIS BOOKS")


# ------------------------------------------------------------------ 11. the Blood Font

func _build_blood_font() -> void:
	var font := RoomKit.altar(room, &"font", "DRINK FROM THE BLOOD FONT", Color(0.9, 0.15, 0.2), func(_by: Node) -> void: pass)
	font.callback = func(_by: Node) -> void:
		var debt := int(round(float(Run.max_health()) * 0.20))
		RoomKit.menu().open("THE BLOOD FONT", "Pay %d health as BLOOD DEBT: you lose it now, and the next %d points of healing you receive only repay the debt. In return: a Tactical Override module for your sword." % [debt, debt], [
			{"name": "Pay the debt", "desc": "-%d health now. +1 weapon module." % debt, "color": Color(0.95, 0.3, 0.3)},
		], func(index: int) -> void:
			if index != 0:
				return
			if not RoomKit.pay_health(debt):
				return
			Run.blood_debt += debt
			var ids: Array = RunData.MODULES.keys().filter(func(id: StringName) -> bool: return id != Run.module)
			Run.module = ids[randi() % ids.size()]
			Run.changed.emit()
			RoomKit.toast("MODULE: %s" % String(RunData.MODULES[Run.module]["name"]).to_upper(), Color(1.0, 0.5, 0.4))
			Audio.play(preload("res://assets/sounds/hurt.wav"), -4.0, 0.6)
			RoomKit.use_up(font, "THE FONT IS DRY"))


# ------------------------------------------------------------------ 12. the Shortcut Shaft

func _build_shortcut_shaft() -> void:
	var shaft := RoomKit.altar(room, &"hole", "JUMP INTO THE SHAFT", Color(0.6, 0.5, 0.9), func(_by: Node) -> void: pass)
	shaft.callback = func(_by: Node) -> void:
		var floors: Array[int] = []
		var options: Array = []
		for d in range(0, depth):
			floors.append(d)
			options.append({"name": "The base" if d == 0 else "Floor %d" % d, "desc": "Back to the hideout: whatever you carry is banked, and the run ends." if d == 0 else "Arrive beside that floor's way down.", "color": Color(0.7, 0.6, 1.0)})
		RoomKit.menu().open("THE SHORTCUT SHAFT", "Anywhere you have already been.", options, func(index: int) -> void:
			if index >= 0:
				GameManager.travel_requested.emit(floors[index]))


# ------------------------------------------------------------------ 13. the Forlorn Shrine

func _build_forlorn_shrine() -> void:
	var shrine := RoomKit.altar(room, &"shrine", "PRAY AT THE SHRINE", Color(0.95, 0.95, 0.7), func(_by: Node) -> void: pass)
	shrine.callback = func(_by: Node) -> void:
		if Run.shield:
			RoomKit.toast("YOU ARE ALREADY PROTECTED", Color(0.8, 0.8, 0.8))
			return
		Run.shield = true
		Run.changed.emit()
		RoomKit.toast("A SHIELD WILL TAKE THE NEXT DEADLY BLOW", Color(0.7, 0.9, 1.0))
		Audio.play(preload("res://assets/sounds/power_up.wav"), -4.0, 1.0)
		RoomKit.use_up(shrine, "THE SHRINE IS QUIET")


# ------------------------------------------------------------------ 14. the Glass Blower

func _build_glass_blower() -> void:
	var table := RoomKit.altar(room, &"table", "SEE THE GLASS BLOWER", Color(0.5, 0.9, 0.9), func(_by: Node) -> void: pass)
	table.callback = func(_by: Node) -> void:
		if Run.instant_canteen:
			RoomKit.toast("YOUR CANTEEN IS ALREADY GLASS", Color(0.8, 0.8, 0.8))
			return
		if Run.canteen_max() <= 1:
			RoomKit.toast("YOU HAVE NO CHARGE TO SPARE", Color(1.0, 0.5, 0.4))
			return
		RoomKit.menu().open("THE GLASS BLOWER", "", [
			{"name": "Reblow the canteen", "desc": "Drinking takes no time at all. But one flask charge shatters in the making (until you die).", "color": Color(0.6, 0.95, 1.0)},
		], func(index: int) -> void:
			if index != 0:
				return
			Run.instant_canteen = true
			Run.canteen_penalty += 1
			Run.canteen = mini(Run.canteen, Run.canteen_max())
			Run.canteen_changed.emit()
			Run.changed.emit()
			RoomKit.toast("THE CANTEEN HEALS INSTANTLY NOW", Color(0.6, 0.95, 1.0))
			Audio.play(preload("res://assets/sounds/explosion.wav"), -10.0, 1.8)
			RoomKit.use_up(table, "THE FURNACE IS COLD"))


# ------------------------------------------------------------------ 15. the Silent Monolith

func _build_silent_monolith() -> void:
	var monolith := RoomKit.altar(room, &"monolith", "TOUCH THE MONOLITH", Color(0.6, 0.9, 0.8), func(_by: Node) -> void: pass)
	monolith.callback = func(_by: Node) -> void:
		var ids: Array = RoomKit.pick_distinct(RunData.CHARMS.keys(), 3)
		var options: Array = []
		for id: StringName in ids:
			var c: Dictionary = RunData.CHARMS[id]
			options.append({"name": c["name"], "desc": "%s  (for this run only)" % c["desc"], "color": c["color"]})
		RoomKit.menu().open("THE SILENT MONOLITH", "Three perfect charms. One may be yours until this run ends.", options, func(index: int) -> void:
			if index < 0:
				return
			if Run.add_slotted(ids[index], "temp"):
				_took_charm(monolith, ids[index])
			else:
				_replace_charm(monolith, ids[index]))


func _replace_charm(monolith: Altar, charm_id: StringName) -> void:
	var slots: Array[int] = []
	var options: Array = []
	for i in Run.SLOT_COUNT:
		var info := Run.slot_info(i)
		if not info.is_empty() and info["kind"] != "graft":
			slots.append(i)
			options.append({"name": info["def"]["name"], "desc": "Replace this charm for the rest of the run (it returns when you reach the base).", "color": info["def"]["color"]})
	if slots.is_empty():
		RoomKit.toast("EVERY SLOT HOLDS A GRAFT", Color(1.0, 0.5, 0.4))
		return
	RoomKit.menu().open("WHICH CHARM GIVES WAY?", "", options, func(index: int) -> void:
		if index < 0:
			return
		Run.slots[slots[index]] = {"kind": "temp", "id": String(charm_id)}
		Run.changed.emit()
		_took_charm(monolith, charm_id))


func _took_charm(monolith: Altar, charm_id: StringName) -> void:
	RoomKit.toast("%s: SLOTTED FOR THIS RUN" % String(RunData.CHARMS[charm_id]["name"]).to_upper(), Color(0.6, 0.95, 0.85))
	Audio.play(preload("res://assets/sounds/power_up.wav"), -4.0, 1.1)
	RoomKit.use_up(monolith, "THE MONOLITH IS SILENT")
