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
## The window shows for ~15 s; the mouse is left free.

const MAIN_SCENE := "res://scenes/main.tscn"
const DEFAULT_OUT := "res://build/screens"
const SETTLE_FRAMES := 20

var _out := DEFAULT_OUT
var _main: Node
var _shot := 0


func _ready() -> void:
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
	await _snap("freeze_time")

	var buy := _ui(BuyMenu) as BuyMenu
	buy.open_menu()
	await _snap("buy_menu")
	buy.close_menu()

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
