class_name ModMenu
extends Control
## In-match mod menu (the cheat shop), toggled with the mod_menu action (Insert)
## at any time. Styled as a sketchy injected cheat menu (ui/theme/hax_theme.gd).
## Tabs and rows are built from cheats.json via CheatSystem; every row shows a
## toggle switch, level, price and buy/upgrade button, or "???" plus the unlock
## requirement while locked. Server Slots (an upgrade) sits on its own tab row.
##
## All rules live in CheatSystem: this script only reads its queries and calls
## purchase() / set_enabled(). While open, Engine.time_scale drops to
## economy.json "mod_menu_time_scale" and the previous value is restored on close.
##
## Tests can call build(tabs, entries) with CheatBase entries from a fixture.

const MENU_ID := &"mod_menu"
const PANEL_SIZE := Vector2(720, 460)
## Cosmetic length of the fake injector bar (real seconds, ignores time scale).
const INJECT_SECONDS := 1.2
const NUMBER_SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

var _tabs: TabContainer
var _cash_label: Label
var _inject_panel: PanelContainer
var _inject_label: Label
var _inject_bar: ProgressBar
var _inject_tween: Tween
var _rows: Dictionary = {}          # id -> {cheat, tab, toggle, name, level, button}
var _tab_pages: Dictionary = {}     # tab name -> VBoxContainer
var _saved_time_scale := 1.0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = HaxTheme.build()
	_build_shell()
	build(DataRegistry.cheat_tabs(), _system_entries())
	EventBus.cash_changed.connect(func(_t, _d): refresh())
	EventBus.kills_changed.connect(func(_k, _l): refresh())
	EventBus.cheat_unlocked.connect(func(_id): refresh())
	EventBus.cheat_toggled.connect(func(_id, _on): refresh())
	EventBus.cheat_purchased.connect(_on_cheat_purchased)
	EventBus.game_state_loaded.connect(refresh)


func _exit_tree() -> void:
	if visible:
		Engine.time_scale = _saved_time_scale


# --- Building ------------------------------------------------------------------

func _system_entries() -> Array:
	var entries: Array = []
	entries.append_array(CheatSystem.cheats())
	entries.append_array(CheatSystem.upgrades())
	return entries


func _build_shell() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "x_Hax_x INTERNAL v0.69  ::  [INSERT] hide"
	title.add_theme_color_override("font_color", DataRegistry.color("neon"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_cash_label = Label.new()
	_cash_label.add_theme_color_override("font_color", DataRegistry.color("cash"))
	header.add_child(_cash_label)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.focus_mode = Control.FOCUS_NONE
	box.add_child(_tabs)

	_inject_panel = PanelContainer.new()
	_inject_panel.visible = false
	box.add_child(_inject_panel)
	var inject_box := VBoxContainer.new()
	_inject_panel.add_child(inject_box)
	_inject_label = Label.new()
	inject_box.add_child(_inject_label)
	_inject_bar = ProgressBar.new()
	_inject_bar.custom_minimum_size = Vector2(0, 18)
	inject_box.add_child(_inject_bar)


## (Re)builds one tab per name in `tabs` and one row per CheatBase in `entries`
## (cheats and upgrades), each row on its cheat's tab, sorted by order.
func build(tabs: Array, entries: Array) -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_rows.clear()
	_tab_pages.clear()
	for tab_name in tabs:
		var scroll := ScrollContainer.new()
		scroll.name = str(tab_name)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 6)
		scroll.add_child(page)
		_tab_pages[str(tab_name)] = page
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a, b): return a.order < b.order)
	for cheat in sorted:
		if not _tab_pages.has(cheat.tab):
			push_warning("[ModMenu] '%s' has unknown tab '%s'" % [cheat.id, cheat.tab])
			continue
		_add_row(cheat)
	refresh()


func _add_row(cheat: CheatBase) -> void:
	var row := HBoxContainer.new()
	row.name = cheat.id
	row.add_theme_constant_override("separation", 12)
	_tab_pages[cheat.tab].add_child(row)
	var toggle := CheckButton.new()
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(_on_toggle.bind(cheat.id))
	row.add_child(toggle)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var level_label := Label.new()
	level_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(level_label)
	var button := Button.new()
	button.custom_minimum_size = Vector2(170, 0)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_buy.bind(cheat.id))
	row.add_child(button)
	_rows[cheat.id] = {"cheat": cheat, "tab": cheat.tab, "toggle": toggle,
		"name": name_label, "level": level_label, "button": button}


# --- Queries (tests) -------------------------------------------------------------

func tab_names() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _tabs.get_children():
		out.append(child.name)
	return out


func row_count() -> int:
	return _rows.size()


