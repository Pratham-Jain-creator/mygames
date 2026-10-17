extends Node
## Probe: Ghost Write ghost copies and Second Look (peek) Eject return.

var _f: FileAccess


func _p(t: String) -> void:
	_f.store_line(t)
	_f.flush()


func _ready() -> void:
	_f = FileAccess.open("res://tools/probe/rework_probe.log", FileAccess.WRITE)
	RunState.start_new_run()
	RunState.add_daemon("glitch")
	RunState.add_daemon("peek")
	RunState.money = 50
	ServerLogic.begin_server()
	var d := ServerLogic.deal_room()
	var before := RunState.deck.draw_pile.size()
	_p("draw before eject=%d room=%d" % [before, d.room.size()])
	ServerLogic.flee()
	_p("draw after eject=%d discard=%d (expect +4 and 0)" % [RunState.deck.draw_pile.size(), RunState.deck.discard_pile.size()])
	var d2 := ServerLogic.deal_room()
	var room: Array = d2.room.duplicate()
	var left_node: NodeData = null
	for n in room:
		if n.type == Enums.NodeType.DATA:
			left_node = n
	if left_node == null:
		left_node = room[0]
		left_node.type = Enums.NodeType.DATA
	var sel: Array = room.filter(func(n): return n != left_node)
	var v: int = left_node.eff_value
	TurnResolver.resolve(sel.slice(0, 3), [left_node])
	var top: NodeData = RunState.deck.draw_pile.back()
	_p("stashed siphon v=%d top temp=%s type=%d value=%d" % [v, str(top.temporary), top.type, top.base_value])
	_p("DONE")
	get_tree().quit()
