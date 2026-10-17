extends Node2D
## A group of spike tiles laid out in a pattern, with choreographed timing. Each pattern is just
## a scene of this script with different `offsets` and `mode`, so adding a new trap shape means
## duplicating a scene in scenes/props/traps/ and editing two values.
##
## Modes:
##   SYNC       every spike fires together (a solid block you must not stand on)
##   ALTERNATE  checkerboard: two groups take turns (find the safe tiles)
##   SWEEP      spikes fire one after another in list order (a travelling wave / rotating ring)
##   RANDOM     every spike on its own random timing

enum Mode { SYNC, ALTERNATE, SWEEP, RANDOM }

const TILE_PX: float = 16.0
## Length of one full spike cycle (hidden + warning + active + lowering of the default tile).
const CYCLE: float = 3.65

@export var tile_scene: PackedScene = preload("res://scenes/props/spike_trap.tscn")
## Tile offsets from this node's origin, in tiles (x right, y down).
@export var offsets: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
@export var mode: Mode = Mode.SYNC
## SWEEP only: seconds between neighbouring spikes.
@export var sweep_delay: float = 0.22


## World positions of every tile for a given origin (used to check the pattern fits on free floor).
func get_tile_positions(origin: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for offset in offsets:
		result.append(origin + offset * TILE_PX)
	return result


func _ready() -> void:
	var base := randf() * 2.0 # random start so patterns in one room don't pulse together
	for i in offsets.size():
		var tile := tile_scene.instantiate()
		tile.position = offsets[i] * TILE_PX
		tile.randomize_start = false
		tile.start_offset = fposmod(base + _delay_for(i), CYCLE)
		add_child(tile)


func _delay_for(index: int) -> float:
	match mode:
		Mode.ALTERNATE:
			var cell := Vector2i(offsets[index])
			return CYCLE * 0.5 * float((cell.x + cell.y) & 1)
		Mode.SWEEP:
			return sweep_delay * float(index)
		Mode.RANDOM:
			return randf() * CYCLE
	return 0.0
