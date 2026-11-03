extends Node3D
## Builds an arena from one arenas.json entry: blocks merged into one mesh per
## palette colour, one shared StaticBody3D on the WORLD layer (one box shape per
## block, so fast bodies cannot tunnel through thin concave triangles), spawn
## points, and a NavigationRegion3D baked synchronously at build time.

signal built(arena_id: String)

var arena_id := ""
var player_spawns: Array[Vector3] = []
var bot_spawns: Array[Vector3] = []
var nav_region: NavigationRegion3D = null

var _materials := {}  # palette colour name -> StandardMaterial3D
var _block_count := 0


## Builds from a validated arena dictionary (DataRegistry.arena(id)).
## Calling build again replaces the previous layout.
func build(arena_def: Dictionary) -> void:
	clear()
	arena_id = arena_def.get("id", "")
	var blocks: Array = arena_def.get("blocks", [])
	_block_count = blocks.size()

	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	add_child(body)

	var tools := {}  # colour name -> SurfaceTool
	var nav_source := NavigationMeshSourceGeometryData3D.new()
	for block in blocks:
		var size: Vector3 = block["size"]
		var pos: Vector3 = block["pos"]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = pos
		body.add_child(shape)
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		var color_name: String = block["color"]
		if not tools.has(color_name):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[color_name] = st
		(tools[color_name] as SurfaceTool).append_from(box_mesh, 0, Transform3D(Basis.IDENTITY, pos))
		nav_source.add_faces(_box_faces(pos, size), Transform3D.IDENTITY)

	var blocks_root := Node3D.new()
	blocks_root.name = "Blocks"
	add_child(blocks_root)
	for color_name in tools:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = color_name
		mesh_instance.mesh = (tools[color_name] as SurfaceTool).commit()
		mesh_instance.material_override = _material(color_name)
		blocks_root.add_child(mesh_instance)

	player_spawns.assign(arena_def.get("player_spawns", []))
	bot_spawns.assign(arena_def.get("bot_spawns", []))
	_bake_navigation(nav_source)
	built.emit(arena_id)


## Number of source blocks (not merged meshes).
func block_count() -> int:
	return _block_count


## Polygon count of the baked navmesh; 0 means the bake failed or found no floor.
func nav_polygon_count() -> int:
	if nav_region == null or nav_region.navigation_mesh == null:
		return 0
	return nav_region.navigation_mesh.get_polygon_count()


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	player_spawns.clear()
	bot_spawns.clear()
	nav_region = null
	_block_count = 0


func _bake_navigation(source: NavigationMeshSourceGeometryData3D) -> void:
	var nav_cfg: Dictionary = DataRegistry.player().get("nav", {})
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = nav_cfg.get("agent_radius", 0.5)
	navmesh.agent_height = nav_cfg.get("agent_height", 2.0)
	navmesh.agent_max_climb = nav_cfg.get("agent_max_climb", 0.5)
	navmesh.cell_size = nav_cfg.get("cell_size", 0.25)
	navmesh.cell_height = nav_cfg.get("cell_height", 0.125)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	nav_region.navigation_mesh = navmesh
	add_child(nav_region)


## 12 triangles of an axis-aligned box, built in script so navmesh baking never
## reads geometry back from the GPU.
static func _box_faces(pos: Vector3, size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var c := PackedVector3Array()
	for i in 8:
		c.append(pos + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var quads := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6]]
	var faces := PackedVector3Array()
	for q in quads:
		faces.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return faces


func _material(color_name: String) -> StandardMaterial3D:
	if not _materials.has(color_name):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = DataRegistry.color(color_name)
		mat.roughness = 1.0
		_materials[color_name] = mat
	return _materials[color_name]
