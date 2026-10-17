extends Node
## Probe: Glitch damage forecast follows pick order and the Firewall switch.

var _lines: Array = []


func _log(m: String) -> void:
	_lines.append(m)
	var f := FileAccess.open("res://tools/probe/forecast_probe.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))


func _n(t: int, v: int) -> NodeData:
	return NodeData.new(t, v)


func _ready() -> void:
	RunState.start_new_run()
	ServerLogic.begin_server()
	var B := Enums.NodeType.BREACH
	var I := Enums.NodeType.ICE
	var D := Enums.NodeType.DATA
	var fw := _n(B, 10)
	var g9 := _n(I, 9)
	var g7 := _n(I, 7)
	var si := _n(D, 5)
	var sv := RunState.server
	sv.room = [fw, g9, g7, si]
	var f1 := ServerLogic.glitch_forecast([fw, g9, g7], sv.room)
	_log("FW10,G9,G7  -> G9 %s  G7 %s (expect 0 / 0)" % [f1[g9.uid], f1[g7.uid]])
	var f2 := ServerLogic.glitch_forecast([g9, fw, g7], sv.room)
	_log("G9,FW10,G7  -> G9 %s  G7 %s (expect raw 9 / 0)" % [f2[g9.uid], f2[g7.uid]])
	var f3 := ServerLogic.glitch_forecast([], sv.room)
	_log("none        -> G9 %s  G7 %s (expect raw 9 / raw 7)" % [f3[g9.uid], f3[g7.uid]])
	sv.weapon_enabled = false
	var f4 := ServerLogic.glitch_forecast([fw, g9, g7], sv.room)
	_log("FIREWALL OFF FW10,G9,G7 -> G9 %s  G7 %s (expect raw 9 / raw 7)" % [f4[g9.uid], f4[g7.uid]])
	sv.weapon_enabled = true
	var g8 := _n(I, 8)
	var g6 := _n(I, 6)
	var f5 := ServerLogic.glitch_forecast([fw, g9, g8, g6], [fw, g9, g8, g6])
	_log("FW10,G9,G8,G6 -> G9 %s G8 %s G6 %s (ceiling 8 then 7: expect 0 / raw 8 / 0)" % [f5[g9.uid], f5[g8.uid], f5[g6.uid]])
	_log("DONE")
	get_tree().quit()
