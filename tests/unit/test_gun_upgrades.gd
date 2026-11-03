extends GutTest
## Gun upgrades (TASK-024): cost curve, ownership and max rules, the equipped
## weapon picking them up, persistence, and surviving death.

const PlayerScene := preload("res://shooter/player/player.tscn")

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()


func after_each() -> void:
	GameState.from_dict(_saved)


func _def(stat: String) -> Dictionary:
	return DataRegistry.gun_upgrades()[stat]


func _starter() -> String:
	return DataRegistry.starter_gun_id()


func _paid_gun() -> String:
	return ShopService.catalog()[0]["id"]


func test_tracks_come_from_data() -> void:
	assert_true(ShopService.upgrade_stats().has("damage"))
	assert_true(ShopService.upgrade_stats().has("fire_rate"))


func test_cost_uses_min_base_for_the_free_starter_and_grows() -> void:
	var d := _def("damage")
	var first := float(d["min_base_cost"]) * float(d["cost_mult"])
	assert_almost_eq(ShopService.upgrade_cost(_starter(), "damage"), first, 0.001)
	GameState.set_gun_upgrade_level(_starter(), "damage", 2)
	assert_almost_eq(ShopService.upgrade_cost(_starter(), "damage"), first * pow(float(d["cost_growth"]), 2), 0.001)


func test_must_own_the_gun_and_afford_it() -> void:
	GameState.cash = 1e9
	assert_eq(ShopService.check_upgrade(_paid_gun(), "damage"), ShopService.Result.NOT_OWNED)
	GameState.add_owned_gun(_paid_gun())
	assert_eq(ShopService.check_upgrade(_paid_gun(), "damage"), ShopService.Result.OK)
	GameState.cash = 0
	assert_eq(ShopService.check_upgrade(_starter(), "damage"), ShopService.Result.CANNOT_AFFORD)
	assert_eq(ShopService.check_upgrade(_starter(), "nope"), ShopService.Result.UNKNOWN_STAT)


func test_buy_spends_levels_up_signals_and_maxes() -> void:
	GameState.cash = 1e9
	watch_signals(EventBus)
	var cost := ShopService.upgrade_cost(_starter(), "damage")
	assert_eq(ShopService.buy_upgrade(_starter(), "damage"), ShopService.Result.OK)
	assert_almost_eq(GameState.cash, 1e9 - cost, 0.01)
	assert_eq(ShopService.upgrade_level(_starter(), "damage"), 1)
	assert_signal_emitted_with_parameters(EventBus, "gun_upgraded", [_starter(), "damage", 1])
	assert_almost_eq(ShopService.upgrade_mult(_starter(), "damage"), 1.0 + float(_def("damage")["step"]), 0.0001)
	for i in int(_def("damage")["max_level"]):
		ShopService.buy_upgrade(_starter(), "damage")
	assert_eq(ShopService.upgrade_level(_starter(), "damage"), int(_def("damage")["max_level"]))
	assert_eq(ShopService.buy_upgrade(_starter(), "damage"), ShopService.Result.MAXED)


func test_equipped_weapon_gets_upgrades_at_once_and_on_equip() -> void:
	GameState.cash = 1e9
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	var wm: WeaponManager = p.get_node("WeaponManager")
	wm.equip(_starter())
	var base_damage := wm.weapon.damage()
	var base_interval := wm.weapon.fire_interval()
	ShopService.buy_upgrade(_starter(), "damage")
	ShopService.buy_upgrade(_starter(), "fire_rate")
	assert_almost_eq(wm.weapon.damage(), base_damage * ShopService.upgrade_mult(_starter(), "damage"), 0.0001)
	assert_lt(wm.weapon.fire_interval(), base_interval, "fires faster")
	wm.equip(_starter())
	assert_almost_eq(wm.weapon.damage(), base_damage * ShopService.upgrade_mult(_starter(), "damage"), 0.0001, "kept on re-equip")


func test_upgrades_persist_and_survive_death() -> void:
	GameState.set_gun_upgrade_level(_paid_gun(), "fire_rate", 3)
	var copy := GameState.to_dict()
	GameState.new_game()
	GameState.from_dict(copy)
	assert_eq(ShopService.upgrade_level(_paid_gun(), "fire_rate"), 3, "saved and loaded")
	GameState.add_owned_gun(_paid_gun())
	GameState.clear_loadout()
	assert_eq(ShopService.upgrade_level(_paid_gun(), "fire_rate"), 3, "death loses the gun, not the upgrades")
