class_name CheatStrip
extends VBoxContainer
## HUD list (top right) of the cheats that are switched on, one line each:
## "SPEED HACK  L3". God Mode shows its invulnerability time left (∞ when
## permanent); Noclip shows flight fuel and FLYING while airborne. Reads
## CheatSystem queries and the player from EventBus.player_spawned; changes nothing.

const COLOR_ON := "neon"
const COLOR_HOT := "cash"   ## a timed effect is running right now
const FONT_SIZE := 14

var player: Object = null
var _labels: Dictionary = {}   # cheat id -> Label


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.cheat_toggled.connect(func(_id, _on): rebuild())
	EventBus.cheat_purchased.connect(func(_id, _lvl): rebuild())
	EventBus.game_state_loaded.connect(rebuild)
	EventBus.player_spawned.connect(func(p): player = p)
	rebuild()


func _process(_delta: float) -> void:
	for id in ["god_mode", "noclip"]:
		if _labels.has(id):
			_refresh(id)


## Ids currently shown, in ladder order.
func shown_ids() -> Array:
	return _labels.keys()


func text_for(id: String) -> String:
	return _labels[id].text if _labels.has(id) else ""


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_labels.clear()
	for cheat in CheatSystem.cheats():
		if not CheatSystem.is_enabled(cheat.id):
			continue
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_constant_override("outline_size", 4)   # readable on bright sky
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		add_child(label)
		_labels[cheat.id] = label
		_refresh(cheat.id)


func _refresh(id: String) -> void:
	var label: Label = _labels[id]
	var cheat := CheatSystem.get_cheat(id)
	if not is_instance_valid(player) and is_inside_tree():
		# First boot: player_spawned fired before the HUD existed.
		player = get_tree().get_first_node_in_group("player")
	var p: Object = player if is_instance_valid(player) else null
	label.text = chip_text(cheat.display_name, id, CheatSystem.level(id), p)
	var hot: bool = p != null and ((id == "god_mode" and p.is_invulnerable()) or (id == "noclip" and p.noclipping))
	label.add_theme_color_override("font_color", DataRegistry.color(COLOR_HOT if hot else COLOR_ON))


## One line of the strip. `p` (the Player, or null) adds live timers.
static func chip_text(cheat_name: String, id: String, level: int, p: Object) -> String:
	var head := "%s  L%d" % [cheat_name.to_upper(), level]
	if p == null:
		return head
	match id:
		"god_mode":
			if p.is_invulnerable():
				return head + ("  ∞" if float(p.invuln_left) <= 0.0 else "  %.1fs" % float(p.invuln_left))
		"noclip":
			var fuel := "∞" if p.noclip_unlimited() else "%.1fs" % float(p.noclip_fuel)
			return head + ("  FLYING " if p.noclipping else "  [V] ") + fuel
	return head
