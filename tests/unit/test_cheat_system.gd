extends GutTest
## CheatSystem + CheatBase: data coverage, cost curve, unlock thresholds,
## prestige locks, purchase/toggle with mock player and weapon, persistence.
## Expected values are read from data/cheats.json, never re-typed here, except
## the plan's fixed rules (ladder order, prestige 1/2/3 for the last three).

const PLAN_LADDER := [
	"speed_hack", "infinite_ammo", "auto_bhop", "wallhack", "no_recoil", "triggerbot",
	"hitbox_expander", "aimbot", "loot_magnet", "god_mode", "spinbot", "noclip",
]
const PRESTIGE_CHEATS := {"god_mode": 1, "spinbot": 2, "noclip": 3}


class MockWeapon:
	extends RefCounted
	var modifiers := {"mag_mult": 1.0, "recoil_mult": 1.0, "spread_mult": 1.0, "infinite_reload": false}

	func set_modifier(key: String, value: Variant) -> void:
		modifiers[key] = value


class MockPlayer:
	extends RefCounted
	var stat_mods := {}
	var weapon := MockWeapon.new()
	var log: Array = []

	func set_stat_mod(mod_name: StringName, value: float) -> void:
		stat_mods[mod_name] = value
		log.append(["set", mod_name, value])

	func clear_stat_mod(mod_name: StringName) -> void:
		stat_mods.erase(mod_name)
		log.append(["clear", mod_name])

	func get_stat_mod(mod_name: StringName) -> float:
		return stat_mods.get(mod_name, 1.0)

	func get_weapon() -> Object:
		return weapon


var _saved: Dictionary
var _saved_player: Object
var _player: MockPlayer


func before_each() -> void:
	_saved = GameState.to_dict()
	_saved_player = CheatSystem.get_player()
	GameState.new_game()
	CheatSystem.refresh_unlocks(false)
	_player = MockPlayer.new()
	CheatSystem.set_player(_player)
	watch_signals(EventBus)


func after_each() -> void:
	GameState.from_dict(_saved)
	CheatSystem.refresh_unlocks(false)
	CheatSystem.set_player(_saved_player)


func _unlock_all_and_fund(cash: float = 1e12) -> void:
	GameState.lifetime_kills = 1000000000
	GameState.prestige_count = 3
	GameState.cash = cash
	CheatSystem.refresh_unlocks(false)


# --- Data ------------------------------------------------------------------------

func test_all_twelve_cheats_and_server_slots_are_in_data() -> void:
	var ids: Array = []
	for c in CheatSystem.cheats():
		ids.append(c.id)
	assert_eq(ids, PLAN_LADDER, "12 cheats in plan ladder order")
	assert_not_null(CheatSystem.get_cheat("server_slots"))
	assert_true(CheatSystem.is_upgrade("server_slots"))
	for c in CheatSystem.cheats() + CheatSystem.upgrades():
		assert_true(DataRegistry.cheat_tabs().has(c.tab), "%s tab" % c.id)
		assert_gt(c.max_level, 0, "%s max_level" % c.id)
		assert_false(c.effects.is_empty(), "%s has effects" % c.id)
	var errors := PackedStringArray()
	DataRegistry.validate_cheats(DataRegistry.get_file("cheats"), errors)
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_validation_reports_bad_cheat_entries() -> void:
	var data: Dictionary = DataRegistry.get_file("cheats").duplicate(true)
	data["cheats"][0]["tab"] = "Nope"
	data["cheats"][1]["unlock"] = {"kills": 1, "prestige": 1}
	data["cheats"][2]["effects"][0]["curve"] = "wobbly"
	data["cheats"][3]["id"] = data["cheats"][0]["id"]
	var errors := PackedStringArray()
	DataRegistry.validate_cheats(data, errors)
	var joined := "\n".join(errors)
	assert_string_contains(joined, "cheats[0].tab: 'Nope'")
	assert_string_contains(joined, "cheats[1].unlock")
	assert_string_contains(joined, "cheats[2].effects[0].curve")
	assert_string_contains(joined, "cheats[3].id: duplicate")


# --- Cost curve ------------------------------------------------------------------

func test_cost_follows_base_times_growth_pow_level() -> void:
	var growth := float(DataRegistry.get_file("cheats")["cost_growth"])
	assert_almost_eq(growth, 1.15, 0.0001, "plan growth lives in data")
	for def in DataRegistry.cheats() + DataRegistry.cheat_upgrades():
		var cheat := CheatSystem.get_cheat(def["id"])
		for lvl in [0, 1, 2, 5, cheat.max_level - 1]:
			var expected := float(def["base_cost"]) * pow(growth, lvl)
			assert_almost_eq(cheat.cost(lvl), expected, expected * 1e-9, "%s cost(%d)" % [cheat.id, lvl])


