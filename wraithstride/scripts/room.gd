extends Node3D
## Room logic. Switches and doors inside the room register themselves here.
## When every switch is pressed the doors open. Killing enemies is never required.

signal solved

var switches: Array = []
var doors: Array = []
var pressed := 0


func register_switch(s: Node) -> void:
	switches.append(s)


func register_door(d: Node) -> void:
	doors.append(d)


func _ready() -> void:
	# Rooms with a door but no switch (pure parkour gauntlets) open on arrival at the far end.
	if switches.is_empty():
		call_deferred("_open_all")


func switch_pressed(_s: Node) -> void:
	pressed += 1
	if pressed >= switches.size():
		_open_all()
		Game.message.emit("GATE OPEN")
	else:
		Game.message.emit("SEAL %d / %d" % [pressed, switches.size()])


func _open_all() -> void:
	for d in doors:
		d.open()
	solved.emit()


## Used when a solved room is streamed back in.
func force_open() -> void:
	for s in switches:
		s.done = true
	for d in doors:
		d.open()
