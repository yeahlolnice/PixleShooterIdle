class_name LootPickup
extends Node3D
## Bonus cash a killed bot drops (economy.json "loot"). Paid out when the player
## comes within pickup_radius_m of it; gone after lifetime_s. Spins so it reads
## as loot. Loot Magnet moves it toward the player with pull_toward().
## Round-end cleanup frees it with the bots (it is parented to the BotSpawner).

const GROUP := "loot"
const SPIN_DEG_S := 180.0
const SIZE := 0.3
const COLOR := "cash"
## Distance is measured to this point above the player's feet (capsule centre).
const PLAYER_CENTER := Vector3(0, 0.9, 0)
## Cheat whose ESP shows the price tag.
const ESP_CHEAT := "loot_magnet"

var value := 0.0
var pickup_radius := 1.0
var life_left := 0.0
var _player: Node3D
## Floating "$12" tag, visible while ESP_CHEAT is on.
var tag: Label3D


## Call before add_child. `rules` = DataRegistry.economy()["loot"].
func setup(cash: float, rules: Dictionary) -> void:
	value = cash
	pickup_radius = float(rules.get("pickup_radius_m", 1.0))
	life_left = float(rules.get("lifetime_s", 1.0))


func _ready() -> void:
	add_to_group(GROUP)
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DataRegistry.color(COLOR)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	# ESP price tag (TASK-030): shown while Loot Magnet is on.
	tag = Label3D.new()
	tag.text = Fmt.cash(value)
	tag.modulate = DataRegistry.color(COLOR)
	tag.outline_size = 8
	tag.font_size = 40
	tag.pixel_size = 0.01
	tag.position = Vector3(0, 0.45, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.visible = false
	add_child(tag)


func _physics_process(delta: float) -> void:
	tick(delta)


## Spin, expire, and pay out when the player is close. Split out for tests.
func tick(delta: float) -> void:
	if is_queued_for_deletion():
		return
	rotate_y(deg_to_rad(SPIN_DEG_S) * delta)
	if tag:
		tag.visible = CheatSystem.is_enabled(ESP_CHEAT)
	life_left -= delta
	if life_left <= 0.0:
		queue_free()
		return
	var player := _find_player()
	if player and global_position.distance_to(player.global_position + PLAYER_CENTER) <= pickup_radius:
		collect()


func collect() -> void:
	if is_queued_for_deletion():
		return
	GameState.add_cash(value)
	EventBus.loot_collected.emit(value)
	queue_free()


## Moves toward `player`'s centre by at most `max_step` metres (Loot Magnet).
func pull_toward(player: Node3D, max_step: float) -> void:
	global_position = global_position.move_toward(player.global_position + PLAYER_CENTER, max_step)


func _find_player() -> Node3D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or _player.get("is_dead") == true:
		return null
	return _player
