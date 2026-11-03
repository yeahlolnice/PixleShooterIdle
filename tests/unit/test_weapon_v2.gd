extends GutTest
## Weapon v2 (TASK-022) and the gun ladder (TASK-023): bloom, scope zoom,
## shotgun pellets, buy-menu categories. Values come from data/guns.json.

const PlayerScene := preload("res://shooter/player/player.tscn")
const BotScene := preload("res://shooter/bots/bot.tscn")


func _weapon(id: String) -> Weapon:
	var w: Weapon = add_child_autofree(Weapon.new())
	w.setup(DataRegistry.gun(id))
	return w


func _first_gun_with(key: String) -> Dictionary:
	for g in DataRegistry.guns():
		if g.has(key):
			return g
	return {}


func test_ladder_has_every_category_from_the_plan() -> void:
	var cats := BuyMenu.categories(ShopService.catalog())
	for c in ["pistol", "smg", "shotgun", "rifle", "sniper", "lmg"]:
		assert_true(cats.has(c), c)
	assert_eq(cats.slice(0, 6), ["pistol", "smg", "shotgun", "rifle", "sniper", "lmg"], "plan order")


func test_bloom_grows_per_shot_caps_and_recovers() -> void:
	var g := _first_gun_with("bloom_deg")
	var w := _weapon(g["id"])
	var base := w.spread_deg()
	assert_true(w.try_fire())
	assert_almost_eq(w.spread_deg(), base + float(g["bloom_deg"]), 0.0001)
	for i in 200:
		w.tick(w.fire_interval())
		w.try_fire()
		if w.is_reloading():
			break
	assert_almost_eq(w.bloom, float(g["bloom_max_deg"]), 0.0001, "capped")
	w.tick(10.0)
	w.tick(10.0)
	assert_eq(w.bloom, 0.0, "recovers while not firing")


func test_scoped_spread_and_zoom() -> void:
	var g := _first_gun_with("zoom_fov")
	var w := _weapon(g["id"])
	assert_gt(w.zoom_fov(), 0.0)
	var unscoped := w.spread_deg()
	w.scoped = true
	assert_almost_eq(w.spread_deg(), unscoped * float(g.get("scoped_spread_mult", 1.0)), 0.0001)


func test_manager_zooms_camera_hides_viewmodel_and_slows_look() -> void:
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	var wm: WeaponManager = p.get_node("WeaponManager")
	var base_fov := p.camera.fov
	wm.equip(_first_gun_with("zoom_fov")["id"])
	wm.set_aiming(true)
	assert_almost_eq(p.camera.fov, wm.weapon.zoom_fov(), 0.0001)
	assert_false(wm.weapon.visible, "scope view, no viewmodel")
	assert_almost_eq(p.look_scale, wm.weapon.zoom_fov() / base_fov, 0.0001)
	wm.set_aiming(false)
	assert_almost_eq(p.camera.fov, base_fov, 0.0001)
	assert_eq(p.look_scale, 1.0)
	wm.equip(DataRegistry.starter_gun_id())
	wm.set_aiming(true)
	assert_almost_eq(p.camera.fov, base_fov, 0.0001, "no scope on a pistol")
	assert_false(wm.is_scoped())


func test_switching_gun_while_scoped_unzooms() -> void:
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	var wm: WeaponManager = p.get_node("WeaponManager")
	var base_fov := p.camera.fov
	wm.equip(_first_gun_with("zoom_fov")["id"])
	wm.set_aiming(true)
	wm.equip(DataRegistry.starter_gun_id())
	assert_almost_eq(p.camera.fov, base_fov, 0.0001)


func test_shotgun_fires_every_pellet_and_sums_damage() -> void:
	var g := _first_gun_with("pellets")
	var p: Player = add_child_autofree(PlayerScene.instantiate())
	p.set_physics_process(false)
	var bot: Bot = BotScene.instantiate()
	bot.configure("grunt", DataRegistry.first_arena_id())
	add_child_autofree(bot)
	bot.global_position = Vector3(0, 0, -2.5)
	bot.set_physics_process(false)
	var wm: WeaponManager = p.get_node("WeaponManager")
	wm.equip(g["id"])
	await wait_physics_frames(2)
	watch_signals(wm.weapon)
	assert_true(wm.weapon.try_fire())
	var hit: Dictionary = get_signal_parameters(wm.weapon, "shot_fired")[0]
	assert_eq(hit["pellets"], int(g["pellets"]))
	assert_gt(hit["pellets_hit"], 1, "several pellets land at close range")
	assert_gt(float(hit["damage"]), float(g["damage"]), "damage adds up across pellets")
