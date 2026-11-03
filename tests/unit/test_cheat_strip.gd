extends GutTest
## CheatStrip: lists switched-on cheats and live God Mode / Noclip timers.


class FakePlayer:
	extends RefCounted
	var invuln_left := 0.0
	var permanent := false
	var noclipping := false
	var noclip_fuel := 0.0
	var unlimited := false

	func is_invulnerable() -> bool:
		return permanent or invuln_left > 0.0

	func noclip_unlimited() -> bool:
		return unlimited


var _saved: Dictionary
var _strip: CheatStrip


func before_each() -> void:
	_saved = GameState.to_dict()
	DevFlags.apply(PackedStringArray([DevFlags.UNLOCK_ALL_FLAG]), true)
	CheatSystem.set_player(null)
	_strip = add_child_autofree(CheatStrip.new())


func after_each() -> void:
	GameState.from_dict(_saved)
	CheatSystem.refresh_unlocks(false)


func test_shows_only_switched_on_cheats() -> void:
	assert_eq(_strip.shown_ids(), [], "nothing owned")
	CheatSystem.purchase("speed_hack")
	CheatSystem.purchase("speed_hack")
	assert_eq(_strip.shown_ids(), ["speed_hack"])
	assert_eq(_strip.text_for("speed_hack"), "SPEED HACK  L2")
	CheatSystem.purchase("wallhack")
	assert_eq(_strip.shown_ids(), ["speed_hack", "wallhack"], "ladder order")
	CheatSystem.set_enabled("speed_hack", false)
	assert_eq(_strip.shown_ids(), ["wallhack"], "switched off = hidden")


func test_live_timers() -> void:
	var p := FakePlayer.new()
	assert_eq(CheatStrip.chip_text("God Mode", "god_mode", 1, p), "GOD MODE  L1", "idle")
	p.invuln_left = 2.4
	assert_eq(CheatStrip.chip_text("God Mode", "god_mode", 1, p), "GOD MODE  L1  2.4s")
	p.invuln_left = 0.0
	p.permanent = true
	assert_eq(CheatStrip.chip_text("God Mode", "god_mode", 10, p), "GOD MODE  L10  ∞")
	p.noclip_fuel = 4.0
	assert_eq(CheatStrip.chip_text("Noclip", "noclip", 1, p), "NOCLIP  L1  [V] 4.0s")
	p.noclipping = true
	assert_eq(CheatStrip.chip_text("Noclip", "noclip", 1, p), "NOCLIP  L1  FLYING 4.0s")
	p.unlimited = true
	assert_eq(CheatStrip.chip_text("Noclip", "noclip", 10, p), "NOCLIP  L10  FLYING ∞")
	assert_eq(CheatStrip.chip_text("Wallhack", "wallhack", 3, null), "WALLHACK  L3")
