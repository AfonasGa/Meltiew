class_name PlaceHighlights
extends RefCounted
## Highlight objects: a tint and an outline on everything drawn for what the Highlight
## is inside (a Part, a Model with its parts, a player's character, a Rig). With
## DepthMode AlwaysOnTop both show through walls. Done with an overlay material on
## those meshes, refreshed a few times a second (models and characters change).

const REFRESH := 0.2

const FILL_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never%s;
uniform vec4 fill : source_color;
void fragment() {
	ALBEDO = fill.rgb;
	ALPHA = fill.a;
}
"""

const LINE_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_front, depth_draw_never%s;
uniform vec4 line : source_color;
uniform float grow = 0.05;
void vertex() {
	VERTEX += NORMAL * grow;
}
void fragment() {
	ALBEDO = line.rgb;
	ALPHA = line.a;
}
"""

static var _shaders := {}

var scene: Node  # PlaceScene
var _items := {}  # Highlight id -> {mat, meshes: Array}
var _clock := 0.0


func _init(s: Node) -> void:
	scene = s


func has_any() -> bool:
	return not _items.is_empty()


func add(id: String) -> void:
	_items[id] = {"mat": null, "meshes": []}
	restyle(id)


## True if it was one.
func remove(id: String) -> bool:
	if not _items.has(id):
		return false
	_clear(_items[id])
	_items.erase(id)
	return true


func restyle(id: String) -> void:
	if not _items.has(id):
		return
	var t: PlaceTree = scene.tree
	var on_top := str(t.prop(id, "DepthMode")) != "Occluded"
	var fill := ShaderMaterial.new()
	fill.shader = _shader(FILL_CODE, on_top)
	var fc: Color = t.prop(id, "FillColor")
	fc.a = 1.0 - float(t.prop(id, "FillTransparency"))
	fill.set_shader_parameter("fill", fc)
	var line := ShaderMaterial.new()
	line.shader = _shader(LINE_CODE, on_top)
	var lc: Color = t.prop(id, "OutlineColor")
	lc.a = 1.0 - float(t.prop(id, "OutlineTransparency"))
	line.set_shader_parameter("line", lc)
	fill.next_pass = line
	_items[id].mat = fill
	_clock = REFRESH  # re-apply on the next frame


## Is this Part inside something highlighted (then it can't be drawn merged)?
func covers_part(part_id: String) -> bool:
	var t: PlaceTree = scene.tree
	for id in _items:
		var target := t.parent_of(id)
		if target == part_id or t.is_descendant(part_id, target):
			return true
	return false


func process(delta: float) -> void:
	_clock += delta
	if _clock < REFRESH:
		return
	_clock = 0.0
	var t: PlaceTree = scene.tree
	for id in _items:
		var e: Dictionary = _items[id]
		var want: Array = [] if not t.prop(id, "Enabled") else _meshes_for(t.parent_of(id))
		for m in e.meshes:
			if is_instance_valid(m) and not m in want:
				(m as MeshInstance3D).material_overlay = null
		for m in want:
			if (m as MeshInstance3D).material_overlay != e.mat:
				(m as MeshInstance3D).material_overlay = e.mat
		e.meshes = want


func _meshes_for(target: String) -> Array:
	var out: Array = []
	var t: PlaceTree = scene.tree
	if target == "" or not t.has(target):
		return out
	var parts: Array = [target] + Array(t.descendants(target))
	for p in parts:
		var m: MeshInstance3D = scene.mesh_of(p)
		if m and m.visible:
			out.append(m)
	# A player's character is drawn as their Melly; a Rig as its own.
	var av: Node = scene.avatar_for(target)
	if av:
		for m in av.find_children("*", "MeshInstance3D", true, false):
			out.append(m)
	return out


func _clear(e: Dictionary) -> void:
	for m in e.meshes:
		if is_instance_valid(m):
			(m as MeshInstance3D).material_overlay = null
	e.meshes = []


static func _shader(code: String, on_top: bool) -> Shader:
	var key := code.length() * 2 + int(on_top)
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = code % (", depth_test_disabled" if on_top else "")
		_shaders[key] = sh
	return _shaders[key]