func test_purchase_charges_next_cost_and_upgrades() -> void:
	_unlock_all_and_fund()
	var cheat := CheatSystem.get_cheat("speed_hack")
	var start := GameState.cash
	assert_true(CheatSystem.purchase("speed_hack"))
	assert_true(CheatSystem.purchase("speed_hack"))
	assert_eq(CheatSystem.level("speed_hack"), 2)
	assert_almost_eq(GameState.cash, start - cheat.cost(0) - cheat.cost(1), 0.001)
	assert_almost_eq(CheatSystem.next_cost("speed_hack"), cheat.cost(2), 0.001)
	assert_signal_emitted_with_parameters(EventBus, "cheat_purchased", ["speed_hack", 2])


func test_purchase_fails_when_poor_locked_or_maxed() -> void:
	GameState.cash = 1e12
	assert_false(CheatSystem.purchase("speed_hack"), "locked at 0 kills")
	_unlock_all_and_fund(CheatSystem.next_cost("speed_hack") - 1.0)
	assert_false(CheatSystem.purchase("speed_hack"), "too poor")
	assert_eq(CheatSystem.level("speed_hack"), 0)
	GameState.cash = 1e15
	var cheat := CheatSystem.get_cheat("speed_hack")
	for i in range(cheat.max_level):
		assert_true(CheatSystem.purchase("speed_hack"))
	var cash := GameState.cash
	assert_false(CheatSystem.purchase("speed_hack"), "maxed")
	assert_eq(GameState.cash, cash)
	assert_false(CheatSystem.purchase("not_a_cheat"))


# --- Unlocks ---------------------------------------------------------------------

func test_kill_unlocks_follow_lifetime_kill_thresholds() -> void:
	for def in DataRegistry.cheats() + DataRegistry.cheat_upgrades():
		if not def["unlock"].has("kills"):
			continue
		var need := int(def["unlock"]["kills"])
		GameState.lifetime_kills = need - 1
		assert_eq(CheatSystem.is_unlocked(def["id"]), need == 0, "%s at %d kills" % [def["id"], need - 1])
		GameState.lifetime_kills = need
		assert_true(CheatSystem.is_unlocked(def["id"]), "%s at %d kills" % [def["id"], need])


func test_unlock_signal_fires_once_when_threshold_crossed() -> void:
	var need := int(DataRegistry.cheat("speed_hack")["unlock"]["kills"])
	GameState.lifetime_kills = need - 1
	CheatSystem.refresh_unlocks(false)
	GameState.add_kill()
	assert_signal_emitted_with_parameters(EventBus, "cheat_unlocked", ["speed_hack"])
	var count: int = get_signal_emit_count(EventBus, "cheat_unlocked")
	GameState.add_kill()
	assert_eq(get_signal_emit_count(EventBus, "cheat_unlocked"), count, "no repeat")


func test_prestige_cheats_locked_below_their_ban_count() -> void:
	GameState.lifetime_kills = 1000000000
	for id in PRESTIGE_CHEATS:
		var bans: int = PRESTIGE_CHEATS[id]
		assert_eq(int(DataRegistry.cheat(id)["unlock"].get("prestige", -1)), bans, "%s data rule" % id)
		for p in range(bans):
			GameState.prestige_count = p
			assert_false(CheatSystem.is_unlocked(id), "%s locked at prestige %d" % [id, p])
		GameState.prestige_count = bans
		assert_true(CheatSystem.is_unlocked(id), "%s unlocked at prestige %d" % [id, bans])


func test_kills_alone_never_unlock_prestige_cheats() -> void:
	GameState.lifetime_kills = 1000000000
	GameState.prestige_count = 0
	GameState.cash = 1e15
	for id in PRESTIGE_CHEATS:
		assert_false(CheatSystem.purchase(id), id)


# --- Toggle apply/remove ---------------------------------------------------------

func test_first_purchase_enables_and_applies() -> void:
	_unlock_all_and_fund()
	assert_false(CheatSystem.any_cheat_active())
	CheatSystem.purchase("speed_hack")
	var cheat := CheatSystem.get_cheat("speed_hack")
	assert_true(CheatSystem.is_enabled("speed_hack"))
	assert_true(CheatSystem.any_cheat_active())
	assert_almost_eq(_player.get_stat_mod(&"move_speed_mult"), float(cheat.value_at("move_speed_mult", 1)), 0.0001)
	assert_signal_emitted_with_parameters(EventBus, "cheat_toggled", ["speed_hack", true])


