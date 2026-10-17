class_name Bat
extends EnemyBase
## A small fast flying bat (sprites: bat_mob.png). It weaves toward you and swoops in a quick bite. Dracula and his
## minions summon them: use Bat.summon().

const SCENE_PATH: String = "res://scenes/enemies/bat.tscn"

var _clock: float = 0.0


## Calls `count` bats out of nowhere around a point. `as_minion` ones also count as boss minions (they crumble when the
## boss dies). Returns them.
static func summon(host: Node, center: Vector2, count: int, health_mult: float, damage_mult: float, as_minion: bool) -> Array[Bat]:
	var result: Array[Bat] = []
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null or host == null:
		return result
	for i in count:
		var bat := scene.instantiate() as Bat
		bat.health_multiplier = health_mult
		bat.damage_multiplier = damage_mult
		if as_minion:
			bat.add_to_group("boss_minion")
		host.add_child(bat)
		bat.global_position = center + Vector2.from_angle(TAU * float(i) / float(maxi(count, 1)) + randf()) * randf_range(14.0, 26.0)
		bat.wake_up()
		result.append(bat)
	return result


func _ready() -> void:
	super()
	_clock = randf() * TAU


## Bats never walk straight: they weave from side to side as they come.
func _update_chase(delta: float) -> void:
	super(delta)
	_clock += delta
	if state == State.CHASE and velocity.length() > 1.0:
		velocity += velocity.orthogonal().normalized() * sin(_clock * 7.0) * move_speed * 0.7
