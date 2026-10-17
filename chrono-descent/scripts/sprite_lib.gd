class_name SpriteLib
extends RefCounted
## Builds SpriteFrames from sprite SHEETS in code, so a scene only needs an empty AnimatedSprite2D.
## Sheets are loaded through the editor's import when it has one, and straight from the PNG file otherwise (a new
## sheet works the moment it is dropped into the project; an exported game always has the import).
##
## Every sheet in the new art is a grid of square cells: ROWS are directions (and sometimes different attacks),
## COLUMNS are frames. add_row() cuts one animation out of one row.

const PRISONER_SHEETS: String = "res://assets/sprites/character/prisoner/"
const MOBS: String = "res://assets/sprites/enemies/mobs/"
const BOSSES: String = "res://assets/sprites/enemies/boss/"
## Direction order of the prisoner sheets (8 rows) and of the 4-way enemy sheets.
const DIRS8: Array[String] = ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]
const DIRS4: Array[String] = ["down", "left", "right", "up"]

static var _cache: Dictionary = {}


## The texture of a sheet (null when the file does not exist at all).
static func texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null:
			tex = ImageTexture.create_from_image(image)
	_cache[path] = tex
	return tex


## Adds an animation made of `count` frames starting at column `first_col` of row `row`.
static func add_row(frames: SpriteFrames, anim_name: String, tex: Texture2D, cell: int, row: int, first_col: int, count: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, loop)
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2((first_col + i) * cell, row * cell, cell, cell)
		frames.add_frame(anim_name, atlas)


static func _empty() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	return frames


# ------------------------------------------------------------------ the prisoner (64 px cells, 8 directions)

## idle_<dir>, walk_<dir>, run_<dir>, dash_<dir>, attack_sweep_<dir>, attack_jab_<dir>, attack_slam_<dir>
static func prisoner() -> SpriteFrames:
	var frames := _empty()
	var specs: Array = [
		["idle", "prisoner_idle.png", 6, 6.0, true], ["walk", "prisoner_walk.png", 8, 9.0, true],
		["run", "prisoner_run.png", 8, 12.0, true], ["dash", "prisoner_dash.png", 8, 23.0, false],
		["attack_sweep", "prisoner_attack_sweep.png", 8, 16.0, false], ["attack_jab", "prisoner_attack_jab.png", 6, 14.0, false],
		["attack_slam", "prisoner_attack_slam.png", 8, 14.0, false], ["attack_bow", "prisoner_attack_bow.png", 8, 14.0, false],
		["hurt", "prisoner_hurt.png", 6, 16.0, false], ["death", "prisoner_death.png", 8, 10.0, false],
	]
	for spec: Array in specs:
		var tex := texture(PRISONER_SHEETS + String(spec[1]))
		if tex == null:
			continue
		for d in 8:
			add_row(frames, "%s_%s" % [spec[0], DIRS8[d]], tex, 64, d, 0, int(spec[2]), float(spec[3]), bool(spec[4]))
	return frames


# ------------------------------------------------------------------ skeletons (64 px cells, 4 directions)

## idle_<dir> (4f), move_<dir> (6f), attack_<dir> (6f), hurt_<dir> (3f), death_<dir> (8f). `sheet` is the file name
## inside the mobs folder ("skeleton_melee.png" / "skeleton_archer.png").
static func skeleton(sheet: String) -> SpriteFrames:
	var frames := _empty()
	var tex := texture(MOBS + sheet)
	if tex == null:
		return frames
	for d in 4:
		add_row(frames, "idle_%s" % DIRS4[d], tex, 64, d, 0, 4, 5.0, true)
		add_row(frames, "move_%s" % DIRS4[d], tex, 64, 4 + d, 0, 6, 8.0, true)
		add_row(frames, "attack_%s" % DIRS4[d], tex, 64, 8 + d, 0, 6, 10.0, false)
		add_row(frames, "hurt_%s" % DIRS4[d], tex, 64, 12 + d, 0, 3, 12.0, false)
		add_row(frames, "death_%s" % DIRS4[d], tex, 64, 16 + d, 0, 8, 9.0, false)
	return frames


# ------------------------------------------------------------------ the sword and its effects (64 px cells, aligned with the prisoner's)

const WEAPONS: String = "res://assets/sprites/weapons/"

## The sword is an overlay drawn in the same 64 px cell as the prisoner (so it sits on him exactly), in four views
## (down, left, right, up). Rows come in groups of four: sheathed 0-3 (4f), draw 4-7 (6f), ready 8-11 (4f),
## swing 12-15 (6f), sheathe 16-19 (8f).
static func sword() -> SpriteFrames:
	var frames := _empty()
	var tex := texture(WEAPONS + "sword_spritesheet.png")
	if tex == null:
		return frames
	for d in 4:
		var dir := DIRS4[d]
		add_row(frames, "sheathed_%s" % dir, tex, 64, d, 0, 4, 6.0, true)
		add_row(frames, "draw_%s" % dir, tex, 64, 4 + d, 0, 6, 24.0, false)
		add_row(frames, "ready_%s" % dir, tex, 64, 8 + d, 0, 4, 8.0, true)
		add_row(frames, "swing_%s" % dir, tex, 64, 12 + d, 0, 6, 24.0, false)
		add_row(frames, "sheathe_%s" % dir, tex, 64, 16 + d, 0, 8, 32.0, false)
	return frames


