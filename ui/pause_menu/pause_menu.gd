class_name PauseMenu
extends Control
## Esc (the pause action). If the buy or mod menu is open, Esc closes it first;
## if the chat log is open, the chat box handles Esc itself. Otherwise Esc opens
## this menu: the scene tree pauses (round timer, bots, physics stop), the mouse
## is freed via menu_toggled("pause"), and Resume / Settings / Quit are offered.
## Quit saves (same path as closing the window) and exits. With dev tools on
## (DevFlags), a DEV button unlocks everything for the session and stops saving.

const MENU_ID := &"pause"

var _open_menus: Dictionary = {}
var _settings_button: Button
## Only when DevFlags.dev_tools_enabled(); null otherwise.
var dev_unlock_button: Button


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = HaxTheme.build()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_button("Resume", close_menu))
	_settings_button = _button("Settings (soon)", func(): pass)
	_settings_button.disabled = true  # TASK-044
	box.add_child(_settings_button)
	box.add_child(_button("Quit to desktop", quit_game))
	if DevFlags.dev_tools_enabled():
		dev_unlock_button = _button("DEV: unlock everything (not saved)", _on_dev_unlock)
		dev_unlock_button.add_theme_color_override("font_color", DataRegistry.color("danger"))
		box.add_child(dev_unlock_button)
	EventBus.menu_toggled.connect(_on_menu_toggled)


func _exit_tree() -> void:
	if visible and is_inside_tree():
		get_tree().paused = false


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 40)
	b.pressed.connect(action)
	return b


func is_open() -> bool:
	return visible


func open_menu() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	EventBus.menu_toggled.emit(MENU_ID, true)


func close_menu() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	EventBus.menu_toggled.emit(MENU_ID, false)


func _on_dev_unlock() -> void:
	DevFlags.unlock_all_in_session()
	dev_unlock_button.text = "DEV: unlocked - press INSERT to buy"
	dev_unlock_button.disabled = true


func quit_game() -> void:
	close_menu()
	# Same notification the window close button sends, so GameState saves.
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()


## What Esc does right now; split out so tests can drive it without input events.
## Returns true if Esc was used here.
func handle_escape() -> bool:
	if visible:
		close_menu()
		return true
	if _open_menus.has(&"chat"):
		return false  # the chat box closes its own log
	var closed := false
	if get_parent():
		for sibling in get_parent().get_children():
			if sibling != self and sibling.has_method("is_open") and sibling.has_method("close_menu") and sibling.is_open():
				sibling.close_menu()
				closed = true
	if closed:
		return true
	open_menu()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and handle_escape():
		get_viewport().set_input_as_handled()


func _on_menu_toggled(menu_id: StringName, open: bool) -> void:
	if menu_id == MENU_ID:
		return
	if open:
		_open_menus[menu_id] = true
	else:
		_open_menus.erase(menu_id)
