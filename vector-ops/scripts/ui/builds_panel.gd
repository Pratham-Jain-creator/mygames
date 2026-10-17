class_name BuildsPanel
extends VBoxContainer
## "My builds" list (scenes/ui/builds_panel.tscn): save the current loadout under a
## name, load or delete saved builds. The list itself lives in
## GameState.saved_builds and is written to disk through SaveData.

signal save_requested(build_name: String)
signal load_requested(sel: Array)

const ROW_SCENE := preload("res://scenes/ui/build_row.tscn")
const MAX_BUILDS := 24

var _active: Array = []


func _ready() -> void:
	%BtnSave.pressed.connect(_on_save_pressed)
	%NameInput.text_submitted.connect(func(_t: String) -> void: _on_save_pressed())
	refresh()


func _on_save_pressed() -> void:
	var n: String = %NameInput.text.strip_edges()
	if n == "":
		n = "Build %d" % (GameState.saved_builds.size() + 1)
	save_requested.emit(n)
	%NameInput.clear()


## Stores (or overwrites, if the name exists) a build and refreshes the list.
func add_build(build_name: String, sel: Array) -> void:
	var clean: Array = Loadout.sanitize(sel)
	for b in GameState.saved_builds:
		if String(b["name"]).to_lower() == build_name.to_lower():
			b["name"] = build_name
			b["sel"] = clean
			SaveData.save_all()
			refresh()
			return
	if GameState.saved_builds.size() >= MAX_BUILDS:
		%NameInput.placeholder_text = "Build list full (%d) - delete one first" % MAX_BUILDS
		return
	%NameInput.placeholder_text = "Name this build"
	GameState.saved_builds.append({"name": build_name, "sel": clean})
	SaveData.save_all()
	refresh()


## Marks the saved build equal to this selection (if any).
func set_active(sel: Array) -> void:
	_active = sel
	for row in %List.get_children():
		(row as BuildRow).set_active((row as BuildRow).sel == sel)


func refresh() -> void:
	for c in %List.get_children():
		%List.remove_child(c)
		c.queue_free()
	for i in GameState.saved_builds.size():
		var b: Dictionary = GameState.saved_builds[i]
		var row: BuildRow = ROW_SCENE.instantiate()
		%List.add_child(row)
		row.setup(b["name"], b["sel"])
		row.load_pressed.connect(func() -> void: load_requested.emit(row.sel))
		row.delete_pressed.connect(_on_delete.bind(i))
	%EmptyLabel.visible = GameState.saved_builds.is_empty()
	set_active(_active)


func _on_delete(index: int) -> void:
	if index < GameState.saved_builds.size():
		GameState.saved_builds.remove_at(index)
		SaveData.save_all()
		refresh()