## Its effects, in the same cell. The sheet's arcs sweep overhead and its side views run into the cell border (cut off
## there), so the game uses the right-facing arc (row 2) and the thrust streak (row 6), ROTATES them to face wherever he
## attacks, and feathers the outer pixels so nothing ends in a hard edge. Hit sparkles: rows 8-11 (8f).
static func sword_vfx() -> SpriteFrames:
	var frames := _empty()
	var tex := texture(WEAPONS + "sword_vfx_spritesheet.png")
	if tex == null:
		return frames
	var sheet := tex.get_image()
	sheet.convert(Image.FORMAT_RGBA8)
	_feathered(frames, "arc", sheet, 2, 6, 24.0)
	_feathered(frames, "stab", sheet, 6, 6, 24.0)
	for d in 4:
		add_row(frames, "hit_%s" % DIRS4[d], tex, 64, 8 + d, 0, 8, 30.0, false)
	return frames


## `count` frames of one sheet row, with the alpha fading to nothing over the last few pixels before the cell border.
static func _feathered(frames: SpriteFrames, anim_name: String, sheet: Image, row: int, count: int, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, false)
	for i in count:
		var cell := sheet.get_region(Rect2i(i * 64, row * 64, 64, 64))
		for y in 64:
			for x in 64:
				var color := cell.get_pixel(x, y)
				if color.a <= 0.0:
					continue
				var edge := mini(mini(x, y), mini(63 - x, 63 - y))
				color.a *= clampf(float(edge) / 7.0, 0.0, 1.0)
				cell.set_pixel(x, y, color)
		frames.add_frame(anim_name, ImageTexture.create_from_image(cell))


# ------------------------------------------------------------------ the reaper NPC (64 px cells, 6 columns)

## idle 0-3 (6f)  talk 4-7 (6f)  beckon 8-11 (6f)  cast 12-15 (4f, cyan magic)  offer 16-19 (4f); rows are down, left, right, up.
static func reaper() -> SpriteFrames:
	var frames := _empty()
	var tex := texture("res://assets/sprites/character/reaperNPC/reaper_npc_spritesheet.png")
	if tex == null:
		return frames
	for d in 4:
		var dir := DIRS4[d]
		add_row(frames, "idle_%s" % dir, tex, 64, d, 0, 6, 5.0, true)
		add_row(frames, "talk_%s" % dir, tex, 64, 4 + d, 0, 6, 6.0, true)
		add_row(frames, "beckon_%s" % dir, tex, 64, 8 + d, 0, 6, 6.0, true)
		add_row(frames, "cast_%s" % dir, tex, 64, 12 + d, 0, 4, 8.0, false)
		add_row(frames, "offer_%s" % dir, tex, 64, 16 + d, 0, 4, 6.0, true)
	return frames


# ------------------------------------------------------------------ dracula, bats, the skull spirit

## Dracula (the mob at 64 px cells, the boss at 192 px cells). The mob's rows (groups of four: down, left, right, up):
##   idle 0-3 (6f)  move 4-7 (6f)  cast 8-11 (6f)  attack = claw slash 12-15 (8f)  summon bats 16-19 (8f)
##   hurt 20-23 (3f)  death row 24 (8f, no direction)
## The boss has the same first rows plus: charge 12-15 (4f), attack 16-19 (8f), summon 20-23 (8f), dissolve into bats
## 24-27 (6f), reform 28-31 (6f), big cast 41-44 (8f), hurt 57-60 (3f), death row 61 (10f).
static func dracula_mob() -> SpriteFrames:
	var frames := _empty()
	var tex := texture(MOBS + "dracula_mob.png")
	if tex == null:
		return frames
	for d in 4:
		var dir := DIRS4[d]
		add_row(frames, "idle_%s" % dir, tex, 64, d, 0, 6, 5.0, true)
		add_row(frames, "move_%s" % dir, tex, 64, 4 + d, 0, 6, 8.0, true)
		add_row(frames, "cast_%s" % dir, tex, 64, 8 + d, 0, 6, 10.0, false)
		add_row(frames, "attack_%s" % dir, tex, 64, 12 + d, 0, 8, 14.0, false)
		add_row(frames, "summon_%s" % dir, tex, 64, 16 + d, 0, 8, 10.0, false)
		add_row(frames, "hurt_%s" % dir, tex, 64, 20 + d, 0, 3, 12.0, false)
	add_row(frames, "death", tex, 64, 24, 0, 8, 9.0, false)
	return frames


