class_name PlaceEffects
extends Node3D
## ParticleEmitter and Trail: particles from the Part (or character, or Rig) they're
## in, and a ribbon left behind as it moves. Textures come from the place's uploaded
## images (asset://...), a soft dot without one.

const MAX_PARTICLES := 600
const TRAIL_POINTS := 64

var scene: PlaceScene
var tree: PlaceTree
var _emitters := {}  # id -> CPUParticles3D
var _trails := {}  # id -> {mi: MeshInstance3D, mat, points: Array[{p, t}]}
static var _dot: Texture2D


func setup(s: PlaceScene) -> void:
	scene = s
	tree = s.tree


func has(id: String) -> bool:
	return _emitters.has(id) or _trails.has(id)


func add(id: String) -> void:
	match tree.cls(id):
		"ParticleEmitter":
			var p := CPUParticles3D.new()
			p.local_coords = false
			p.mesh = QuadMesh.new()
			add_child(p)
			_emitters[id] = p
		"Trail":
			var mi := MeshInstance3D.new()
			mi.mesh = ImmediateMesh.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_trails[id] = {"mi": mi, "mat": null, "points": []}
		_:
			return
	restyle(id)


func remove(id: String) -> void:
	if _emitters.has(id):
		_emitters[id].queue_free()
		_emitters.erase(id)
	if _trails.has(id):
		_trails[id].mi.queue_free()
		_trails.erase(id)


func restyle(id: String) -> void:
	if _emitters.has(id):
		_style_emitter(id)
	elif _trails.has(id):
		_trails[id].mat = _material(id, true)
		(_trails[id].mi as MeshInstance3D).material_override = _trails[id].mat


## Emit(n) / Clear() from a script.
func particles_op(op: Dictionary) -> void:
	var p: CPUParticles3D = _emitters.get(str(op.get("id", "")))
	if p == null:
		return
	if op.get("clear", false):
		p.restart()
		p.emitting = bool(tree.prop(str(op.id), "Enabled")) and float(tree.prop(str(op.id), "Rate")) > 0.0
		return
	# A burst: a copy that throws `n` at once and goes away when they're done.
	var burst: CPUParticles3D = p.duplicate()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = clampi(int(op.get("n", 10)), 1, 200)
	burst.emitting = false
	add_child(burst)
	burst.global_transform = _host_transform(str(op.id))
	burst.emitting = true
	get_tree().create_timer(burst.lifetime + 0.5).timeout.connect(burst.queue_free)


func _process(delta: float) -> void:
	for id in _emitters:
		_place(id, _emitters[id])
	var cam := get_viewport().get_camera_3d()
	var now := Time.get_ticks_msec() / 1000.0
	for id in _trails:
		_step_trail(id, now, cam)


# --- particles ------------------------------------------------------------------------

func _style_emitter(id: String) -> void:
	var p: CPUParticles3D = _emitters[id]
	var t := tree
	var lmin := float(t.prop(id, "LifetimeMin"))
	var lmax := maxf(float(t.prop(id, "LifetimeMax")), lmin)
	var rate := float(t.prop(id, "Rate"))
	p.lifetime = lmax
	p.lifetime_randomness = clampf(1.0 - lmin / lmax, 0.0, 1.0)
	p.amount = clampi(int(ceil(maxf(rate, 1.0) * lmax)) + 20, 1, MAX_PARTICLES)
	p.emitting = t.prop(id, "Enabled") and rate > 0.0
	p.direction = _direction(id)
	p.spread = float(t.prop(id, "SpreadAngle"))
	p.initial_velocity_min = float(t.prop(id, "SpeedMin"))
	p.initial_velocity_max = maxf(float(t.prop(id, "SpeedMax")), p.initial_velocity_min)
	p.gravity = t.prop(id, "Acceleration") as Vector3
	p.damping_min = float(t.prop(id, "Drag"))
	p.damping_max = p.damping_min
	p.angle_min = 0.0
	p.angle_max = float(t.prop(id, "Rotation"))
	p.angular_velocity_min = float(t.prop(id, "RotSpeed"))
	p.angular_velocity_max = p.angular_velocity_min
	p.local_coords = t.prop(id, "LockedToPart") == true
	# Size over life (the quad is 1 stud; scale does the rest).
	var s0 := float(t.prop(id, "Size"))
	var s1 := float(t.prop(id, "SizeEnd"))
	var top := maxf(maxf(s0, s1), 0.001)
	p.scale_amount_min = top
	p.scale_amount_max = top
	var curve := Curve.new()
	curve.add_point(Vector2(0, s0 / top))
	curve.add_point(Vector2(1, s1 / top))
	p.scale_amount_curve = curve
	# Color and fade over life.
	var g := Gradient.new()
	var c0: Color = t.prop(id, "Color")
	var c1: Color = t.prop(id, "ColorEnd")
	c0.a = 1.0 - float(t.prop(id, "Transparency"))
	c1.a = 1.0 - float(t.prop(id, "TransparencyEnd"))
	g.set_color(0, c0)
	g.set_color(1, c1)
	p.color_ramp = g
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	match str(t.prop(id, "Shape")):
		"Box":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = _host_size(id) / 2.0
		"Sphere":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			var sz := _host_size(id)
			p.emission_sphere_radius = maxf(sz.x, maxf(sz.y, sz.z)) / 2.0
	(p.mesh as QuadMesh).material = _material(id, false)


