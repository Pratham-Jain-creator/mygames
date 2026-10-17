extends Node
var _f: FileAccess
func _p(t: String) -> void:
	_f.store_line(t)
	_f.flush()
func _ready() -> void:
	_f = FileAccess.open("res://tools/probe/blind_probe.log", FileAccess.WRITE)
	RunState.start_new_run()
	RunState.add_daemon("blind_trust")
	ServerLogic.begin_server()
	for t in 5:
		var d := ServerLogic.deal_room()
		var fd := 0
		for n: NodeData in d.room:
			if n.face_down:
				fd += 1
		_p("turn %d room=%d facedown=%d (expect 1)" % [t, d.room.size(), fd])
		RunState.deck.discard(d.room)
		RunState.server.stash = []
	_p("DONE")
	get_tree().quit()
