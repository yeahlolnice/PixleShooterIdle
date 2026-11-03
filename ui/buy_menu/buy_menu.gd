class_name BuyMenu
extends Control
## Counter-Strike-style buy menu. Opens with the buy_menu action (B) during
## freeze time only and closes when the round goes live. Purchase rules live in
## ShopService; this only draws one row per gun category (guns.json "category",
## in CATEGORY_ORDER) and equips through WeaponManager. Number keys 1-9 buy in
## on-screen order. Locked guns show the kills they need.

const CATEGORY_ORDER := ["pistol", "smg", "shotgun", "rifle", "sniper", "lmg", "special"]
const CATEGORY_NAMES := {"pistol": "PISTOLS", "smg": "SMGS", "shotgun": "SHOTGUNS", "rifle": "RIFLES",
	"sniper": "SNIPERS", "lmg": "MACHINE GUNS", "special": "SPECIAL"}

## Set by Main; the menu equips the bought gun here.
var weapon_manager: WeaponManager

var _freeze := false
var _rows: VBoxContainer
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
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	box.add_child(_rows)
	_feedback = Label.new()
	box.add_child(_feedback)
	_build_buttons()
	EventBus.round_state_changed.connect(_on_round_state)
	EventBus.cash_changed.connect(func(_t, _d): _refresh())
	EventBus.gun_equipped.connect(func(_id): _refresh())
	EventBus.kills_changed.connect(func(_k, _l): _refresh())


func _build_buttons() -> void:
	var i := 1
	for cat in categories(ShopService.catalog()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var header := Label.new()
		header.text = CATEGORY_NAMES.get(cat, String(cat).to_upper())
		header.custom_minimum_size = Vector2(130, 0)
		header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(header)
		for g in ShopService.catalog():
			if String(g.get("category", "pistol")) != cat:
				continue
			var b := Button.new()
			b.custom_minimum_size = Vector2(200, 70)
			b.add_theme_font_size_override("font_size", 13)
			b.set_meta("label", _label(g, i))
			b.text = b.get_meta("label")
			b.pressed.connect(_buy.bind(g["id"]))
			row.add_child(b)
			_buttons[g["id"]] = b
			i += 1
		_rows.add_child(row)


## Categories present in `guns`, in CATEGORY_ORDER (unknown ones last, in data order).
static func categories(guns: Array) -> Array:
	var present: Array = []
	for g in guns:
		var c := String(g.get("category", "pistol"))
		if not present.has(c):
			present.append(c)
	var out: Array = []
	for c in CATEGORY_ORDER:
		if present.has(c):
			out.append(c)
	for c in present:
		if not out.has(c):
			out.append(c)
	return out


static func _label(g: Dictionary, index: int) -> String:
	var pellets := int(g.get("pellets", 1))
	var dps := float(g["damage"]) * pellets * float(g["fire_rate"])
	var dmg := "%d" % int(g["damage"]) if pellets == 1 else "%d×%d" % [int(g["damage"]), pellets]
	return "[%d] %s\n%s\n%s dmg · %.0f dps · %d rnd" % [index, g["name"], Fmt.cash(float(g["price"])), dmg, dps, int(g["mag_size"])]


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
	_cash_label.text = "Cash: " + Fmt.cash(GameState.cash)
	for id in _buttons:
		var b: Button = _buttons[id]
		var r := ShopService.check(id)
		b.disabled = r == ShopService.Result.CANNOT_AFFORD or r == ShopService.Result.LOCKED
		b.tooltip_text = ShopService.message(r)
		var need := int(DataRegistry.gun(id).get("unlock_kills", 0))
		b.text = String(b.get_meta("label")) + ("\nneeds %s kills" % Fmt.number(need) if r == ShopService.Result.LOCKED else "")
