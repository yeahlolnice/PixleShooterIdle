class_name Wallhack
extends CheatBase
## Wallhack: bots within range of the player get a neon outline drawn on top of
## walls (shaders/wallhack_outline.gdshader as next_pass on their part materials),
## and from the "health_bars" level a health bar above them.
##
## Effects (data/cheats.json): radius_m (range at the owned level), whole_map
## (unlimited range), health_bars (bool). apply() adds a Scanner node under the
## player that re-checks the range on a timer (SCAN_INTERVAL_S), not every frame;
## only bots entering or leaving the range have their materials touched.
## remove() frees the Scanner, which strips every outline and bar it added.

const SCANNER_NAME := "WallhackScanner"
const HEALTH_BAR_NAME := "WallhackHealthBar"
const OUTLINE_SHADER := preload("res://shaders/wallhack_outline.gdshader")
## How often the range is re-checked. Engine cadence, not a balance value.
const SCAN_INTERVAL_S := 0.2
const OUTLINE_COLOR := "neon"
const BAR_BG_COLOR := "ui_bg"
const BAR_LOW_COLOR := "danger"
const BAR_HIGH_COLOR := "neon"
const BAR_HEIGHT_M := 2.1      ## above the bot's feet (bot head top is ~1.7 m)
const BAR_PIXELS := Vector2i(64, 8)
const BAR_PIXEL_SIZE := 0.012  ## metres per bar pixel -> 0.77 m wide


# --- Pure range logic (unit-tested) ----------------------------------------------

## Outline range in metres at `level`: INF with whole_map, 0 when not owned.
func range_at(level: int) -> float:
	return effective_range(float(value_at("radius_m", level)), bool(value_at("whole_map", level)))


func health_bars_at(level: int) -> bool:
	return bool(value_at("health_bars", level))


static func effective_range(radius_m: float, whole_map: bool) -> float:
	return INF if whole_map else maxf(radius_m, 0.0)


