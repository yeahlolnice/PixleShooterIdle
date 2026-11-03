extends GutTest
## ModMenu: tabs/rows built from a fixture cheats.json and from the real data,
## locked rows, live prices, toggles through CheatSystem, Insert + time scale.

const FIXTURE := "res://tests/fixtures/mod_menu/cheats.json"
const MENU_SCENE := "res://ui/mod_menu/mod_menu.tscn"

var _menu: ModMenu
var _saved: Dictionary
var _saved_scale: float


func before_each() -> void:
	_saved = GameState.to_dict()
	_saved_scale = Engine.time_scale
	GameState.new_game()
	CheatSystem.refresh_unlocks(false)
	_menu = load(MENU_SCENE).instantiate()
	add_child_autofree(_menu)
	watch_signals(EventBus)


func after_each() -> void:
	_menu.close_menu()
	Engine.time_scale = _saved_scale
	GameState.from_dict(_saved)
	CheatSystem.refresh_unlocks(false)


func _fixture() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var entries: Array = []
	for def in data["cheats"] + data["upgrades"]:
		entries.append(CheatBase.from_def(def, float(data["cost_growth"])))
	return {"tabs": data["tabs"], "entries": entries}


# --- Building ---------------------------------------------------------------------

func test_builds_tabs_and_rows_from_fixture() -> void:
	var fx := _fixture()
	_menu.build(fx["tabs"], fx["entries"])
	assert_eq(Array(_menu.tab_names()), ["Movement", "Visuals", "Combat"])
	assert_eq(_menu.row_count(), 4)
	assert_eq(Array(_menu.row_ids("Movement")), ["fx_jump", "fx_speed"], "rows sorted by order")
	assert_eq(Array(_menu.row_ids("Visuals")), ["fx_glow"])
	assert_eq(Array(_menu.row_ids("Combat")), ["fx_slots"], "upgrades get rows too")


func test_fixture_rows_unknown_to_cheat_system_show_locked_requirement() -> void:
	var fx := _fixture()
	_menu.build(fx["tabs"], fx["entries"])
	assert_eq(_menu.row("fx_speed")["name"].text, "???")
	assert_eq(_menu.row("fx_speed")["level"].text, "needs 5 kills")
	assert_eq(_menu.row("fx_glow")["level"].text, "needs ban #2")
	assert_true(_menu.row("fx_glow")["button"].disabled)


func test_real_data_builds_every_cheat_and_server_slots_on_rage() -> void:
	assert_eq(Array(_menu.tab_names()), DataRegistry.cheat_tabs())
	assert_eq(_menu.row_count(), DataRegistry.cheats().size() + DataRegistry.cheat_upgrades().size())
	assert_true(_menu.row_ids("Rage").has(CheatSystem.SERVER_SLOTS_ID))
	for c in DataRegistry.cheats():
		assert_true(_menu.row_ids(c["tab"]).has(c["id"]), "%s on tab %s" % [c["id"], c["tab"]])


# --- Locks, prices, toggles (real CheatSystem) -----------------------------------

func test_locked_cheat_shows_requirement_then_unlocks() -> void:
	var r := _menu.row("god_mode")
	assert_eq(r["name"].text, "???")
	assert_eq(r["level"].text, "needs ban #1")
	var speed: CheatBase = CheatSystem.get_cheat("speed_hack")
	assert_eq(_menu.row("speed_hack")["level"].text, ModMenu.requirement_text(speed))
	GameState.lifetime_kills = speed.unlock_kills
	CheatSystem.refresh_unlocks()
	assert_eq(_menu.row("speed_hack")["name"].text, speed.display_name, "refreshes on cheat_unlocked")


func test_purchase_and_upgrade_update_price_live() -> void:
	var speed: CheatBase = CheatSystem.get_cheat("speed_hack")
	GameState.lifetime_kills = speed.unlock_kills
	CheatSystem.refresh_unlocks(false)
	_menu.refresh()
	var button: Button = _menu.row("speed_hack")["button"]
	assert_true(button.disabled, "too poor")
	GameState.add_cash(speed.cost(0) + speed.cost(1))
	assert_false(button.disabled, "cash_changed refreshes")
	assert_eq(button.text, "BUY $" + ModMenu.short_number(speed.cost(0)))
	button.pressed.emit()
	assert_eq(CheatSystem.level("speed_hack"), 1)
	assert_eq(button.text, "UPGRADE $" + ModMenu.short_number(speed.cost(1)))
	assert_true(_menu.is_injecting(), "fake injector bar on first purchase")
	button.pressed.emit()
	assert_eq(CheatSystem.level("speed_hack"), 2)
	assert_eq(button.text, "UPGRADE $" + ModMenu.short_number(speed.cost(2)))
	assert_true(button.disabled, "cannot afford level 3")
	assert_eq(_menu.row("speed_hack")["level"].text, "LV 2/%d" % speed.max_level)


func test_toggle_switch_goes_through_cheat_system() -> void:
	var speed: CheatBase = CheatSystem.get_cheat("speed_hack")
	GameState.lifetime_kills = speed.unlock_kills
	CheatSystem.refresh_unlocks(false)
	var toggle: CheckButton = _menu.row("speed_hack")["toggle"]
	_menu.refresh()
	assert_true(toggle.disabled, "unowned cheats cannot be toggled")
	GameState.add_cash(speed.cost(0))
	assert_true(CheatSystem.purchase("speed_hack"))
	assert_true(toggle.button_pressed, "on after first purchase")
	toggle.button_pressed = false
	assert_false(CheatSystem.is_enabled("speed_hack"))
	assert_signal_emitted_with_parameters(EventBus, "cheat_toggled", ["speed_hack", false])
	toggle.button_pressed = true
	assert_true(CheatSystem.is_enabled("speed_hack"))


# --- Open / close ---------------------------------------------------------------

func test_insert_toggles_menu_and_time_scale() -> void:
	Engine.time_scale = 1.0
	var press := InputEventAction.new()
	press.action = "mod_menu"
	press.pressed = true
	_menu._input(press)
	assert_true(_menu.is_open())
	assert_almost_eq(Engine.time_scale, float(DataRegistry.economy()["mod_menu_time_scale"]), 0.0001)
	assert_signal_emitted_with_parameters(EventBus, "menu_toggled", [ModMenu.MENU_ID, true])
	_menu._input(press)
	assert_false(_menu.is_open())
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001)
	assert_signal_emitted_with_parameters(EventBus, "menu_toggled", [ModMenu.MENU_ID, false])


func test_short_number() -> void:
	assert_eq(ModMenu.short_number(0), "0")
	assert_eq(ModMenu.short_number(999.9), "999")
	assert_eq(ModMenu.short_number(1000), "1K")
	assert_eq(ModMenu.short_number(1299), "1.2K", "rounds down")
	assert_eq(ModMenu.short_number(1300), "1.3K")
	assert_eq(ModMenu.short_number(-1500), "-1.5K")
	assert_eq(ModMenu.short_number(6000000), "6M")
