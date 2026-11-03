extends GutTest
## Speed Hack, Infinite Ammo and Auto Bhop: level 1 and max effects match the
## plan table / cheats.json, remove() restores base stats exactly (mock player
## and the real Player/Weapon), and bhop speed builds per hop, capped below max.

const PlayerScene := preload("res://shooter/player/player.tscn")
const DT := 1.0 / 60.0


class MockWeapon:
	extends RefCounted
	var modifiers := {"mag_mult": 1.0, "recoil_mult": 1.0, "spread_mult": 1.0, "infinite_reload": false}

	func set_modifier(key: String, value: Variant) -> void:
		modifiers[key] = value


class MockPlayer:
	extends RefCounted
	var stat_mods := {}
	var bhop := {}
	var weapon: Object = MockWeapon.new()

	func set_stat_mod(mod_name: StringName, value: float) -> void:
		stat_mods[mod_name] = value

	func clear_stat_mod(mod_name: StringName) -> void:
		stat_mods.erase(mod_name)

	func set_bhop(settings: Dictionary) -> void:
		bhop = settings.duplicate()

	func clear_bhop() -> void:
		bhop = {}

	func get_weapon() -> Object:
		return weapon


func _cheat(id: String) -> CheatBase:
	return CheatSystem.get_cheat(id)


func _effect(id: String, key: String) -> Dictionary:
	return _cheat(id).effect_def(key)


# --- Data wiring -----------------------------------------------------------------

func test_cheats_use_their_scripts() -> void:
	assert_true(_cheat("speed_hack") is SpeedHack)
	assert_true(_cheat("infinite_ammo") is InfiniteAmmo)
	assert_true(_cheat("auto_bhop") is AutoBhop)


# --- Speed Hack --------------------------------------------------------------------

func test_speed_hack_level_1_and_max_match_table() -> void:
	var c := _cheat("speed_hack")
	var p := MockPlayer.new()
	c.apply(p, 1)
	assert_almost_eq(p.stat_mods[&"move_speed_mult"], 1.10, 0.0001, "plan: +10% at level 1")
	assert_almost_eq(p.stat_mods[&"move_speed_mult"], float(_effect("speed_hack", "move_speed_mult")["from"]), 0.0001)
	c.apply(p, c.max_level)
	assert_almost_eq(p.stat_mods[&"move_speed_mult"], 2.50, 0.0001, "plan: +150% at max")
	assert_almost_eq(p.stat_mods[&"move_speed_mult"], float(_effect("speed_hack", "move_speed_mult")["to"]), 0.0001)
	c.remove(p)
	assert_eq(p.stat_mods, {}, "no modifier left")


func test_speed_hack_on_real_player_restores_base_exactly() -> void:
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	var base := p.effective(&"move_speed")
	var c := _cheat("speed_hack")
	for lvl in [1, c.max_level]:
		c.apply(p, lvl)
		assert_almost_eq(p.effective(&"move_speed"), base * float(c.value_at("move_speed_mult", lvl)), 0.0001)
		c.remove(p)
		assert_eq(p.effective(&"move_speed"), base, "level %d removed" % lvl)
	assert_eq(p.stat_mods, {})


# --- Infinite Ammo -----------------------------------------------------------------

func test_infinite_ammo_level_1_and_max_match_table() -> void:
	var c := _cheat("infinite_ammo")
	var p := MockPlayer.new()
	var neutral: Dictionary = p.weapon.modifiers.duplicate()
	c.apply(p, 1)
	assert_almost_eq(float(p.weapon.modifiers["mag_mult"]), 2.0, 0.0001, "plan: 2x magazine at level 1")
	assert_false(p.weapon.modifiers["infinite_reload"])
	c.apply(p, c.max_level)
	assert_almost_eq(float(p.weapon.modifiers["mag_mult"]), float(_effect("infinite_ammo", "mag_mult")["to"]), 0.0001)
	assert_true(p.weapon.modifiers["infinite_reload"], "plan: never reload at max")
	assert_false(c.value_at("infinite_reload", c.max_level - 1), "only max level never reloads")
	c.remove(p)
	assert_eq(p.weapon.modifiers, neutral, "weapon modifiers back to neutral")


func test_infinite_ammo_on_real_weapon_restores_base_exactly() -> void:
	var w: Weapon = add_child_autofree(Weapon.new())
	w.setup(DataRegistry.guns()[0])
	var base_mag: int = w.mag_size()
	var base_reload: float = w.reload_time()
	var p := MockPlayer.new()
	p.weapon = w
	var c := _cheat("infinite_ammo")
	c.apply(p, 1)
	assert_eq(w.mag_size(), base_mag * 2)
	assert_eq(w.reload_time(), base_reload)
	c.apply(p, c.max_level)
	assert_eq(w.reload_time(), 0.0)
	# Empty the magazine: the last shot refills at once.
	for i in w.ammo:
		w.tick(10.0)
		assert_true(w.try_fire())
	assert_false(w.is_reloading())
	assert_eq(w.ammo, w.mag_size())
	c.remove(p)
	assert_eq(w.mag_size(), base_mag)
	assert_eq(w.reload_time(), base_reload)
	assert_eq(w.modifiers["infinite_reload"], false)


