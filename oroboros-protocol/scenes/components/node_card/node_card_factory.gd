class_name NodeCardFactory
extends RefCounted
## Spawns the correct NodeCard variant for a NodeData. Compact cards (stash,
## deck viewer) are scaled copies wrapped in a plain Control so Containers lay
## them out at their visual size.

const SCENES := {
	Enums.NodeType.DATA: preload("res://scenes/components/node_card/variants/data_cache_card.tscn"),
	Enums.NodeType.ICE: preload("res://scenes/components/node_card/variants/ice_card.tscn"),
	Enums.NodeType.BREACH: preload("res://scenes/components/node_card/variants/breach_card.tscn"),
	Enums.NodeType.COOLANT: preload("res://scenes/components/node_card/variants/coolant_card.tscn"),
}
const CARD_SIZE := Vector2(160, 227)   # portrait body of the PNG frames (480x680 art px / 3)


## Adds a card for `data` to `parent` and returns it.
## `card_scale` != 1 wraps the card in a Control sized to its visual size.
static func spawn(parent: Node, data: NodeData, card_scale := 1.0) -> NodeCard:
	var card: NodeCard = SCENES[data.type].instantiate()
	if absf(card_scale - 1.0) > 0.001:
		var wrap := Control.new()
		wrap.custom_minimum_size = CARD_SIZE * card_scale
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(wrap)
		wrap.add_child(card)
		card.scale = Vector2(card_scale, card_scale)
		card.set_meta("wrapper", wrap)
	else:
		parent.add_child(card)
	card.idle_enabled = card_scale >= 0.999
	card.bind(data)
	return card


static func dispose(card: NodeCard) -> void:
	if not is_instance_valid(card):
		return
	if card.has_meta("wrapper"):
		var w: Node = card.get_meta("wrapper")
		if is_instance_valid(w):
			w.queue_free()
			return
	card.queue_free()
