extends SceneTree
## Renders every res://shaders/*.gdshader on a box (as next_pass, like the game
## uses them) for a few frames so the active renderer compiles them. Needs a real
## display/GPU (not --headless). Usage (see tools/check_shaders.sh):
##   godot --path . --rendering-method gl_compatibility -s res://tools/check_shaders.gd

const DIR := "res://shaders"
const FRAMES := 5


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	world.add_child(cam)
	var x := -1.0
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".gdshader"):
			continue
		var shader: Shader = load(DIR + "/" + file)
		print("[check_shaders] ", file, " -> ", "OK load" if shader else "LOAD FAILED")
		var pass_mat := ShaderMaterial.new()
		pass_mat.shader = shader
		var base := StandardMaterial3D.new()
		base.next_pass = pass_mat
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = base
		mi.position = Vector3(x, 0, 0)
		x += 1.5
		world.add_child(mi)
	print("[check_shaders] renderer: ", RenderingServer.get_current_rendering_method(),
		" driver: ", RenderingServer.get_current_rendering_driver_name())


var _frames := 0


func _process(_delta: float) -> bool:
	_frames += 1
	return _frames >= FRAMES
