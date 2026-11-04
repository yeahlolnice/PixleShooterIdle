class_name Sentry
extends Node3D
## One Sentry.exe turret (fun pack, D66): a voxel tripod whose head turns to the
## nearest live bot it can see within range and shoots it (body hits, hitscan,
## world blocks line of sight). Base stats from economy.json "sentries", scaled
## by the sentry_damage / sentry_rate upgrades (SentryManager sets the mults).
## Kills report gun_id GUN_ID, so MatchTracker pays them at sentries.cash_mult
## and keeps them out of streaks and multi-kills.

const GUN_ID := MatchTracker.SENTRY_GUN_ID
const MUZZLE_HEIGHT := 1.05
const AIM_HEIGHT := 0.9          ## bot body centre above its feet
const AIM_TOLERANCE_DEG := 8.0   ## fires once the head points within this
const TRACER_S := 0.06
const DEPLOY_S := 0.35

var damage_mult := 1.0
var fire_rate_mult := 1.0
var target: Node3D = null
var _cooldown := 0.0
var _head: Node3D
var _tracer: MeshInstance3D
var _tracer_left := 0.0
var _sound: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("sentries")
	var base := _box(Vector3(0.7, 0.15, 0.7), Vector3(0, 0.075, 0), "gun_black")
	base.name = "Base"
	_box(Vector3(0.14, 0.75, 0.14), Vector3(0, 0.5, 0), "gun_grey")
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, MUZZLE_HEIGHT, 0)
	add_child(_head)
	_box(Vector3(0.4, 0.3, 0.45), Vector3.ZERO, "danger", _head)
	_box(Vector3(0.08, 0.08, 0.6), Vector3(0, 0.02, -0.45), "gun_black", _head)
	_box(Vector3(0.12, 0.06, 0.02), Vector3(0, 0.05, -0.23), "neon", _head)   # "eye"
	_tracer = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = DataRegistry.color("cash")
	mesh.material = mat
	_tracer.mesh = mesh
	_tracer.visible = false
	add_child(_tracer)
	_sound = AudioStreamPlayer3D.new()
	_sound.stream = SfxSynth.shot("smg")
	_sound.bus = SfxPlayer.BUS
	_sound.volume_db = -8.0
	_sound.max_polyphony = 3
	_head.add_child(_sound)
	scale = Vector3.ONE * 0.01
	create_tween().tween_property(self, "scale", Vector3.ONE, DEPLOY_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func rules() -> Dictionary:
	return DataRegistry.economy().get("sentries", {})


func damage() -> float:
	return float(rules().get("damage", 0.0)) * damage_mult


func fire_interval() -> float:
	return 1.0 / maxf(float(rules().get("fire_rate", 1.0)) * fire_rate_mult, 0.01)


func muzzle() -> Vector3:
	return global_position + Vector3(0, MUZZLE_HEIGHT, 0)


func _physics_process(delta: float) -> void:
	tick(delta)


## Pick a target, turn, shoot. Split out so tests can step it.
func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _tracer_left > 0.0:
		_tracer_left -= delta
		_tracer.visible = _tracer_left > 0.0
	if not _valid(target) or not _sees(target):
		target = _pick_target()
	if target == null:
		return
	var aim := target.global_position + Vector3(0, AIM_HEIGHT, 0)
	var flat := Vector3(aim.x - global_position.x, 0.0, aim.z - global_position.z)
	if flat.length_squared() < 0.0001:
		return
	var want := atan2(-flat.x, -flat.z)
	var step := deg_to_rad(float(rules().get("turn_speed_deg_s", 360.0))) * delta
	var diff := wrapf(want - _head.rotation.y, -PI, PI)
	_head.rotation.y += clampf(diff, -step, step)
	if _cooldown <= 0.0 and absf(wrapf(want - _head.rotation.y, -PI, PI)) <= deg_to_rad(AIM_TOLERANCE_DEG):
		_fire(aim)


func _fire(aim: Vector3) -> void:
	_cooldown = fire_interval()
	if target.has_method("take_hit"):
		target.take_hit("body", damage(), GUN_ID, 1.0)
	var from := muzzle()
	var length := from.distance_to(aim)
	if length > 0.05:
		_tracer.global_transform = Transform3D(Basis.looking_at(aim - from, Vector3.UP), (from + aim) * 0.5)
		_tracer.scale = Vector3(1, 1, length)
		_tracer_left = TRACER_S
		_tracer.visible = true
	if _sound and _sound.is_inside_tree():
		_sound.play()


## Nearest live bot within range with a clear line from the muzzle, or null.
func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_d := float(rules().get("range_m", 0.0))
	for b in get_tree().get_nodes_in_group("bots"):
		if not CheatTargeting.is_live(b):
			continue
		var d := muzzle().distance_to((b as Node3D).global_position + Vector3(0, AIM_HEIGHT, 0))
		if d <= best_d and _sees(b):
			best = b
			best_d = d
	return best


func _valid(b: Variant) -> bool:
	return CheatTargeting.is_live(b) and muzzle().distance_to((b as Node3D).global_position) <= float(rules().get("range_m", 0.0)) + 1.0


func _sees(b: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(muzzle(), b.global_position + Vector3(0, AIM_HEIGHT, 0), Layers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _box(size: Vector3, pos: Vector3, color: String, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DataRegistry.color(color)
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi
