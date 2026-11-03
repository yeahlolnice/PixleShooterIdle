class_name Aimbot
extends DriverCheat
## Aimbot (Rage): every physics tick, pulls the aim toward the visible bot head
## nearest the crosshair. Effects (cheats.json), all target cheat:
##   fov_deg           only heads within this angle of the crosshair are locked
##                     (180 at max: anywhere around you)
##   snap_speed        fraction of the remaining angle turned per physics tick
##                     (1 = instant snap)
##   instant_headshot  max level: every bot hit counts as a headshot (sets the
##                     weapon's force_headshot modifier; reapplied on gun change)
## Fighting it with the mouse works at low levels; it also pulls recoil back on target.

const FORCE_HEADSHOT := "force_headshot"
const LASER_NAME := "AimbotLaser"
## Laser start in camera space: right of and below the crosshair, near the muzzle.
const LASER_ORIGIN := Vector3(0.25, -0.2, -0.6)


func apply(player: Object, level: int) -> void:
	super.apply(player, level)
	var weapon: Object = weapon_of(player) if player else null
	if weapon:
		weapon.set_modifier(FORCE_HEADSHOT, bool(value_at("instant_headshot", level)))


func remove(player: Object) -> void:
	super.remove(player)
	var weapon: Object = weapon_of(player) if player else null
	if weapon:
		weapon.set_modifier(FORCE_HEADSHOT, false)


func drive(player: Node, driver: DriverCheat.Driver, _delta: float) -> void:
	var target := CheatTargeting.best_target(player.camera, float(driver.settings.get("fov_deg", 0.0)))
	var laser := laser_of(driver)
	if target.is_empty():
		laser.visible = false
		return
	player.aim_at(target["head"], float(driver.settings.get("snap_speed", 0.0)))
	_point_laser(laser, player.camera, target["head"])


func idle(driver: DriverCheat.Driver) -> void:
	laser_of(driver).visible = false


## Red laser from just under the gun to the locked head (TASK-030). Lives under
## the driver, so removing the cheat removes it.
static func laser_of(driver: Node) -> MeshInstance3D:
	var laser := driver.get_node_or_null(LASER_NAME) as MeshInstance3D
	if laser == null:
		laser = MeshInstance3D.new()
		laser.name = LASER_NAME
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.012, 0.012, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.15, 0.15, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = mat
		laser.mesh = mesh
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		laser.visible = false
		driver.add_child(laser)
	return laser


static func _point_laser(laser: MeshInstance3D, camera: Camera3D, head: Vector3) -> void:
	var b := camera.global_transform.basis
	var from := camera.global_position + b * LASER_ORIGIN
	var length := from.distance_to(head)
	if length < 0.05:
		laser.visible = false
		return
	laser.global_transform = Transform3D(Basis.looking_at(head - from, Vector3.UP), (from + head) * 0.5)
	laser.scale = Vector3(1, 1, length)
	laser.visible = true