## Indices of `positions` (Vector3) within `radius` of `origin`, in input order.
## A radius of 0 or less selects nothing; INF selects everything.
static func select_in_range(origin: Vector3, positions: Array, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if radius <= 0.0:
		return out
	var r2 := radius * radius
	for i in positions.size():
		if is_inf(radius) or origin.distance_squared_to(positions[i]) <= r2:
			out.append(i)
	return out


## Live bots (Node3D, not dead) from `bots` that are within range at `level`.
func select_bots(origin: Vector3, bots: Array, level: int) -> Array:
	var live: Array = []
	var positions: Array = []
	for bot in bots:
		if not (is_instance_valid(bot) and bot is Node3D):
			continue
		if bot.has_method("is_dead") and bot.is_dead():
			continue
		live.append(bot)
		positions.append((bot as Node3D).global_position)
	var out: Array = []
	for i in select_in_range(origin, positions, range_at(level)):
		out.append(live[i])
	return out


# --- CheatBase hooks ------------------------------------------------------------

func apply(player: Object, level: int) -> void:
	super.apply(player, level)
	if not (player is Node3D):
		return
	var scanner: Scanner = player.get_node_or_null(SCANNER_NAME) as Scanner
	if scanner == null:
		scanner = Scanner.new()
		scanner.name = SCANNER_NAME
		scanner.cheat = self
		scanner.level = level
		player.add_child(scanner)
	else:
		scanner.cheat = self
		scanner.level = level
		scanner.scan()


func remove(player: Object) -> void:
	super.remove(player)
	if not (player is Node):
		return
	var scanner: Scanner = player.get_node_or_null(SCANNER_NAME) as Scanner
	if scanner:
		scanner.clear_all()
		player.remove_child(scanner)
		scanner.free()


## Lives under the player while Wallhack is on. Keeps the set of outlined bots
## in sync with the range on a timer and owns the outline material.
class Scanner:
	extends Node

	var cheat: Wallhack
	var level := 0
	var outline_material: ShaderMaterial
	var _outlined := {}   ## instance_id -> bot
	var _bar_texture: ImageTexture
	var _timer: Timer

	func _ready() -> void:
		outline_material = ShaderMaterial.new()
		outline_material.shader = OUTLINE_SHADER
		outline_material.set_shader_parameter("outline_color", DataRegistry.color(OUTLINE_COLOR))
		var image := Image.create(BAR_PIXELS.x, BAR_PIXELS.y, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_bar_texture = ImageTexture.create_from_image(image)
		_timer = Timer.new()
		_timer.wait_time = SCAN_INTERVAL_S
		_timer.timeout.connect(scan)
		add_child(_timer)
		_timer.start()
		EventBus.bot_damaged.connect(_on_bot_damaged)
		scan()

	func _exit_tree() -> void:
		clear_all()

	## Bots currently outlined (valid ones only).
	func outlined_bots() -> Array:
		return _outlined.values().filter(func(b): return is_instance_valid(b))

	## Re-checks the range: outlines bots that entered, strips bots that left.
	func scan() -> void:
		var player := get_parent() as Node3D
		if player == null or cheat == null or not is_inside_tree():
			return
		var bots := get_tree().get_nodes_in_group("bots")
		var keep := {}
		for bot in cheat.select_bots(player.global_position, bots, level):
			keep[bot.get_instance_id()] = bot
		for id in _outlined.keys():
			if not keep.has(id):
				var old: Object = _outlined[id]
				if is_instance_valid(old):
					_set_outline(old, false)
				_outlined.erase(id)
		var bars := cheat.health_bars_at(level)
		for id in keep:
			var bot: Node3D = keep[id]
			if not _outlined.has(id):
				_outlined[id] = bot
				_set_outline(bot, true)
			_update_bar(bot, bars)

	## Strips every outline and health bar this scanner added.
	func clear_all() -> void:
		for bot in _outlined.values():
			if is_instance_valid(bot):
				_set_outline(bot, false)
		_outlined.clear()

	func _on_bot_damaged(bot: Node, _info: Dictionary) -> void:
		if is_instance_valid(bot) and _outlined.has(bot.get_instance_id()):
			_update_bar(bot, cheat.health_bars_at(level))

	func _set_outline(bot: Node, on: bool) -> void:
		for node in bot.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var mat := mi.material_override
			if mat:
				if on:
					mat.next_pass = outline_material
				elif mat.next_pass == outline_material:
					mat.next_pass = null
			elif on:
				mi.material_overlay = outline_material
			elif mi.material_overlay == outline_material:
				mi.material_overlay = null
		if not on:
			_update_bar(bot, false)

	func _update_bar(bot: Node, show: bool) -> void:
		var bar: Node3D = bot.get_node_or_null(HEALTH_BAR_NAME)
		if not show:
			if bar:
				bot.remove_child(bar)
				bar.free()
			return
		if bar == null:
			bar = _make_bar()
			bot.add_child(bar)
		var max_health := float(bot.stats.get("health", 0.0)) if "stats" in bot else 0.0
		var ratio := clampf(float(bot.health) / max_health, 0.0, 1.0) if max_health > 0.0 and "health" in bot else 1.0
		var fill: Sprite3D = bar.get_node("Fill")
		fill.visible = ratio > 0.0
		fill.region_rect = Rect2(0, 0, BAR_PIXELS.x * ratio, BAR_PIXELS.y)
		fill.modulate = DataRegistry.color(BAR_LOW_COLOR).lerp(DataRegistry.color(BAR_HIGH_COLOR), ratio)

	func _make_bar() -> Node3D:
		var bar := Node3D.new()
		bar.name = HEALTH_BAR_NAME
		bar.position = Vector3(0, BAR_HEIGHT_M, 0)
		var bg := _bar_sprite("Bg", DataRegistry.color(BAR_BG_COLOR), 0)
		bar.add_child(bg)
		var fill := _bar_sprite("Fill", DataRegistry.color(BAR_HIGH_COLOR), 1)
		fill.region_enabled = true
		bar.add_child(fill)
		return bar

	func _bar_sprite(sprite_name: String, color: Color, priority: int) -> Sprite3D:
		var s := Sprite3D.new()
		s.name = sprite_name
		s.texture = _bar_texture
		s.pixel_size = BAR_PIXEL_SIZE
		s.centered = false
		s.offset = Vector2(-BAR_PIXELS.x * 0.5, -BAR_PIXELS.y * 0.5)
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.no_depth_test = true
		s.shaded = false
		s.modulate = color
		s.render_priority = priority
		return s