static func dracula_boss() -> SpriteFrames:
	var frames := _empty()
	var tex := texture(MOBS + "dracula_boss.png")
	if tex == null:
		return frames
	for d in 4:
		var dir := DIRS4[d]
		add_row(frames, "idle_%s" % dir, tex, 192, d, 0, 6, 5.0, true)
		add_row(frames, "move_%s" % dir, tex, 192, 4 + d, 0, 6, 8.0, true)
		add_row(frames, "cast_%s" % dir, tex, 192, 8 + d, 0, 6, 10.0, false)
		add_row(frames, "charge_%s" % dir, tex, 192, 12 + d, 0, 4, 8.0, true)
		add_row(frames, "attack_%s" % dir, tex, 192, 16 + d, 0, 8, 14.0, false)
		add_row(frames, "summon_%s" % dir, tex, 192, 20 + d, 0, 8, 10.0, false)
		add_row(frames, "dissolve_%s" % dir, tex, 192, 24 + d, 0, 6, 10.0, false)
		add_row(frames, "reform_%s" % dir, tex, 192, 28 + d, 0, 6, 10.0, false)
		add_row(frames, "bigcast_%s" % dir, tex, 192, 41 + d, 0, 8, 10.0, false)
		add_row(frames, "hurt_%s" % dir, tex, 192, 57 + d, 0, 3, 12.0, false)
	add_row(frames, "death", tex, 192, 61, 0, 10, 8.0, false)
	return frames


## The bat (32 px cells): idle / move = the flying rows 0-3 (4f), attack = the swooping dash rows 4-7 (6f),
## hurt 8-11 (3f), death row 12 (5f).
static func bat() -> SpriteFrames:
	var frames := _empty()
	var tex := texture(MOBS + "bat_mob.png")
	if tex == null:
		return frames
	for d in 4:
		var dir := DIRS4[d]
		add_row(frames, "idle_%s" % dir, tex, 32, d, 0, 4, 12.0, true)
		add_row(frames, "move_%s" % dir, tex, 32, d, 0, 4, 14.0, true)
		add_row(frames, "attack_%s" % dir, tex, 32, 4 + d, 0, 6, 12.0, false)
		add_row(frames, "hurt_%s" % dir, tex, 32, 8 + d, 0, 3, 12.0, false)
	add_row(frames, "death", tex, 32, 12, 0, 5, 10.0, false)
	return frames


## The flying skull spirit (64 px cells): idle 0-3 (6f), move 4-7 (6f), attack (fireball cast) 8-11 (6f),
## hurt 12-15 (3f), death 16-19 (8f).
static func skull_spirit() -> SpriteFrames:
	var frames := _empty()
	var tex := texture(MOBS + "flying_skull_spirit.png")
	if tex == null:
		return frames
	for d in 4:
		var dir := DIRS4[d]
		add_row(frames, "idle_%s" % dir, tex, 64, d, 0, 6, 6.0, true)
		add_row(frames, "move_%s" % dir, tex, 64, 4 + d, 0, 6, 8.0, true)
		add_row(frames, "attack_%s" % dir, tex, 64, 8 + d, 0, 6, 8.0, false)
		add_row(frames, "hurt_%s" % dir, tex, 64, 12 + d, 0, 3, 12.0, false)
		add_row(frames, "death_%s" % dir, tex, 64, 16 + d, 0, 8, 10.0, false)
	return frames


# ------------------------------------------------------------------ mimics (chest: 64 px cells, boss: 224 px cells)

## Both mimic sheets share one layout (12 columns, 33 rows, 4-way rows in groups of four):
##   idle 0-3 (2f)   reveal 4-7 (8f)   taunt 8-11 (6f)   move 12-15 (6f)   bite 16-19 (8f)   lash 20-23 (12f)
##   slam 24-27 (12f)   hurt 28-31 (3f)   death row 32 (8f, no direction)
static func mimic(sheet_path: String, cell: int) -> SpriteFrames:
	var frames := _empty()
	var tex := texture(sheet_path)
	if tex == null:
		return frames
	for d in 4:
		var dir := DIRS4[d]
		add_row(frames, "idle_%s" % dir, tex, cell, d, 0, 2, 3.0, true)
		add_row(frames, "reveal_%s" % dir, tex, cell, 4 + d, 0, 8, 10.0, false)
		add_row(frames, "taunt_%s" % dir, tex, cell, 8 + d, 0, 6, 9.0, true)
		add_row(frames, "move_%s" % dir, tex, cell, 12 + d, 0, 6, 10.0, true)
		add_row(frames, "attack_%s" % dir, tex, cell, 16 + d, 0, 8, 12.0, false)
		add_row(frames, "lash_%s" % dir, tex, cell, 20 + d, 0, 12, 16.0, false)
		add_row(frames, "slam_%s" % dir, tex, cell, 24 + d, 0, 12, 14.0, false)
		add_row(frames, "hurt_%s" % dir, tex, cell, 28 + d, 0, 3, 12.0, false)
	add_row(frames, "death", tex, cell, 32, 0, 8, 9.0, false)
	return frames
