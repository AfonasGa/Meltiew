extends Node
## Plays a .melt offline (like Studio's Test: your scripts in a local VM, you alone)
## and saves a screenshot after a few seconds. For checking engine features by eye.
##   godot --path . res://tools/play_test.tscn -- --melt=/path/place.melt --out=/tmp/shot.png --wait=5

var shooter := false
var _out := "/tmp/play_test.png"
var _wait := 5.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--wait="):
			_wait = float(a.trim_prefix("--wait="))
	if shooter:
		_shoot.call_deferred()
		return
	var melt_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--melt="):
			melt_path = a.trim_prefix("--melt=")
	var melt: Variant = JSON.parse_string(FileAccess.get_file_as_string(melt_path))
	if not melt is Dictionary:
		printerr("play_test: no place at ", melt_path)
		get_tree().quit(1)
		return
	Session.user = {"id": 1, "username": "tester", "display_name": "Tester", "birthdate": "2000-01-01", "colors": Session.DEFAULT_COLORS, "face": ":D", "accessories": []}
	Session.test_melt = melt
	Session.pending_game = "test"
	Session.pending_server = "auto"
	# Something that outlives the scene change takes the picture.
	var s: Node = load("res://tools/play_test.gd").new()
	s.shooter = true
	s.name = "PlayTestShooter"
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _shoot() -> void:
	await get_tree().create_timer(_wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out)
	print("saved ", _out)
	get_tree().quit()
