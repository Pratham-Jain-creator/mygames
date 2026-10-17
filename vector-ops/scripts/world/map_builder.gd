class_name MapBuilder
extends Node3D
## Script of scenes/world/map.tscn. The arena itself (floor tiles, containers, walls,
## platforms, ladders, spawn markers) is authored in that scene - edit it in the editor.
## This script only does the runtime chores:
##  - merges each container / floor tile into one mesh (a few draw calls instead of thousands)
##  - collects the solid footprints for the minimap
##  - ladder volumes tell the player when it is climbing
##  - bakes the bots' navigation mesh

## Solid footprints for the minimap: [Vector2 centre(x,z), Vector2 size(x,z)]
static var rects: Array = []


func _ready() -> void:
	rects.clear()
	for n in get_node("Nav/Geo").get_children():
		if n is CSGBox3D:
			var b := n as CSGBox3D
			if b.use_collision and b.size.y > 1.0:
				rects.append([Vector2(b.position.x, b.position.z), Vector2(b.size.x, b.size.z)])
			continue
		var cs := n.get_node_or_null("Collision") as CollisionShape3D
		if cs == null and n is Node3D and not (n is CollisionObject3D):
			# an instanced building / alley scene: take the footprints of its solid CSG parts
			_collect_csg(n as Node3D)
			continue
		if cs != null and cs.shape is BoxShape3D:
			var sz: Vector3 = (cs.shape as BoxShape3D).size
			var turned: bool = absf((n as Node3D).basis.x.x) < 0.5 # rotated a quarter turn
			if sz.y > 1.0:
				var pos: Vector3 = (n as Node3D).position
				rects.append([Vector2(pos.x, pos.z), Vector2(sz.z, sz.x) if turned else Vector2(sz.x, sz.z)])
		_merge_meshes(n as Node3D, not String(n.name).begins_with("Ground_"))


## Minimap footprints of a CSG building: every solid top-level box / cylinder that rises above
## head height and starts near the ground (bridges and overhangs are skipped).
func _collect_csg(root: Node3D) -> void:
	var inv: Transform3D = global_transform.affine_inverse()
	for n in root.find_children("*", "CSGShape3D", true, false):
		var c := n as CSGShape3D
		if not c.use_collision or c.operation != CSGShape3D.OPERATION_UNION or c.get_parent() is CSGShape3D:
			continue
		var half := Vector3.ZERO
		if c is CSGBox3D:
			half = (c as CSGBox3D).size * 0.5
		elif c is CSGCylinder3D:
			var cyl := c as CSGCylinder3D
			half = Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)
		else:
			continue
		var xf: Transform3D = inv * c.global_transform
		var top: float = xf.origin.y + half.y * xf.basis.y.length()
		var bottom: float = xf.origin.y - half.y * xf.basis.y.length()
		if top < 1.5 or bottom > 3.0:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p: Vector3 = xf * Vector3(half.x * sx, 0.0, half.z * sz)
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		rects.append([(lo + hi) * 0.5, hi - lo])


func _on_ladder_entered(b: Node) -> void:
	if b.has_method("ladder_enter"):
		b.ladder_enter()


func _on_ladder_exited(b: Node) -> void:
	if b.has_method("ladder_exit"):
		b.ladder_exit()


## Many small meshes -> one mesh with a surface per material.
static func _merge_meshes(root: Node3D, shadows: bool) -> void:
	var groups := {}
	var src: Array = []
	for n in root.get_children():
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mat: Material = mi.get_active_material(0)
		if not groups.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[mat] = st
		(groups[mat] as SurfaceTool).append_from(mi.mesh, 0, mi.transform)
		src.append(mi)
	if groups.is_empty():
		return
	var am := ArrayMesh.new()
	for mat in groups:
		(groups[mat] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	for mi in src:
		root.remove_child(mi)
		mi.free()
	var out := MeshInstance3D.new()
	out.name = "Visual"
	out.mesh = am
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(out)


static func bake_nav(map: Node) -> void:
	var nav := map.get_node("Nav") as NavigationRegion3D
	if nav == null:
		return
	nav.bake_navigation_mesh(true) # on a thread: the big arenas take a few seconds
