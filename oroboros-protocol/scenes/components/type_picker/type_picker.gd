class_name TypePicker
extends Control
## Small modal used by Reformat. `var t: int = await picker.choose()` -> NodeType or -1.

signal chosen(node_type: int)

@onready var _anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	z_index = 50   # overlays always draw above raised (selected / hovered) Node cards
	(%DataButton as ActionButton).activated.connect(func(_s): _pick(Enums.NodeType.DATA))
	(%IceButton as ActionButton).activated.connect(func(_s): _pick(Enums.NodeType.ICE))
	(%BreachButton as ActionButton).activated.connect(func(_s): _pick(Enums.NodeType.BREACH))
	(%CoolantButton as ActionButton).activated.connect(func(_s): _pick(Enums.NodeType.COOLANT))
	(%CancelButton as ActionButton).activated.connect(func(_s): _pick(-1))


func choose() -> int:
	_anim.play(&"show")
	var t: int = await chosen
	return t


func _pick(t: int) -> void:
	_anim.play(&"hide")
	TooltipService.hide_now()
	chosen.emit(t)