func _direction(id: String) -> Vector3:
	return {"Top": Vector3.UP, "Bottom": Vector3.DOWN, "Front": Vector3.FORWARD, "Back": Vector3.BACK,
		"Left": Vector3.LEFT, "Right": Vector3.RIGHT}.get(str(tree.prop(id, "EmitDirection")), Vector3.UP)


func _place(id: String, p: CPUParticles3D) -> void:
	var t := _host_transform(id)
	p.global_transform = t
	p.visible = true


# --- trails ---------------------------------------------------------------------------

func _step_trail(id: String, now: float, cam: Camera3D) -> void:
	var e: Dictionary = _trails[id]
	var t := tree
	var life := float(t.prop(id, "Lifetime"))
	var pts: Array = e.points
	if t.prop(id, "Enabled"):
		var at: Vector3 = _host_transform(id) * (t.prop(id, "Offset") as Vector3)
		if pts.is_empty() or (pts[-1].p as Vector3).distance_to(at) > 0.05:
			pts.append({"p": at, "t": now})
	while not pts.is_empty() and now - float(pts[0].t) > life:
		pts.pop_front()
	while pts.size() > TRAIL_POINTS:
		pts.pop_front()
	var im: ImmediateMesh = e.mi.mesh
	im.clear_surfaces()
	if pts.size() < 2 or cam == null:
		return
	var w0 := float(t.prop(id, "Width"))
	var w1 := float(t.prop(id, "WidthEnd"))
	var c0: Color = t.prop(id, "Color")
	var c1: Color = t.prop(id, "ColorEnd")
	var a0 := 1.0 - float(t.prop(id, "Transparency"))
	var a1 := 1.0 - float(t.prop(id, "TransparencyEnd"))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, e.mat)
	for i in pts.size():
		var p: Vector3 = pts[i].p
		var age := clampf((now - float(pts[i].t)) / life, 0.0, 1.0)
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)].p
		var prv: Vector3 = pts[maxi(i - 1, 0)].p
		var along := (nxt - prv).normalized()
		var side := along.cross(cam.global_position - p).normalized() * lerpf(w1, w0, 1.0 - age) * 0.5
		var col := c0.lerp(c1, age)
		col.a = lerpf(a0, a1, age)
		im.surface_set_color(col)
		im.surface_set_uv(Vector2(age, 0))
		im.surface_add_vertex(p - side)
		im.surface_set_color(col)
		im.surface_set_uv(Vector2(age, 1))
		im.surface_add_vertex(p + side)
	im.surface_end()


# --- shared ---------------------------------------------------------------------------

## Where an effect sits: its Part, a character's or Rig's Melly, or the first part of a Model.
func _host_transform(id: String) -> Transform3D:
	var host := tree.parent_of(id)
	var av: Node = scene.avatar_for(host)
	if av and av is Node3D:
		return Transform3D((av as Node3D).global_transform.basis.orthonormalized(), (av as Node3D).global_position + Vector3(0, 1.3, 0))
	var m := scene.mesh_of(host)
	if m:
		return Transform3D(m.global_transform.basis.orthonormalized(), m.global_position)
	for d in tree.descendants(host):
		var dm := scene.mesh_of(d)
		if dm:
			return Transform3D(dm.global_transform.basis.orthonormalized(), dm.global_position)
	return Transform3D()


func _host_size(id: String) -> Vector3:
	var host := tree.parent_of(id)
	var s: Variant = tree.prop(host, "Size") if tree.has(host) else null
	return s if s is Vector3 else Vector3(2, 2, 2)


func _material(id: String, ribbon: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if not ribbon:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if float(tree.prop(id, "LightEmission")) >= 0.5:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var ref := str(tree.prop(id, "Texture"))
	if ref != "":
		AssetCache.fetch(ref, func(tex: Texture2D):
			if tex and has(id):
				m.albedo_texture = tex)
	elif not ribbon:
		m.albedo_texture = _soft_dot()
	return m


static func _soft_dot() -> Texture2D:
	if _dot == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d * d, 0.0, 1.0)))
		_dot = ImageTexture.create_from_image(img)
	return _dot
