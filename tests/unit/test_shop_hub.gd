extends GutTest
## One shop (fun pack, D65): the buy menu opens any time and slows the world;
## the buy and mod menus are two tabs, so opening one closes the other.

const BuyScene := preload("res://ui/buy_menu/buy_menu.tscn")
const ModScene := preload("res://ui/mod_menu/mod_menu.tscn")

var _buy: BuyMenu
var _mod: ModMenu


func before_each() -> void:
	Engine.time_scale = 1.0
	var ui: Control = add_child_autofree(Control.new())
	_buy = BuyScene.instantiate()
	ui.add_child(_buy)
	_mod = ModScene.instantiate()
	ui.add_child(_mod)


func after_each() -> void:
	_buy.close_menu()
	_mod.close_menu()
	Engine.time_scale = 1.0


func test_buy_menu_opens_mid_round_and_slows_time() -> void:
	EventBus.round_state_changed.emit(EventBus.ROUND_LIVE, {})
	_buy.open_menu()
	assert_true(_buy.is_open(), "not limited to freeze time any more")
	assert_almost_eq(Engine.time_scale, float(DataRegistry.economy()["mod_menu_time_scale"]), 0.0001)
	EventBus.round_state_changed.emit(EventBus.ROUND_SUMMARY, {})
	assert_true(_buy.is_open(), "round changes do not kick you out")
	_buy.close_menu()
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "restored")


func test_opening_one_tab_closes_the_other_and_keeps_one_slowdown() -> void:
	_mod.open_menu()
	_buy.open_menu()
	assert_true(_buy.is_open())
	assert_false(_mod.is_open(), "one shop: cheats tab closed")
	ShopTabs.open_in(get_tree(), "cheats")
	assert_true(_mod.is_open())
	assert_false(_buy.is_open())
	assert_almost_eq(Engine.time_scale, float(DataRegistry.economy()["mod_menu_time_scale"]), 0.0001)
	_mod.close_menu()
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "slowdown not stacked or lost")


func test_both_menus_show_the_tab_strip() -> void:
	assert_eq(_buy.find_children("*", "ShopTabs", true, false).size(), 1)
	assert_eq(_mod.find_children("*", "ShopTabs", true, false).size(), 1)
