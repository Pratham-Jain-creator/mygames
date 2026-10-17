class_name Deck
extends RefCounted
## The 52-node deck. `all_nodes` is the permanent collection; draw / discard
## piles are rebuilt at the start of every Server.

var all_nodes: Array = []
var draw_pile: Array = []
var discard_pile: Array = []


func build_standard() -> void:
	all_nodes.clear()
	for t in [Enums.NodeType.DATA, Enums.NodeType.ICE, Enums.NodeType.BREACH, Enums.NodeType.COOLANT]:
		for v in range(2, 15):
			all_nodes.append(NodeData.new(t, v))


func start_server() -> void:
	for n: NodeData in all_nodes:
		n.spent_hidden = false
	draw_pile = all_nodes.duplicate()
	draw_pile.shuffle()
	discard_pile.clear()


## Draws up to n nodes. No mid-server reshuffle: an empty draw pile means the deck is exhausted.
func draw(n: int) -> Array:
	var out: Array = []
	for i in n:
		if draw_pile.is_empty():
			break
		out.append(draw_pile.pop_back())
	return out


## Tutorial: forces the draw order. `spec` is [[type, value], ...]; spec[0] is drawn first.
func stack_top(spec: Array) -> void:
	for i in range(spec.size() - 1, -1, -1):
		var want: Array = spec[i]
		for n in draw_pile:
			if n.type == int(want[0]) and n.base_value == int(want[1]):
				draw_pile.erase(n)
				draw_pile.append(n)
				break


## Index 0 is the bottom, the back of the array is the top.
func put_bottom(nodes: Array) -> void:
	for n in nodes:
		draw_pile.push_front(n)


func put_top(node: NodeData) -> void:
	draw_pile.append(node)


func discard(nodes: Array) -> void:
	for n in nodes:
		if not n.temporary:
			discard_pile.append(n)


func add_node(node: NodeData, into_draw_pile := false) -> void:
	all_nodes.append(node)
	if into_draw_pile:
		draw_pile.insert(randi() % (draw_pile.size() + 1), node)


func remove_node(node: NodeData) -> void:
	all_nodes.erase(node)
	draw_pile.erase(node)
	discard_pile.erase(node)


func size() -> int:
	return all_nodes.size()


func remaining_counts() -> Dictionary:
	var c := {
		Enums.NodeType.DATA: 0, Enums.NodeType.ICE: 0,
		Enums.NodeType.BREACH: 0, Enums.NodeType.COOLANT: 0,
	}
	for n in draw_pile:
		c[n.type] += 1
	return c
