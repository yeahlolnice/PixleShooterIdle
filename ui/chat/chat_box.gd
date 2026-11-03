class_name ChatBox
extends Control
## Lobby chat in the HUD corner. Recent lines appear in the corner and fade out;
## the chat action (T / Enter) opens a scrollable log with the bot-mute toggle.
## Reads only EventBus.chat_message_posted and the ChatSystem autoload.

var _other_menu_open := false
var _ages: Array[float] = []  # seconds shown, one per corner line

@onready var recent: VBoxContainer = $Recent
@onready var log_panel: PanelContainer = $LogPanel
@onready var log_title: Label = $LogPanel/Box/Title
@onready var log_text: RichTextLabel = $LogPanel/Box/Log
@onready var mute_bots: CheckBox = $LogPanel/Box/MuteBots


func _ready() -> void:
	log_panel.hide()
	log_title.text = ChatSystem.ui_text("log_title")
	mute_bots.text = ChatSystem.ui_text("mute_bots")
	mute_bots.button_pressed = ChatSystem.is_muted(ChatSystem.CHANNEL_BOT)
	mute_bots.toggled.connect(func(on: bool): ChatSystem.set_channel_muted(ChatSystem.CHANNEL_BOT, on))
	EventBus.chat_message_posted.connect(_on_message)
	EventBus.menu_toggled.connect(_on_menu_toggled)
	ChatSystem.mute_changed.connect(func(_c, _m): _rebuild())
	_rebuild()


func _process(delta: float) -> void:
	var box: Dictionary = ChatSystem.data().get("box", {})
	var fade_after := float(box.get("fade_after_s", 0.0))
	var fade_time := float(box.get("fade_time_s", 1.0))
	var i := 0
	while i < _ages.size():
		_ages[i] += delta
		var alpha := clampf(1.0 - (_ages[i] - fade_after) / fade_time, 0.0, 1.0)
		var line: Control = recent.get_child(i)
		if alpha <= 0.0:
			line.free()
			_ages.remove_at(i)
			continue
		line.modulate.a = alpha
		i += 1


func is_log_open() -> bool:
	return log_panel.visible


func open_log() -> void:
	if log_panel.visible or _other_menu_open:
		return
	_rebuild()
	log_panel.show()
	recent.hide()
	EventBus.menu_toggled.emit(&"chat", true)


func close_log() -> void:
	if not log_panel.visible:
		return
	log_panel.hide()
	recent.show()
	EventBus.menu_toggled.emit(&"chat", false)


## Number of lines currently in the corner box.
func recent_count() -> int:
	return _ages.size()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat"):
		if log_panel.visible:
			close_log()
		else:
			open_log()
		if log_panel.visible or not _other_menu_open:
			get_viewport().set_input_as_handled()
	elif log_panel.visible and event.is_action_pressed("pause"):
		close_log()
		get_viewport().set_input_as_handled()


func _on_menu_toggled(menu_id: StringName, open: bool) -> void:
	if menu_id != &"chat":
		_other_menu_open = open


func _on_message(channel: StringName, sender: String, text: String) -> void:
	_add_recent(channel, sender, text)
	if log_panel.visible:
		_append_log(channel, sender, text)


func _add_recent(channel: StringName, sender: String, text: String) -> void:
	var label := Label.new()
	label.text = ChatSystem.format_line(channel, sender, text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("channel", channel)
	label.add_theme_color_override("font_color", ChatSystem.channel_color(channel))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	recent.add_child(label)
	_ages.append(0.0)
	var max_lines := int(ChatSystem.data().get("box", {}).get("visible_lines", 1))
	while _ages.size() > max_lines:
		recent.get_child(0).free()
		_ages.remove_at(0)


## Redraws the log from ChatSystem history and drops muted lines from the corner.
func _rebuild() -> void:
	log_text.clear()
	for m in ChatSystem.visible_history():
		_append_log(m["channel"], m["sender"], m["text"])
	var i := 0
	while i < recent.get_child_count():
		if ChatSystem.is_muted(recent.get_child(i).get_meta("channel", &"")):
			recent.get_child(i).free()
			_ages.remove_at(i)
		else:
			i += 1


func _append_log(channel: StringName, sender: String, text: String) -> void:
	log_text.push_color(ChatSystem.channel_color(channel))
	log_text.add_text(ChatSystem.format_line(channel, sender, text))
	log_text.pop()
	log_text.newline()
