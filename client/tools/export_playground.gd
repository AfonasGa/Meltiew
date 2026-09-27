extends Node
## Writes the playground's solid shapes as boxes for the server's anti-cheat (what
## players can stand on there): server/src/playground_solids.json. Run after changing
## the playground:
##   godot --headless --path . res://tools/export_playground.tscn


func _ready() -> void:
	var pg: Node3D = Playground.new()
	add_child(pg)
	await get_tree().process_frame
	var out: Array = []
	for body in pg.find_children("*", "PhysicsBody3D", true, false):
		for col in body.find_children("*", "CollisionShape3D", true, false):
			var cs := col as CollisionShape3D
			if cs.disabled or cs.shape == null:
				continue
			var xf := cs.global_transform
			var half := Vector3.ZERO
			var center := Vector3.ZERO
			var sh := cs.shape
			if sh is BoxShape3D:
				half = (sh as BoxShape3D).size / 2.0
			elif sh is CylinderShape3D:
				var c := sh as CylinderShape3D
				half = Vector3(c.radius, c.height / 2.0, c.radius)
			elif sh is CapsuleShape3D:
				var c := sh as CapsuleShape3D
				half = Vector3(c.radius, c.height / 2.0, c.radius)
			elif sh is SphereShape3D:
				var r := (sh as SphereShape3D).radius
				half = Vector3(r, r, r)
			else:
				var aabb := sh.get_debug_mesh().get_aabb()
				half = aabb.size / 2.0
				center = aabb.get_center()
			var b := xf.basis.orthonormalized()
			var sc := xf.basis.get_scale()
			half *= sc
			var p := xf * center
			var e := [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001), snappedf(half.x, 0.001), snappedf(half.y, 0.001), snappedf(half.z, 0.001)]
			# Rows of the rotation, like the runtime's rotMatrix.
			for r in 3:
				for c in 3:
					e.append(snappedf(b[c][r], 0.0001))
			# Moving things (carousel, swings, see-saw): where they are now isn't where
			# they'll be, so a box around their whole reach, and standing in it counts.
			if body is AnimatableBody3D or body is RigidBody3D or body is CharacterBody3D:
				for k in range(3, 6):
					e[k] += 2.5
				e.append(2 + 4)
			else:
				e.append(2)
			out.append(e)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../server/src/playground_solids.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("playground: %d solid boxes" % out.size())
	get_tree().quit()