func row_ids(tab_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	if _tab_pages.has(tab_name):
		for row in _tab_pages[tab_name].get_children():
			if not row.is_queued_for_deletion():
				out.append(row.name)
	return out


## The widgets of one row: {cheat, tab, toggle, name, level, button}, or {}.
func row(id: String) -> Dictionary:
	return _rows.get(id, {})


func is_open() -> bool:
	return visible


# --- Open / close ----------------------------------------------------------------

func open_menu() -> void:
	if visible:
		return
	visible = true
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = float(DataRegistry.economy().get("mod_menu_time_scale", 1.0))
	refresh()
	EventBus.menu_toggled.emit(MENU_ID, true)


func close_menu() -> void:
	if not visible:
		return
	visible = false
	Engine.time_scale = _saved_time_scale
	EventBus.menu_toggled.emit(MENU_ID, false)


func toggle_menu() -> void:
	if visible:
		close_menu()
	else:
		open_menu()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mod_menu"):
		toggle_menu()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		close_menu()
		get_viewport().set_input_as_handled()


# --- Actions (all through CheatSystem) -------------------------------------------

func _on_buy(id: String) -> void:
	CheatSystem.purchase(id)
	refresh()


func _on_toggle(on: bool, id: String) -> void:
	CheatSystem.set_enabled(id, on)
	refresh()


func _on_cheat_purchased(id: String, new_level: int) -> void:
	if new_level == 1 and not CheatSystem.is_upgrade(id):
		_play_injection(id)
	refresh()


## Fake injector bar on the first purchase of a cheat. Purely cosmetic: the
## cheat is already active; the bar runs in real time despite the slow-mo.
func _play_injection(id: String) -> void:
	var cheat := CheatSystem.get_cheat(id)
	_inject_label.text = "injecting %s.dll into game.exe ... bypassing anti-cheat" % (cheat.id if cheat else id)
	_inject_bar.value = 0.0
	_inject_panel.visible = true
	if _inject_tween:
		_inject_tween.kill()
	_inject_tween = create_tween()
	_inject_tween.set_ignore_time_scale(true)
	_inject_tween.tween_property(_inject_bar, "value", _inject_bar.max_value, INJECT_SECONDS)
	_inject_tween.tween_callback(func(): _inject_label.text = "%s injected. undetected (for now)" % (cheat.display_name if cheat else id))
	_inject_tween.tween_interval(INJECT_SECONDS * 0.5)
	_inject_tween.tween_callback(func(): _inject_panel.visible = false)


func is_injecting() -> bool:
	return _inject_panel.visible


# --- Display ---------------------------------------------------------------------

## Redraws every row from CheatSystem state (prices, levels, switches, locks).
func refresh() -> void:
	if _cash_label == null:
		return
	_cash_label.text = "$" + short_number(GameState.cash)
	for id in _rows:
		_refresh_row(_rows[id])


func _refresh_row(r: Dictionary) -> void:
	var cheat: CheatBase = r["cheat"]
	var id := cheat.id
	var toggle: CheckButton = r["toggle"]
	var button: Button = r["button"]
	var lvl := CheatSystem.level(id)
	var unlocked := CheatSystem.get_cheat(id) != null and CheatSystem.is_unlocked(id)
	if not unlocked:
		r["name"].text = "???"
		r["level"].text = requirement_text(cheat)
		toggle.set_pressed_no_signal(false)
		toggle.disabled = true
		button.text = "LOCKED"
		button.disabled = true
		return
	r["name"].text = cheat.display_name
	r["level"].text = "LV %d/%d" % [lvl, cheat.max_level]
	toggle.set_pressed_no_signal(CheatSystem.is_enabled(id))
	toggle.disabled = lvl == 0 or CheatSystem.is_upgrade(id)
	if CheatSystem.is_maxed(id):
		button.text = "MAXED"
		button.disabled = true
	else:
		button.text = "%s $%s" % ["BUY" if lvl == 0 else "UPGRADE", short_number(CheatSystem.next_cost(id))]
		button.disabled = not CheatSystem.can_purchase(id)


## "needs 400 kills" or "needs ban #2" from the cheat's unlock rule.
static func requirement_text(cheat: CheatBase) -> String:
	var req := cheat.unlock_requirement()
	if req.has("prestige"):
		return "needs ban #%d" % int(req["prestige"])
	return "needs %s kills" % short_number(float(req["kills"]))


## Short display: 950, 1.2K, 3.4M, ... (one decimal, rounded down, above 1000).
static func short_number(value: float) -> String:
	var v := absf(value)
	var prefix := "-" if value < 0.0 else ""
	if v < 1000.0:
		return prefix + str(int(floor(v)))
	var tier := 0
	while v >= 1000.0 and tier < NUMBER_SUFFIXES.size() - 1:
		v /= 1000.0
		tier += 1
	# Floor to one decimal so cash is never shown higher than it is.
	var text := "%.1f" % (floor(v * 10.0 + 0.000001) / 10.0)
	if text.ends_with(".0"):
		text = text.left(-2)
	return prefix + text + NUMBER_SUFFIXES[tier]
