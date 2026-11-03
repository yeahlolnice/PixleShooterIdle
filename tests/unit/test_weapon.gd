extends GutTest

var w: Weapon


func before_each() -> void:
	w = Weapon.new()
	add_child_autofree(w)
	w.setup(DataRegistry.gun("pistol_starter"))


func test_starts_with_full_mag_from_data() -> void:
	assert_eq(w.ammo, 12)
	assert_eq(w.mag_size(), 12)


func test_fire_depletes_ammo_and_respects_fire_rate() -> void:
	assert_true(w.try_fire())
	assert_eq(w.ammo, 11)
	assert_false(w.try_fire(), "cooldown blocks immediate second shot")
	w.tick(0.26)  # fire_rate 4/s -> 0.25 s
	assert_true(w.try_fire())
	assert_eq(w.ammo, 10)


func test_empty_mag_auto_reloads_with_data_time() -> void:
	for i in 12:
		w.tick(1.0)
		assert_true(w.try_fire())
	assert_eq(w.ammo, 0)
	assert_true(w.is_reloading())
	w.tick(1.3)
	assert_true(w.is_reloading())
	w.tick(0.2)  # reload_time_s 1.4
	assert_false(w.is_reloading())
	assert_eq(w.ammo, 12)


func test_cannot_fire_while_reloading_or_reload_full_mag() -> void:
	assert_false(w.start_reload(), "full mag")
	w.try_fire()
	assert_true(w.start_reload())
	w.tick(1.0)
	assert_false(w.try_fire())


func test_recoil_kicks_by_data() -> void:
	watch_signals(w)
	w.try_fire()
	assert_signal_emit_count(w, "recoil_kicked", 1)
	assert_almost_eq(float(get_signal_parameters(w, "recoil_kicked")[0]), 1.8, 0.001)


func test_mag_mult_changes_mag_and_refill() -> void:
	w.set_modifier("mag_mult", 2.0)
	assert_eq(w.mag_size(), 24)
	w.try_fire()
	w.start_reload()
	w.tick(2.0)
	assert_eq(w.ammo, 24)


func test_recoil_and_spread_mult() -> void:
	w.set_modifier("recoil_mult", 0.5)
	w.set_modifier("spread_mult", 0.0)
	assert_almost_eq(w.recoil_deg(), 0.9, 0.001)
	assert_eq(w.spread_deg(), 0.0)
	watch_signals(w)
	w.try_fire()
	assert_almost_eq(float(get_signal_parameters(w, "recoil_kicked")[0]), 0.9, 0.001)
	w.set_modifier("recoil_mult", 0.0)
	w.tick(1.0)
	w.try_fire()
	assert_signal_emit_count(w, "recoil_kicked", 1, "No Recoil maxed: no kick")


func test_infinite_reload_is_instant() -> void:
	w.set_modifier("infinite_reload", true)
	w.try_fire()
	assert_true(w.start_reload())
	assert_false(w.is_reloading())
	assert_eq(w.ammo, 12)


func test_reset_modifiers() -> void:
	w.set_modifier("mag_mult", 3.0)
	w.reset_modifiers()
	assert_eq(w.mag_size(), 12)


func test_spread_stays_in_cone() -> void:
	w.seed_rng(7)
	for i in 100:
		var d := w.spread_direction(Vector3.FORWARD, 2.0)
		assert_lte(rad_to_deg(d.angle_to(Vector3.FORWARD)), 2.001)
	assert_eq(w.spread_direction(Vector3.FORWARD, 0.0), Vector3.FORWARD)


func test_three_pistols_in_data() -> void:
	var pistols := DataRegistry.guns().filter(func(g): return g["id"].begins_with("pistol_"))
	assert_eq(pistols.size(), 3)
	assert_eq(DataRegistry.gun("pistol_starter")["price"], 0)


func test_manager_falls_back_to_starter() -> void:
	var m := WeaponManager.new()
	m.mount_path = ^""
	add_child_autofree(m)
	assert_eq(m.equip("nonexistent"), "pistol_starter")
	assert_eq(m.equip("pistol_hand_cannon"), "pistol_hand_cannon")
	assert_eq(m.weapon.mag_size(), 7)


func test_raycast_hits_headshot_hitbox() -> void:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.current = true
	var target := Node3D.new()
	target.set_script(load("res://tests/unit/hit_target.gd"))
	add_child_autofree(target)
	target.position = Vector3(0, 0, -5)
	var area := Area3D.new()
	area.collision_layer = Layers.HITBOXES
	area.set_meta("headshot", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.5)
	shape.shape = box
	area.add_child(shape)
	target.add_child(area)
	await get_tree().physics_frame
	await get_tree().physics_frame
	w.modifiers["spread_mult"] = 0.0
	w.try_fire()
	assert_eq(target.last_damage, 50.0)
	assert_true(target.last_info["headshot"])


# TASK-015: firing stays blocked until every open menu has closed.
func test_manager_tracks_menus_per_id() -> void:
	var m := WeaponManager.new()
	m.mount_path = ^""
	add_child_autofree(m)
	EventBus.menu_toggled.emit(&"buy_menu", true)
	EventBus.menu_toggled.emit(&"mod_menu", true)
	EventBus.menu_toggled.emit(&"mod_menu", false)
	assert_true(m.is_menu_open())
	EventBus.menu_toggled.emit(&"buy_menu", false)
	assert_false(m.is_menu_open())
