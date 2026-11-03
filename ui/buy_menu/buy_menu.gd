class_name BuyMenu
extends Control
## Counter-Strike-style buy menu. Opens with the buy_menu action (B) during
## freeze time only and closes when the round goes live. Purchase rules live in
## ShopService; this only draws the grid and equips through WeaponManager.

## Set by Main; the menu equips the bought gun here.
var weapon_manager: WeaponManager

var _freeze := false
var _grid: GridContainer
var _cash_label: Label
var _feedback: Label
var _buttons: Dictionary = {}  # gun_id -> Button


func _ready() -> void:
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Label.new()
	title.text = "BUY MENU  (B to close)"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_cash_label = Label.new()
	box.add_child(_cash_label)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	box.add_child(_grid)
	_feedback = Label.new()
	box.add_child(_feedback)
	_build_buttons()
	EventBus.round_state_changed.connect(_on_round_state)
	EventBus.cash_changed.connect(func(_t, _d): _refresh())
	EventBus.gun_equipped.connect(func(_id): _refresh())
	EventBus.kills_changed.connect(func(_k, _l): _refresh())


func _build_buttons() -> void:
	var i := 1
	for g in ShopService.catalog():
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 110)
		b.text = _label(g, i)
		b.pressed.connect(_buy.bind(g["id"]))
		_grid.add_child(b)
		_buttons[g["id"]] = b
		i += 1


static func _label(g: Dictionary, index: int) -> String:
	var dps := float(g["damage"]) * float(g["fire_rate"])
	return "[%d] %s\n$%d\n%d dmg · %.0f dps · %d rnd" % [index, g["name"], int(g["price"]), int(g["damage"]), dps, int(g["mag_size"])]


func is_open() -> bool:
	return visible


func open_menu() -> void:
	if not _freeze or visible:
		return
	visible = true
	_feedback.text = ""
	_refresh()
	EventBus.menu_toggled.emit(&"buy_menu", true)


func close_menu() -> void:
	if not visible:
		return
	visible = false
	EventBus.menu_toggled.emit(&"buy_menu", false)


func _on_round_state(state: StringName, _info: Dictionary) -> void:
	_freeze = state == EventBus.ROUND_FREEZE
	if not _freeze:
		close_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("buy_menu"):
		if visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.keycode - KEY_1
		var ids := _buttons.keys()
		if n >= 0 and n < 9 and n < ids.size():
			_buy(ids[n])
			get_viewport().set_input_as_handled()


func _buy(gun_id: String) -> void:
	var r := ShopService.buy(gun_id)
	_feedback.text = ShopService.message(r)
	if r == ShopService.Result.OK:
		if weapon_manager:
			weapon_manager.equip(gun_id)
		else:
			EventBus.gun_equipped.emit(gun_id)
	_refresh()


func _refresh() -> void:
	if _cash_label == null:
		return
	_cash_label.text = "Cash: $%d" % int(GameState.cash)
	for id in _buttons:
		var b: Button = _buttons[id]
		var r := ShopService.check(id)
		b.disabled = r == ShopService.Result.CANNOT_AFFORD or r == ShopService.Result.LOCKED
		b.tooltip_text = ShopService.message(r)
