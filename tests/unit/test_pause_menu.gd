extends GutTest
## PauseMenu: Esc closes an open menu first, leaves the chat log to the chat box,
## otherwise pauses the tree (round timer stops) and frees the mouse.

const PauseScene := preload("res://ui/pause_menu/pause_menu.tscn")


class FakeMenu:
	extends Control
	var open := false

	func is_open() -> bool:
		return open

	func close_menu() -> void:
		open = false


var _ui: Control
var _pause: PauseMenu
var _other: FakeMenu
var _rounds: RoundController


func before_each() -> void:
	_ui = add_child_autofree(Control.new())
	_other = FakeMenu.new()
	_ui.add_child(_other)
	_pause = PauseScene.instantiate()
	_ui.add_child(_pause)
	_rounds = add_child_autofree(RoundController.new())


func after_each() -> void:
	get_tree().paused = false


func test_escape_pauses_and_resumes() -> void:
	watch_signals(EventBus)
	assert_true(_pause.handle_escape())
	assert_true(_pause.is_open())
	assert_true(get_tree().paused)
	assert_false(_rounds.can_process(), "round timer stops while paused")
	assert_true(_pause.can_process(), "the menu itself keeps working")
	assert_signal_emitted_with_parameters(EventBus, "menu_toggled", [PauseMenu.MENU_ID, true])
	assert_true(_pause.handle_escape())
	assert_false(_pause.is_open())
	assert_false(get_tree().paused)
	assert_true(_rounds.can_process())


func test_escape_closes_another_open_menu_first() -> void:
	_other.open = true
	assert_true(_pause.handle_escape())
	assert_false(_other.open, "buy/mod menu closed")
	assert_false(_pause.is_open(), "pause not opened on the same press")
	assert_false(get_tree().paused)


func test_escape_left_to_chat_log() -> void:
	EventBus.menu_toggled.emit(&"chat", true)
	assert_false(_pause.handle_escape(), "chat box handles it")
	assert_false(_pause.is_open())
	EventBus.menu_toggled.emit(&"chat", false)
	assert_true(_pause.handle_escape())
	assert_true(_pause.is_open())
	_pause.close_menu()
