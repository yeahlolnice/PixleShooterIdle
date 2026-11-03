extends GutTest
## DevFlags: QA flags only work in debug builds and start a fresh in-memory game.

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()


func after_each() -> void:
	GameState.from_dict(_saved)
	CheatSystem.refresh_unlocks(false)


func test_release_builds_ignore_dev_flags() -> void:
	GameState.cash = 5.0
	assert_false(DevFlags.apply(PackedStringArray([DevFlags.CASH_FLAG, DevFlags.UNLOCK_ALL_FLAG]), false))
	assert_eq(GameState.cash, 5.0, "state untouched")


func test_no_flag_does_nothing() -> void:
	assert_false(DevFlags.apply(PackedStringArray(["--something-else"]), true))


func test_dev_cash_unlocks_first_cheats_only() -> void:
	assert_true(DevFlags.apply(PackedStringArray([DevFlags.CASH_FLAG]), true))
	assert_eq(GameState.cash, DevFlags.DEV_CASH)
	assert_true(CheatSystem.is_unlocked("wallhack"))
	assert_false(CheatSystem.is_unlocked("god_mode"), "prestige cheats stay locked")


func test_dev_unlock_all_unlocks_every_cheat_and_upgrade() -> void:
	assert_true(DevFlags.apply(PackedStringArray([DevFlags.UNLOCK_ALL_FLAG]), true))
	for cheat in CheatSystem.cheats() + CheatSystem.upgrades():
		assert_true(CheatSystem.is_unlocked(cheat.id), cheat.id)
	assert_true(CheatSystem.can_purchase("noclip"), "and enough cash to buy")
