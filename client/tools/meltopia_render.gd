extends Node
## Meltopia's pictures, rendered with the game's own Melly avatar:
##   killer / survivor   4:3 inventory pictures (nrz with the censor square, Melly running)
##   cover_wide          16:9 place cover (both of them under the red moon, with the title)
##   cover_square        1:1 place icon (the censor square on the moon)
##
## Run from the client folder (the window size is the picture size):
##   godot --path . res://tools/meltopia_render.tscn --resolution 1200x900 -- --what=killer --out=/tmp/killer.png
##   godot --path . res://tools/meltopia_render.tscn --resolution 1920x1080 -- --what=cover_wide --out=/tmp/cover.png
## --look=<file> takes nrz's look (JSON from https://meltiew.narez.xyz/api/users/nrz/look);
## by default it's examples/meltopia/nrz_look.json. --pose=<seconds> picks the animation frame.

var _look_path := "res://../examples/meltopia/nrz_look.json"
var _out := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var what := "killer"
	var pose := 0.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--what="):
			what = a.trim_prefix("--what=")
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--look="):
			_look_path = a.trim_prefix("--look=")
		elif a.begins_with("--pose="):
			pose = float(a.trim_prefix("--pose="))
	if _out == "":
		_out = OS.get_executable_path().get_base_dir().path_join(what + ".png")
	if what.begins_with("cover_"):
		await _place_cover(what.trim_prefix("cover_"))
	else:
		await _char_render(what, pose)
	get_tree().quit()


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _save(_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out)
	print("saved ", _out)


