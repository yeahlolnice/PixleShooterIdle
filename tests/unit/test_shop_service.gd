extends GutTest
## ShopService: affordability, exact deduction, already-owned handling.

var _saved: Dictionary
var gun_id: String
var price: float


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	gun_id = ShopService.catalog()[0]["id"]
	price = ShopService.price(gun_id)


func after_each() -> void:
	GameState.from_dict(_saved)


func test_catalog_excludes_starter_and_comes_from_data() -> void:
	var ids := ShopService.catalog().map(func(g): return g["id"])
	assert_false(ids.has(DataRegistry.starter_gun_id()))
	assert_eq(ids.size(), DataRegistry.guns().size() - 1)


func test_cannot_afford_refused_and_nothing_changes() -> void:
	GameState.cash = price - 1.0
	assert_eq(ShopService.buy(gun_id), ShopService.Result.CANNOT_AFFORD)
	assert_eq(GameState.cash, price - 1.0)
	assert_false(GameState.owns_gun(gun_id))
	assert_eq(GameState.equipped_gun_id, "")


func test_buy_deducts_exact_price_and_equips() -> void:
	GameState.cash = price + 7.0
	assert_eq(ShopService.buy(gun_id), ShopService.Result.OK)
	assert_eq(GameState.cash, 7.0)
	assert_true(GameState.owns_gun(gun_id))
	assert_eq(GameState.equipped_gun_id, gun_id)


func test_exact_cash_is_affordable() -> void:
	GameState.cash = price
	assert_true(ShopService.can_buy(gun_id))
	assert_eq(ShopService.buy(gun_id), ShopService.Result.OK)
	assert_eq(GameState.cash, 0.0)


func test_already_equipped_is_not_charged_twice() -> void:
	GameState.cash = price * 3.0
	ShopService.buy(gun_id)
	var left := GameState.cash
	assert_eq(ShopService.buy(gun_id), ShopService.Result.ALREADY_EQUIPPED)
	assert_eq(GameState.cash, left)


func test_owned_gun_reequips_free() -> void:
	GameState.cash = price
	ShopService.buy(gun_id)
	GameState.equipped_gun_id = ""
	assert_eq(ShopService.buy(gun_id), ShopService.Result.OK)
	assert_eq(GameState.cash, 0.0)


func test_death_clears_ownership_so_rebuy_costs_again() -> void:
	GameState.cash = price * 2.0
	ShopService.buy(gun_id)
	GameState.clear_loadout()
	assert_eq(ShopService.buy(gun_id), ShopService.Result.OK)
	assert_eq(GameState.cash, 0.0)


func test_unknown_gun() -> void:
	assert_eq(ShopService.buy("nope"), ShopService.Result.UNKNOWN_GUN)