func test_toggle_off_removes_and_on_reapplies() -> void:
	_unlock_all_and_fund()
	CheatSystem.purchase("speed_hack")
	CheatSystem.purchase("infinite_ammo")
	assert_gt(float(_player.weapon.modifiers["mag_mult"]), 1.0)
	assert_true(CheatSystem.set_enabled("speed_hack", false))
	assert_false(_player.stat_mods.has(&"move_speed_mult"), "remove() restores base")
	assert_eq(_player.log.back(), ["clear", &"move_speed_mult"])
	assert_signal_emitted_with_parameters(EventBus, "cheat_toggled", ["speed_hack", false])
	assert_false(GameState.cheat_enabled["speed_hack"])
	assert_true(CheatSystem.any_cheat_active(), "ammo still on")
	CheatSystem.toggle("infinite_ammo")
	assert_eq(_player.weapon.modifiers["mag_mult"], 1.0)
	assert_eq(_player.weapon.modifiers["infinite_reload"], false)
	assert_false(CheatSystem.any_cheat_active())
	CheatSystem.toggle("speed_hack")
	assert_true(_player.stat_mods.has(&"move_speed_mult"))
	assert_eq(CheatSystem.level("speed_hack"), 1, "toggling never changes level")


func test_cannot_toggle_unowned_or_upgrades() -> void:
	_unlock_all_and_fund()
	assert_false(CheatSystem.set_enabled("wallhack", true))
	CheatSystem.purchase("server_slots")
	assert_false(CheatSystem.toggle("server_slots"))
	assert_false(CheatSystem.any_cheat_active(), "upgrades are not cheats for legit mode")


func test_cheats_reapply_when_player_spawns() -> void:
	_unlock_all_and_fund()
	CheatSystem.purchase("speed_hack")
	CheatSystem.purchase("no_recoil")
	CheatSystem.set_enabled("no_recoil", false)
	var fresh := MockPlayer.new()
	EventBus.player_spawned.emit(fresh)
	assert_true(fresh.stat_mods.has(&"move_speed_mult"))
	assert_eq(fresh.weapon.modifiers["recoil_mult"], 1.0, "disabled cheat not applied")


func test_max_level_values_and_bool_flags() -> void:
	var ammo := CheatSystem.get_cheat("infinite_ammo")
	var flag := ammo.effect_def("infinite_reload")
	assert_false(ammo.value_at("infinite_reload", int(flag["from_level"]) - 1))
	assert_true(ammo.value_at("infinite_reload", ammo.max_level))
	var aimbot := CheatSystem.get_cheat("aimbot")
	var fov := aimbot.effect_def("fov_deg")
	assert_almost_eq(float(aimbot.value_at("fov_deg", 1)), float(fov["from"]), 0.0001)
	assert_almost_eq(float(aimbot.value_at("fov_deg", aimbot.max_level)), float(fov["to"]), 0.0001)
	assert_gt(float(aimbot.value_at("fov_deg", 2)), float(fov["from"]), "grows with level")
	assert_eq(aimbot.value_at("fov_deg", 0), 0.0, "neutral when not owned")


func test_effect_is_neutral_when_disabled() -> void:
	_unlock_all_and_fund()
	CheatSystem.purchase("wallhack")
	assert_gt(float(CheatSystem.effect("wallhack", "radius_m")), 0.0)
	CheatSystem.toggle("wallhack")
	assert_eq(CheatSystem.effect("wallhack", "radius_m"), 0.0)


func test_server_slots_adds_bots_and_uses_game_state_field() -> void:
	_unlock_all_and_fund()
	assert_eq(CheatSystem.extra_bots(), 0)
	CheatSystem.purchase("server_slots")
	CheatSystem.purchase("server_slots")
	assert_eq(GameState.server_slots, 2)
	var slots := CheatSystem.get_cheat("server_slots")
	assert_eq(CheatSystem.extra_bots(), roundi(float(slots.value_at("extra_bots", 2))))
	assert_gt(CheatSystem.extra_bots(), 0)


# --- Persistence -----------------------------------------------------------------

func test_state_persists_through_game_state_dict() -> void:
	_unlock_all_and_fund()
	CheatSystem.purchase("speed_hack")
	CheatSystem.purchase("speed_hack")
	CheatSystem.purchase("wallhack")
	CheatSystem.set_enabled("wallhack", false)
	CheatSystem.purchase("server_slots")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.new_game()
	_player.stat_mods.clear()
	GameState.from_dict(saved)
	EventBus.game_state_loaded.emit()
	assert_eq(CheatSystem.level("speed_hack"), 2)
	assert_true(CheatSystem.is_enabled("speed_hack"))
	assert_false(CheatSystem.is_enabled("wallhack"))
	assert_eq(CheatSystem.level("server_slots"), 1)
	assert_true(_player.stat_mods.has(&"move_speed_mult"), "re-applied after load")