func test_infinite_reload_finishes_running_reload() -> void:
	var w: Weapon = add_child_autofree(Weapon.new())
	w.setup(DataRegistry.guns()[0])
	var p := MockPlayer.new()
	p.weapon = w
	w.ammo = 0
	assert_true(w.start_reload())
	var c := _cheat("infinite_ammo")
	c.apply(p, c.max_level)
	assert_false(w.is_reloading())
	assert_eq(w.ammo, w.mag_size())


# --- Auto Bhop ---------------------------------------------------------------------

func test_auto_bhop_level_1_and_max_settings() -> void:
	var c := _cheat("auto_bhop")
	var p := MockPlayer.new()
	c.apply(p, 1)
	assert_false(p.bhop.is_empty(), "level 1: hold jump to hop")
	assert_eq(p.bhop["hop_speed_gain"], 0.0, "no speed gain at level 1")
	assert_false(p.bhop["uncapped"])
	c.apply(p, c.max_level)
	assert_almost_eq(p.bhop["hop_speed_gain"], float(_effect("auto_bhop", "hop_speed_gain")["to"]), 0.0001)
	assert_true(p.bhop["uncapped"], "plan: no cap at max")
	assert_false(c.value_at("uncapped", c.max_level - 1), "capped below max level")
	assert_gt(float(c.value_at("hop_speed_gain", 2)), 0.0, "gain from level 2")
	c.remove(p)
	assert_eq(p.bhop, {}, "bhop cleared")
	assert_eq(p.stat_mods, {})


func test_hop_speed_gain_and_cap() -> void:
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	var c := _cheat("auto_bhop")
	var ms := p.effective(&"move_speed")
	c.apply(p, 1)
	assert_eq(p.hop_speed(ms), ms, "level 1 keeps speed")
	var lvl := c.max_level - 1
	c.apply(p, lvl)
	var cap := ms * float(c.value_at("max_hop_speed_mult", lvl))
	assert_almost_eq(p.hop_speed(ms), ms * (1.0 + float(c.value_at("hop_speed_gain", lvl))), 0.0001)
	assert_eq(p.hop_speed(cap), cap, "capped")
	assert_eq(p.hop_speed(cap * 2.0), cap * 2.0, "never slows down")
	c.apply(p, c.max_level)
	assert_gt(p.hop_speed(cap * 2.0), cap * 2.0, "uncapped at max")
	c.remove(p)
	assert_false(p.has_bhop())
	assert_eq(p.hop_speed(ms), ms)


## Holds jump on a flat floor with no input and returns horizontal speed after
## each landing hop.
func _hop_speeds(p: Player, hops: int) -> Array:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5000, 1, 5000)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child_autofree(floor_body)
	p.global_position = Vector3(0, 0.1, 0)
	p.velocity = Vector3.ZERO
	for i in 30:
		p.step_movement(DT, Vector3.ZERO, false)
	assert_true(p.is_on_floor(), "settled")
	p.velocity = Vector3(p.effective(&"move_speed"), 0, 0)
	var speeds: Array = []
	var ticks := 0
	while speeds.size() < hops and ticks < hops * 120:
		var was_on_floor := p.is_on_floor()
		p.step_movement(DT, Vector3.ZERO, true)
		if was_on_floor:
			speeds.append(Vector2(p.velocity.x, p.velocity.z).length())
		ticks += 1
	return speeds


func test_bhop_speed_builds_per_hop_and_caps_below_max() -> void:
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	var c := _cheat("auto_bhop")
	var lvl := c.max_level - 1
	c.apply(p, lvl)
	var cap := p.effective(&"move_speed") * float(c.value_at("max_hop_speed_mult", lvl))
	var speeds := _hop_speeds(p, 25)
	assert_eq(speeds.size(), 25, "hopped on every landing")
	assert_gt(speeds[1], speeds[0], "speed builds per hop")
	assert_gt(speeds[2], speeds[1])
	assert_almost_eq(speeds[-1], cap, 0.01, "reaches the cap")
	for s in speeds:
		assert_lte(s, cap + 0.001)


func test_bhop_uncapped_at_max_and_level_1_keeps_speed() -> void:
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	var c := _cheat("auto_bhop")
	var ms := p.effective(&"move_speed")
	c.apply(p, 1)
	var flat := _hop_speeds(p, 4)
	for s in flat:
		assert_almost_eq(s, ms, 0.01, "level 1 hops keep speed")
	c.apply(p, c.max_level)
	var cap_below_max := ms * float(c.value_at("max_hop_speed_mult", c.max_level - 1))
	var speeds := _hop_speeds(p, 12)
	assert_gt(speeds[-1], cap_below_max, "no cap at max level")
