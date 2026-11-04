extends Node
## Windowed screenshot tour for build notes (TASK-018). Boots the main scene with
## --dev-unlock-all state (the save file is never read or written), walks through
## buy menu, mod menu, every cheat, a live round, noclip, pause and the round
## summary, and saves one PNG per step.
##
##   godot --path . res://tools/screenshot_tour.tscn                 # -> build/screens/
##   godot --path . res://tools/screenshot_tour.tscn -- --out=/tmp/shots
##
## Needs a real display (headless renders nothing). On Linux CI use xvfb-run.
## The window shows for ~40 s without taking focus (WINDOW_FLAG_NO_FOCUS), so real
## clicks on the desktop do not reach the game; the mouse is left free.

const MAIN_SCENE := "res://scenes/main.tscn"
const DEFAULT_OUT := "res://build/screens"
const SETTLE_FRAMES := 20

var _out := DEFAULT_OUT
var _main: Node
var _shot := 0


func _ready() -> void:
	# Never take focus: the tour runs on a real desktop and must not catch the user's clicks.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run.call_deferred()


func _run() -> void:
	DevFlags.apply(PackedStringArray([DevFlags.UNLOCK_ALL_FLAG]), true)
	_main = load(MAIN_SCENE).instantiate()
	_main.use_save_file = false
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await _settle()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # never grab the user's mouse
	# Ignore real input entirely: the shots are scripted.
	_main.player.set_process_input(false)
	_main.player.set_process_unhandled_input(false)
	(_main.player.get_node("WeaponManager") as Node).set_physics_process(false)
	await _snap("freeze_time")

	var buy := _ui(BuyMenu) as BuyMenu
	buy.open_menu()
	await _snap("buy_menu")
	buy.close_menu()
	var wm: WeaponManager = _main.player.get_node("WeaponManager")
	for id in ["shotgun_boomstick", "lmg_brrt"]:
		wm.equip(id)
		await _snap("gun_" + id)
	wm.equip("sniper_longboi")
	wm.set_aiming(true)
	await _snap("sniper_scoped")
	wm.set_aiming(false)
	wm.equip("rifle_block47")

	# Warehouse live, no cheats yet: bots should stream in from the entrances in columns.
	_main.rounds.advance(_main.rounds.time_left + 0.05)
	_main.player.rotation = Vector3.ZERO
	_main.player.aim_at(_main.player.camera.global_position + Vector3(0, -0.15, -10), 1.0)
	await _settle(200)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _snap("columns_live")

	var last_arena: String = DataRegistry.arenas()[-1]["id"]
	if ArenaService.select(last_arena):
		await _settle(30)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await _snap("arena_" + last_arena)
		buy.open_menu()
		await _snap("buy_menu_servers")
		buy.close_menu()

	# Close-up lineup of every bot type (art pass), then one pops.
	var lineup: Array = []
	var cam: Camera3D = _main.player.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var types := DataRegistry.bots().map(func(b): return b["id"])
	for i in types.size():
		var b: Bot = load("res://shooter/bots/bot.tscn").instantiate()
		b.configure(types[i], DataRegistry.first_arena_id(), _main.player)
		_main.add_child(b)
		b.set_physics_process(false)
		b.global_position = _main.player.global_position + fwd * 3.5 + right * (float(i) - (types.size() - 1) * 0.5) * 1.3
		b.look_at(_main.player.global_position, Vector3.UP)
		b.rotation.x = 0.0
		lineup.append(b)
	await _snap("bot_lineup")
	lineup[0].take_hit("head", 100000.0)
	await _settle(6)
	await _snap("bot_pop")
	for b in lineup:
		if is_instance_valid(b):
			b.queue_free()

	var mod := _ui(ModMenu) as ModMenu
	mod.open_menu()
	await _snap("mod_menu")
	for cheat in CheatSystem.cheats():
		for i in 3:
			CheatSystem.purchase(cheat.id)
	CheatSystem.purchase(CheatSystem.SERVER_SLOTS_ID)
	mod.refresh()
	await _snap("mod_menu_all_bought")
	mod.close_menu()

	var rounds: RoundController = _main.rounds
	rounds.advance(rounds.time_left + 0.05)   # freeze -> live
	await _settle(90)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _snap("live_all_cheats")

	var player: Player = _main.player
	player.toggle_noclip()
	for i in 40:
		player.step_noclip(1.0 / 60.0, Vector3.UP * 0.5 + Vector3.FORWARD)
	await _snap("noclip_flying")

	player.toggle_noclip()
	var killer: Node = null
	for b in get_tree().get_nodes_in_group("bots"):
		if CheatTargeting.is_live(b):
			killer = b
			break
	player.die(killer)
	await _snap("death_screen")

	var pause := _ui(PauseMenu) as PauseMenu
	pause.open_menu()
	await _snap("pause_menu")
	if pause.dev_unlock_button:
		pause.dev_unlock_button.pressed.emit()
		await _snap("pause_dev_unlocked")
	pause.close_menu()

	rounds.advance(rounds.time_left + 0.05)   # live -> summary
	await _snap("round_summary")
	print("[screenshot_tour] %d screenshots in %s" % [_shot, ProjectSettings.globalize_path(_out)])
	get_tree().quit(0)


func _ui(type: Variant) -> Node:
	for n in _main.get_node("UI").get_children():
		if is_instance_of(n, type):
			return n
	push_error("[screenshot_tour] UI node not found")
	return null


func _settle(frames: int = SETTLE_FRAMES) -> void:
	for i in frames:
		await get_tree().process_frame


func _snap(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	_shot += 1
	var path := "%s/%02d_%s.png" % [_out, _shot, label]
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		push_error("[screenshot_tour] could not save %s (%s)" % [path, error_string(err)])
	else:
		print("[screenshot_tour] ", ProjectSettings.globalize_path(path))