func _mat(c: Color, rough := 0.8, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _box(root: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	root.add_child(mi)
	return mi


func _light(root: Node3D, pos: Vector3, c: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = true
	root.add_child(l)


## 4:3 inventory pictures of the Meltopia characters: nrz (the killer) and Melly.
func _char_render(which: String, pose: float) -> void:
	var killer := which == "killer"
	var root := Node3D.new()
	get_tree().root.add_child(root)
	if get_tree().current_scene and get_tree().current_scene != self:
		get_tree().current_scene.queue_free()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0b0610") if killer else Color("#070d1c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#3a2030") if killer else Color("#27345c")
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color("#3a0d18") if killer else Color("#1a2744")
	env.fog_density = 0.035
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	# Ground, moon, pines.
	_box(root, Vector3(80, 0.2, 80), Vector3(0, -0.1, 0), _mat(Color("#141019") if killer else Color("#0f1522"), 0.75))
	var moon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 5.0
	sm.height = 10.0
	moon.mesh = sm
	moon.material_override = _mat(Color("#ff3355") if killer else Color("#dfe8ff"), 1.0, 3.0 if killer else 2.2)
	moon.position = Vector3(6, 10, -38)
	root.add_child(moon)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pine := _mat(Color("#07050a") if killer else Color("#060a14"), 1.0)
	for i in 26:
		var x := rng.randf_range(-22, 22)
		var z := rng.randf_range(-26, -7)
		if absf(x) < 3.5 and z > -12:
			continue
		var h := rng.randf_range(6, 12)
		_box(root, Vector3(0.4, h * 0.3, 0.4), Vector3(x, h * 0.15, z), pine)
		for k in 3:
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = h * (0.26 - k * 0.06)
			cm.height = h * 0.42
			cm.radial_segments = 7
			cone.mesh = cm
			cone.material_override = pine
			cone.position = Vector3(x, h * (0.38 + k * 0.2), z)
			root.add_child(cone)
	var av := MellyAvatar.new()
	root.add_child(av)
	await get_tree().process_frame
	await get_tree().process_frame
	if killer:
		var look: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_look_path))
		av.apply_user(look)
		av.rotation_degrees.y = 180 - 24
		av.restart("idle")

		# Spikes stuck in the ground around, glowing.
		var spike := _mat(Color("#ff3b4f"), 0.4, 4.0)
		for sp in [[Vector3(-1.9, 0.5, 0.6), Vector3(20, 0, -14)], [Vector3(2.1, 0.45, -0.8), Vector3(-16, 30, 18)], [Vector3(-0.9, 0.4, -2.3), Vector3(12, 60, 8)]]:
			_box(root, Vector3(0.09, 1.1, 0.09), sp[0], spike, sp[1])
		_light(root, Vector3(-1.8, 2.8, -1.8), Color("#ff2a48"), 6.0, 6.0)
		_light(root, Vector3(2.2, 2.2, -1.6), Color("#ff5a3d"), 2.5, 5.0)
		_light(root, Vector3(1.6, 2.4, 3.6), Color("#e8ecff"), 1.8, 10.0)
	else:
		av.apply_user({"colors": {"head": "#f5f1ec", "torso": "#baa4e2", "arm_l": "#f5f1ec", "arm_r": "#f5f1ec", "leg_l": "#302d38", "leg_r": "#302d38"}, "face": ":O", "accessories": []})
		av.rotation_degrees.y = 180 + 28
		av.restart("run")
		# A generator behind her, humming, two bulbs on.
		var gen := Node3D.new()
		gen.position = Vector3(-2.6, 0, -2.8)
		gen.rotation_degrees.y = 30
		root.add_child(gen)
		_box(gen, Vector3(1.8, 1.3, 1.1), Vector3(0, 0.65, 0), _mat(Color("#2c3a4a"), 0.5))
		_box(gen, Vector3(1.9, 0.16, 1.2), Vector3(0, 1.36, 0), _mat(Color("#e0b43a"), 0.6))
		for b in 3:
			_box(gen, Vector3(0.18, 0.18, 0.05), Vector3(-0.45 + b * 0.45, 0.95, 0.57), _mat(Color("#6bffa8") if b < 2 else Color("#3a1f24"), 0.3, 5.0 if b < 2 else 0.0))
		_light(root, Vector3(-2.2, 1.4, -1.9), Color("#ffcf5a"), 3.5, 6.0)
		_light(root, Vector3(2.4, 2.4, -2.2), Color("#7ee0c3"), 5.0, 6.0)
		_light(root, Vector3(0.6, 2.4, 3.4), Color("#9fb4ff"), 0.7, 10.0)
		# A flashlight beam from off screen.
		var spot := SpotLight3D.new()
		spot.position = Vector3(3.5, 3.0, 4.0)
		spot.light_color = Color("#fff4d6")
		spot.light_energy = 2.2
		spot.spot_range = 12.0
		spot.spot_angle = 18.0
		spot.shadow_enabled = true
		root.add_child(spot)
		spot.look_at(Vector3(0, 1.1, 0))
	var cam := Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	cam.position = Vector3(1.1, 0.45, 4.6) if killer else Vector3(-0.8, 1.1, 4.4)
	cam.look_at(Vector3(0.1, 1.2, 0) if killer else Vector3(-0.35, 1.0, 0))
	cam.current = true
	await wait(pose)
	if av.anim_player:
		av.anim_player.pause()
	if killer:
		# A spike in his hand, pointing down and out.
		var hp: Vector3 = av.hand_r().global_position
		_box(root, Vector3(0.08, 1.25, 0.08), hp + Vector3(-0.12, -0.38, 0.12), _mat(Color("#ff3b4f"), 0.4, 6.0), Vector3(20, 0, -24))
	if killer and not OS.get_cmdline_user_args().has("--nocensor"):
		var l := Label3D.new()
		l.text = "\u25a0"
		l.font = UI.font_black
		l.font_size = 92
		l.pixel_size = 0.01
		l.modulate = Color.BLACK
		l.outline_modulate = Color.BLACK
		l.outline_size = 15
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.double_sided = true
		root.add_child(l)
		var at := av.head_center()
		l.global_position = at + (cam.global_position - at).normalized() * 0.55
	await wait(0.4)
	await _save(which)


func _pines(root: Node3D, m: Material, seed_: int, zmin: float, zmax: float, spread: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for i in 34:
		var x := rng.randf_range(-spread, spread)
		var z := rng.randf_range(zmin, zmax)
		var h := rng.randf_range(6, 13)
		_box(root, Vector3(0.4, h * 0.3, 0.4), Vector3(x, h * 0.15, z), m)
		for k in 3:
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = h * (0.26 - k * 0.06)
			cm.height = h * 0.42
			cm.radial_segments = 7
			cone.mesh = cm
			cone.material_override = m
			cone.position = Vector3(x, h * (0.38 + k * 0.2), z)
			root.add_child(cone)


func _censor(root: Node3D, av: MellyAvatar, cam: Camera3D) -> void:
	var l := Label3D.new()
	l.text = "\u25a0"
	l.font = UI.font_black
	l.font_size = 92
	l.pixel_size = 0.01
	l.modulate = Color.BLACK
	l.outline_modulate = Color.BLACK
	l.outline_size = 15
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(l)
	var at := av.head_center()
	l.global_position = at + (cam.global_position - at).normalized() * 0.55


## Meltopia's place covers: 16:9 (lists, place page) and a square icon.
func _place_cover(kind: String) -> void:
	var wide := kind == "wide"
	var root := Node3D.new()
	get_tree().root.add_child(root)
	if get_tree().current_scene and get_tree().current_scene != self:
		get_tree().current_scene.queue_free()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0a0612")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#34304e")
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color("#2a0f24")
	env.fog_density = 0.03
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	_box(root, Vector3(90, 0.2, 90), Vector3(0, -0.1, 0), _mat(Color("#120e1a"), 0.75))
	var moon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 6.0
	sm.height = 12.0
	moon.mesh = sm
	moon.material_override = _mat(Color("#ff3355"), 1.0, 3.0)
	moon.position = Vector3(-9, 11, -40) if wide else Vector3(-0.95, 2.95, -8.5)
	if not wide:
		sm.radius = 1.9
		sm.height = 3.8
	root.add_child(moon)
	_pines(root, _mat(Color("#07050b"), 1.0), 11, -30, -9, 30)
	var killer := MellyAvatar.new()
	root.add_child(killer)
	var melly: MellyAvatar = null
	if wide:
		melly = MellyAvatar.new()
		root.add_child(melly)
	await get_tree().process_frame
	await get_tree().process_frame
	var look: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_look_path))
	killer.apply_user(look)
	killer.restart("idle")
	var cam := Camera3D.new()
	root.add_child(cam)
	var spike := _mat(Color("#ff3b4f"), 0.4, 6.0)
	if wide:
		killer.position = Vector3(-1.9, 0, -2.2)
		killer.rotation_degrees.y = 180 - 10
		melly.apply_user({"colors": {"head": "#f5f1ec", "torso": "#baa4e2", "arm_l": "#f5f1ec", "arm_r": "#f5f1ec", "leg_l": "#302d38", "leg_r": "#302d38"}, "face": ":O", "accessories": []})
		melly.position = Vector3(1.3, 0, 0.6)
		melly.rotation_degrees.y = 180 + 40
		melly.restart("run")
		for sp in [[Vector3(-3.6, 0.45, -1.2), Vector3(18, 0, -14)], [Vector3(0.2, 0.4, -1.6), Vector3(-14, 30, 16)], [Vector3(3.4, 0.4, -2.6), Vector3(10, 60, 8)]]:
			_box(root, Vector3(0.08, 1.1, 0.08), sp[0], spike, sp[1])
		_light(root, Vector3(-3.4, 2.8, -3.8), Color("#ff2a48"), 7.0, 7.0)
		_light(root, Vector3(-0.4, 2.2, -3.2), Color("#ff5a3d"), 2.5, 5.0)
		_light(root, Vector3(3.2, 2.6, -1.0), Color("#7ee0c3"), 5.0, 6.0)
		_light(root, Vector3(0.6, 2.6, 4.2), Color("#c9d2ff"), 1.6, 12.0)
		cam.fov = 40
		cam.position = Vector3(0.2, 1.0, 5.4)
		cam.look_at(Vector3(0.0, 1.35, -0.5))
	else:
		killer.rotation_degrees.y = 180 - 18
		_box(root, Vector3(0.08, 1.1, 0.08), Vector3(-1.6, 0.4, -0.8), spike, Vector3(18, 0, -14))
		_box(root, Vector3(0.08, 1.1, 0.08), Vector3(1.7, 0.4, -1.2), spike, Vector3(-14, 30, 16))
		_light(root, Vector3(-1.8, 2.8, -1.8), Color("#ff2a48"), 6.0, 6.0)
		_light(root, Vector3(2.0, 2.4, -1.6), Color("#ff5a3d"), 3.0, 5.0)
		_light(root, Vector3(1.2, 2.2, 3.4), Color("#e8ecff"), 1.6, 10.0)
		cam.fov = 34
		cam.position = Vector3(0.5, 0.9, 4.6)
		cam.look_at(Vector3(0.05, 1.15, 0))
	cam.current = true
	await wait(0.5)
	killer.anim_player.pause()
	if melly:
		melly.anim_player.pause()
	var hp: Vector3 = killer.hand_r().global_position
	_box(root, Vector3(0.08, 1.25, 0.08), hp + Vector3(-0.12, -0.38, 0.12), spike, Vector3(20, 0, -24))
	_censor(root, killer, cam)
	# The title.
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var vp := get_viewport().get_visible_rect().size
	var title := Label.new()
	title.text = "MELTOPIA"
	title.add_theme_font_override("font", UI.font_black)
	title.add_theme_font_size_override("font_size", int(vp.y * (0.17 if wide else 0.15)))
	title.add_theme_color_override("font_color", Color("#fff4f6"))
	title.add_theme_color_override("font_outline_color", Color("#c8102e"))
	title.add_theme_constant_override("outline_size", int(vp.y * 0.03))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", int(vp.y * 0.012))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vp.x, vp.y * 0.26)
	title.position = Vector2(0, vp.y * (0.04 if wide else 0.7))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(title)
	await wait(0.4)
	await _save("cover_" + kind)
