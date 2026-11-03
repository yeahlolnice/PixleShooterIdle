extends GutTest
## Audio pack (TASK-028): every procedural sound builds, guns sound different
## per class, and every gameplay EventBus signal plays something.


func test_every_sound_builds() -> void:
	for n in SfxSynth.NAMES:
		var wav := SfxSynth.get_sound(n)
		assert_not_null(wav, n)
		assert_gt(wav.data.size(), 400, "%s has samples" % n)
		assert_eq(wav.mix_rate, SfxSynth.RATE)
	assert_same(SfxSynth.get_sound("hit"), SfxSynth.get_sound("hit"), "cached")


func test_each_gun_class_has_its_own_shot() -> void:
	var seen := {}
	for c in ["pistol", "smg", "shotgun", "rifle", "sniper", "lmg"]:
		var wav := SfxSynth.shot(c)
		assert_false(seen.has(wav.data), "%s sounds different" % c)
		seen[wav.data] = true
	assert_same(SfxSynth.shot("banana"), SfxSynth.shot("pistol"), "unknown -> pistol")


func test_weapon_uses_its_class_sound_on_the_sfx_bus() -> void:
	var w: Weapon = add_child_autofree(Weapon.new())
	for g in DataRegistry.guns():
		if g.get("category", "") == "sniper":
			w.setup(g)
	var players := w.get_children().filter(func(c): return c is AudioStreamPlayer)
	assert_eq(players.size(), 2, "shot + reload")
	assert_same(players[0].stream, SfxSynth.shot("sniper"))
	assert_eq(players[0].bus, StringName(SfxPlayer.BUS))
	assert_ne(AudioServer.get_bus_index(SfxPlayer.BUS), -1, "bus exists")


func test_gameplay_signals_play_sounds() -> void:
	var sfx: SfxPlayer = add_child_autofree(SfxPlayer.new())
	var cases := [
		[func(): EventBus.bot_damaged.emit(null, {"headshot": true}), "headshot"],
		[func(): EventBus.kill_rewarded.emit(10.0, {}), "kill"],
		[func(): EventBus.loot_collected.emit(5.0), "loot"],
		[func(): EventBus.player_damaged.emit(5.0, 50.0, null), "hurt"],
		[func(): EventBus.player_died.emit({}), "death"],
		[func(): EventBus.round_state_changed.emit(EventBus.ROUND_LIVE, {}), "round_live"],
		[func(): EventBus.round_state_changed.emit(EventBus.ROUND_SUMMARY, {}), "round_end"],
		[func(): EventBus.cheat_purchased.emit("speed_hack", 1), "inject"],
		[func(): EventBus.cheat_unlocked.emit("speed_hack"), "unlock"],
		[func(): EventBus.gun_upgraded.emit("pistol_starter", "damage", 1), "buy"],
		[func(): EventBus.menu_toggled.emit(&"test_menu", true), "menu_open"],
		[func(): EventBus.menu_toggled.emit(&"test_menu", false), "menu_close"],
		[func(): EventBus.scope_changed.emit(true), "scope"],
	]
	for c in cases:
		var before := sfx.played.size()
		c[0].call()
		assert_eq(sfx.played.size(), before + 1, "one sound for %s" % c[1])
		assert_eq(sfx.played[-1], c[1])


func test_body_hits_are_rate_limited_headshots_are_not() -> void:
	var sfx: SfxPlayer = add_child_autofree(SfxPlayer.new())
	for i in 8:
		sfx.play_hit(false)
	assert_eq(sfx.played.count("hit"), 1, "8 pellets in one frame = one tick")
	sfx.play_hit(true)
	sfx.play_hit(true)
	assert_eq(sfx.played.count("headshot"), 2)
