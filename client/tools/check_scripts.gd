extends Node
## Loads every GDScript in the project and reports the ones that don't compile.
## A scene (not -s) so the autoloads the scripts use are there:
##   godot --headless --path . res://tools/check_scripts.tscn


func _ready() -> void:
	var bad := 0
	for path in _scripts("res://"):
		var s: Script = load(path)
		if s == null or not s.can_instantiate():
			printerr("FAILED ", path)
			bad += 1
	print("checked, %d failed" % bad)
	get_tree().quit(1 if bad else 0)


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with(".") and d != "android" and d != "export":
			out.append_array(_scripts(dir.path_join(d)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
