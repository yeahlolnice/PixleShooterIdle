class_name HudFeedback
extends Control
## HUD juice (TASK-027), driven only by EventBus:
##   hit marker   "×" over the crosshair on bot_damaged (red on headshots),
##                bigger on kill_rewarded
##   kill feed    top-left lines "+$240  Sniper  HEADSHOT  [Block-47]", fading out
##   death screen "YOU DIED / killed by Rusher / respawn in 2.3" until player_spawned
##   scope        dark ring + thin cross while scope_changed(true)

const HIT_MARKER_S := 0.15
const KILL_MARKER_S := 0.3
const FEED_LINES := 5
const FEED_LIFE_S := 4.0
const FEED_FADE_S := 0.8
const SCOPE_RADIUS_RATIO := 0.42   ## of the shorter screen side
const ANNOUNCE_S := 1.4
const CHAIN_NAMES := {2: "DOUBLE KILL", 3: "TRIPLE KILL", 4: "MULTI KILL"}
const CHAIN_TOP := "RAMPAGE"

var _marker: Label
var _marker_left := 0.0
var _feed: VBoxContainer
var _death: PanelContainer
var _death_label: Label
var _respawn_left := 0.0
var _killer_name := ""
var _scope: Control
var _announce: Label
var _announce_left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # not set_anchors_preset: that keeps the 0x0 rect
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope = ScopeOverlay.new()
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.visible = false
	add_child(_scope)
	_marker = Label.new()
	_marker.text = "×"
	_marker.add_theme_font_size_override("font_size", 34)
	_marker.add_theme_constant_override("outline_size", 4)
	_marker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_marker.set_anchors_preset(Control.PRESET_CENTER)
	_marker.offset_left = -20.0
	_marker.offset_right = 20.0
	_marker.offset_top = -26.0
	_marker.offset_bottom = 22.0
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.visible = false
	add_child(_marker)
	_feed = VBoxContainer.new()
	_feed.position = Vector2(24, 64)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)
	_death = PanelContainer.new()
	_death.set_anchors_preset(Control.PRESET_CENTER)
	_death.offset_left = -200.0
	_death.offset_right = 200.0
	_death.offset_top = -70.0
	_death.offset_bottom = 70.0
	_death.visible = false
	add_child(_death)
	_death_label = Label.new()
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 22)
	_death.add_child(_death_label)
	_announce = Label.new()
	_announce.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_announce.offset_top = 150.0
	_announce.offset_bottom = 200.0
	_announce.offset_left = -300.0
	_announce.offset_right = 300.0
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.add_theme_font_size_override("font_size", 34)
	_announce.add_theme_constant_override("outline_size", 8)
	_announce.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_announce.add_theme_color_override("font_color", DataRegistry.color("accent"))
	_announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_announce.visible = false
	add_child(_announce)
	EventBus.bot_damaged.connect(func(_bot, info): show_hit(bool(info.get("headshot", false)), false))
	EventBus.kill_rewarded.connect(_on_kill_rewarded)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_spawned.connect(func(_p): _death.visible = false)
	EventBus.scope_changed.connect(func(on): _scope.visible = on)
	EventBus.multi_kill.connect(func(c, m): announce(chain_text(c, m)))
	EventBus.bonus_paid.connect(func(reason, cash, _pos): announce("%s  +%s" % [reason, Fmt.cash(cash)]))


func _process(delta: float) -> void:
	if _announce_left > 0.0:
		_announce_left -= delta
		_announce.modulate.a = clampf(_announce_left / 0.4, 0.0, 1.0)
		_announce.visible = _announce_left > 0.0
	if _marker_left > 0.0:
		_marker_left -= delta
		_marker.modulate.a = clampf(_marker_left / HIT_MARKER_S, 0.0, 1.0)
		_marker.visible = _marker_left > 0.0
	if _death.visible and _respawn_left > 0.0:
		_respawn_left = maxf(0.0, _respawn_left - delta)
		_death_label.text = death_text(_killer_name, _respawn_left)
	for line in _feed.get_children():
		var age := float(line.get_meta("age", 0.0)) + delta
		line.set_meta("age", age)
		line.modulate.a = clampf((FEED_LIFE_S - age) / FEED_FADE_S, 0.0, 1.0)
		if age >= FEED_LIFE_S:
			line.queue_free()


