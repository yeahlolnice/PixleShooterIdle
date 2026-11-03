extends Node3D
## Builds an arena from one arenas.json entry: a coloured box per block, one
## shared StaticBody3D on the WORLD layer, and spawn point markers.
## TASK-002 extends this with merged meshes and a runtime NavigationRegion3D bake.

signal built(arena_id: String)

var arena_id := ""
var player_spawns: Array[Vector3] = []
var bot_spawns: Array[Vector3] = []

var _materials := {}  # palette colour name -> StandardMaterial3D


## Builds from a validated arena dictionary (DataRegistry.arena(id)).
## Calling build again replaces the previous layout.
func build(arena_def: Dictionary) -> void:
	clear()
	arena_id = arena_def.get("id", "")
	var blocks_root := Node3D.new()
	blocks_root.name = "Blocks"
	add_child(blocks_root)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	add_child(body)
	for block in arena_def.get("blocks", []):
		var size: Vector3 = block["size"]
		var pos: Vector3 = block["pos"]
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _material(block["color"])
		mesh_instance.position = pos
		blocks_root.add_child(mesh_instance)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = pos
		body.add_child(shape)
	player_spawns.assign(arena_def.get("player_spawns", []))
	bot_spawns.assign(arena_def.get("bot_spawns", []))
	built.emit(arena_id)


func block_count() -> int:
	var blocks := get_node_or_null("Blocks")
	return blocks.get_child_count() if blocks else 0


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	player_spawns.clear()
	bot_spawns.clear()


func _material(color_name: String) -> StandardMaterial3D:
	if not _materials.has(color_name):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = DataRegistry.color(color_name)
		mat.roughness = 1.0
		_materials[color_name] = mat
	return _materials[color_name]