func show_hit(headshot: bool, kill: bool) -> void:
	_marker_left = KILL_MARKER_S if kill else HIT_MARKER_S
	_marker.scale = Vector2.ONE * (1.5 if kill else 1.0)
	_marker.pivot_offset = _marker.size * 0.5
	_marker.add_theme_color_override("font_color", DataRegistry.color("danger") if headshot or kill else Color.WHITE)
	_marker.modulate.a = 1.0
	_marker.visible = true


func is_marker_visible() -> bool:
	return _marker.visible


func feed_lines() -> Array:
	return _feed.get_children().filter(func(l): return not l.is_queued_for_deletion()).map(func(l): return l.text)


func is_death_screen_visible() -> bool:
	return _death.visible


func death_screen_text() -> String:
	return _death_label.text


func is_scope_visible() -> bool:
	return _scope.visible


## Big centre line for multi-kills and bonuses, fading out.
func announce(text: String) -> void:
	_announce.text = text
	_announce_left = ANNOUNCE_S
	_announce.modulate.a = 1.0
	_announce.visible = true


func announcement() -> String:
	return _announce.text if _announce.visible else ""


## "DOUBLE KILL  x1.5", ..., "RAMPAGE x5  x3.0"
static func chain_text(chain: int, mult: float) -> String:
	var title: String = CHAIN_NAMES.get(chain, "%s x%d" % [CHAIN_TOP, chain])
	return "%s  x%s" % [title, String.num(mult, 1)]


## "+$240  Sniper  HEADSHOT  [Block-47]"
static func feed_text(cash: float, info: Dictionary) -> String:
	var bot_type := String(info.get("bot_type", ""))
	var who := String(DataRegistry.bot(bot_type).get("name", bot_type.capitalize())) if bot_type != "" else "Bot"
	var gun := String(DataRegistry.gun(String(info.get("gun_id", ""))).get("name", ""))
	var text := "%s  %s" % [Fmt.cash(cash), who]
	if bool(info.get("headshot", false)):
		text += "  HEADSHOT"
	if gun != "":
		text += "  [%s]" % gun
	return text


static func death_text(killer_name: String, respawn_in: float) -> String:
	var by := ("killed by %s" % killer_name) if killer_name != "" else "you fell"
	return "YOU DIED\n%s\nrespawn in %.1f" % [by, respawn_in]


func _on_kill_rewarded(cash: float, info: Dictionary) -> void:
	show_hit(bool(info.get("headshot", false)), true)
	var line := Label.new()
	line.text = feed_text(cash, info)
	line.add_theme_font_size_override("font_size", 15)
	line.add_theme_constant_override("outline_size", 4)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	line.add_theme_color_override("font_color", DataRegistry.color("cash"))
	line.set_meta("age", 0.0)
	_feed.add_child(line)
	while _feed.get_child_count() > FEED_LINES:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()


func _on_player_died(info: Dictionary) -> void:
	var killer: Variant = info.get("killer")
	_killer_name = ""
	if is_instance_valid(killer) and "stats" in killer:
		_killer_name = String(killer.stats.get("name", ""))
	_respawn_left = float(DataRegistry.player().get("respawn_delay_s", 0.0))
	_death_label.text = death_text(_killer_name, _respawn_left)
	_death.visible = true


## Dark ring outside a circle in the screen centre, plus a thin cross.
class ScopeOverlay:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * HudFeedback.SCOPE_RADIUS_RATIO
		var far := size.length()
		draw_arc(c, r + far * 0.5, 0.0, TAU, 96, Color.BLACK, far, true)
		draw_arc(c, r, 0.0, TAU, 96, Color(0, 0, 0, 0.9), 3.0, true)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.8), 1.5)
		draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0, 0, 0, 0.8), 1.5)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
