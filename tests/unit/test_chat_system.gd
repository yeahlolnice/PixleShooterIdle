extends GutTest
## ChatSystem: trigger -> message mapping, once-only persistence through
## GameState save dictionaries, placeholder substitution and the mute filter.

const ChatSystemScript := preload("res://autoload/chat_system.gd")

var _saved_state: Dictionary
var _chat: Node
var _posted: Array = []


func _fixture() -> Dictionary:
	return {
		"channels": {
			"system": {"sender": "SYSTEM", "color": "chat_system", "format": "[{sender}] {text}"},
			"seller": {"sender": "x_Hax_x", "color": "chat_seller", "format": "[DM] {sender}: {text}"},
			"bot": {"sender": "", "color": "chat_bot", "format": "{sender}: {text}"},
		},
		"ui": {},
		"box": {"visible_lines": 3, "fade_after_s": 1.0, "fade_time_s": 1.0, "log_max_lines": 50},
		"bot_names": ["botty"],
		"triggers": [
			{"id": "hello", "event": "first_match", "channel": "system", "once": true, "delay_s": 0.0, "lines": ["Press B"]},
			{"id": "later", "event": "first_match", "channel": "seller", "once": true, "delay_s": 2.0, "lines": ["press INSERT"]},
			{"id": "cash", "event": "first_cash", "channel": "seller", "once": false, "delay_s": 0.0, "lines": ["${amount} is cute, {who}"]},
			{"id": "unlock", "event": "cheat_unlocked", "channel": "system", "once": true, "once_key": "unlock_{cheat_id}", "delay_s": 0.0, "lines": ["New: {cheat_name}"]},
			{"id": "lvl1", "event": "cheat_purchased", "channel": "system", "once": false, "delay_s": 0.0, "when": {"level": "1"}, "lines": ["bought {cheat_id}"]},
			{"id": "taunt", "event": "player_died", "channel": "bot", "once": false, "delay_s": 0.0, "lines": ["gg ez"]},
		],
	}


func before_each() -> void:
	_saved_state = GameState.to_dict()
	GameState.new_game()
	_chat = ChatSystemScript.new()  # not added to the tree: no autoload wiring, no settings file
	_chat.settings_path = ""
	_chat.configure(_fixture())
	_posted.clear()
	EventBus.chat_message_posted.connect(_record)


func after_each() -> void:
	EventBus.chat_message_posted.disconnect(_record)
	_chat.free()
	GameState.from_dict(_saved_state)


func _record(channel: StringName, sender: String, text: String) -> void:
	_posted.append([channel, sender, text])


func test_shipped_chat_json_is_valid() -> void:
	assert_true(DataRegistry.is_valid(), "\n".join(DataRegistry.errors()))
	var chat := DataRegistry.chat()
	assert_false(chat.get("triggers", []).is_empty())
	for channel in ["system", "seller", "bot"]:
		assert_true(chat["channels"].has(channel), "channel %s" % channel)


func test_shipped_tutorial_covers_controls_buy_and_mod_menu() -> void:
	var tutorial := ""
	for t in DataRegistry.chat()["triggers"]:
		if t["event"] in ["first_match", "round_live", "first_cash"] and t["once"]:
			tutorial += " ".join(t["lines"]) + "\n"
	for needle in ["WASD", "SPACE", "LEFT CLICK", "B to open the buy menu", "INSERT"]:
		assert_string_contains(tutorial, needle)


func test_trigger_maps_event_to_channel_sender_and_text() -> void:
	var out: Array[Dictionary] = _chat.handle_event(&"first_match")
	assert_eq(out.size(), 2)
	assert_eq(_posted, [[&"system", "SYSTEM", "Press B"]], "zero-delay line posts immediately")
	assert_eq(_chat.pending_count(), 1)
	_chat.tick(1.0)
	assert_eq(_posted.size(), 1, "delayed line waits")
	_chat.tick(1.5)
	assert_eq(_posted[1], [&"seller", "x_Hax_x", "press INSERT"])
	assert_eq(_chat.pending_count(), 0)


func test_unknown_event_posts_nothing() -> void:
	assert_eq(_chat.handle_event(&"nope").size(), 0)
	assert_eq(_posted.size(), 0)


func test_once_only_trigger_fires_once() -> void:
	_chat.handle_event(&"first_match")
	_chat.handle_event(&"first_match")
	_chat.tick(5.0)
	assert_eq(_posted.size(), 2)
	assert_true(GameState.chat_flags.has("hello"))


func test_once_only_survives_save_and_load() -> void:
	_chat.handle_event(&"first_match")
	var json := JSON.stringify(GameState.to_dict())
	GameState.new_game()
	assert_eq(_chat.handle_event(&"first_match").size(), 2, "fresh game shows the tutorial")
	GameState.from_dict(JSON.parse_string(json))
	_posted.clear()
	assert_eq(_chat.handle_event(&"first_match").size(), 0, "loaded save remembers the tutorial")
	assert_eq(_posted.size(), 0)


func test_once_key_is_per_payload() -> void:
	_chat.handle_event(&"cheat_unlocked", {"cheat_id": "speed_hack"})
	_chat.handle_event(&"cheat_unlocked", {"cheat_id": "speed_hack"})
	_chat.handle_event(&"cheat_unlocked", {"cheat_id": "infinite_ammo"})
	assert_eq(_posted.size(), 2)
	assert_true(GameState.chat_flags.has("unlock_speed_hack"))
	assert_true(GameState.chat_flags.has("unlock_infinite_ammo"))


func test_repeat_trigger_fires_every_time() -> void:
	_chat.handle_event(&"first_cash", {"amount": 5.0, "who": "you"})
	_chat.handle_event(&"first_cash", {"amount": 5.0, "who": "you"})
	assert_eq(_posted.size(), 2)


func test_placeholder_substitution() -> void:
	_chat.handle_event(&"first_cash", {"amount": 12.0, "who": "noob"})
	assert_eq(_posted[0][2], "$12 is cute, noob", "whole floats print without .0")
	assert_eq(ChatSystemScript.substitute("{a} and {missing}", {"a": 2.5}), "2.5 and {missing}")
	assert_eq(ChatSystemScript.substitute("{flag}", {"flag": true}), "true")


func test_cheat_name_is_derived_from_cheat_id() -> void:
	_chat.handle_event(&"cheat_unlocked", {"cheat_id": "speed_hack"})
	assert_eq(_posted[0][2], "New: Speed Hack")


func test_when_condition_filters_on_payload() -> void:
	_chat.handle_event(&"cheat_purchased", {"cheat_id": "wallhack", "level": 2})
	assert_eq(_posted.size(), 0)
	_chat.handle_event(&"cheat_purchased", {"cheat_id": "wallhack", "level": 1})
	assert_eq(_posted, [[&"system", "SYSTEM", "bought wallhack"]])


func test_bot_lines_get_a_bot_name() -> void:
	_chat.handle_event(&"player_died")
	assert_eq(_posted, [[&"bot", "botty", "gg ez"]])


func test_mute_filter_hides_bots_but_not_system_or_seller() -> void:
	_chat.set_channel_muted(ChatSystemScript.CHANNEL_BOT, true)
	_chat.handle_event(&"player_died")
	_chat.handle_event(&"first_match")
	_chat.tick(5.0)
	var channels := _posted.map(func(p): return p[0])
	assert_eq(channels, [&"system", &"seller"])
	assert_eq(_chat.history.size(), 3, "muted lines stay in history")
	assert_eq(_chat.visible_history().size(), 2)
	_chat.set_channel_muted(ChatSystemScript.CHANNEL_BOT, false)
	assert_eq(_chat.visible_history().size(), 3, "unmuting brings the log back")


func test_filter_muted_is_pure() -> void:
	var lines: Array[Dictionary] = [{"channel": &"bot", "sender": "a", "text": "x"}, {"channel": &"system", "sender": "SYSTEM", "text": "y"}]
	var out := ChatSystemScript.filter_muted(lines, {"bot": true})
	assert_eq(out.size(), 1)
	assert_eq(out[0]["channel"], &"system")


func test_history_is_capped() -> void:
	for i in range(60):
		_chat.post(&"system", "SYSTEM", str(i))
	assert_eq(_chat.history.size(), 50)
	assert_eq(_chat.history[0]["text"], "10")


func test_mute_setting_persists_to_settings_file() -> void:
	var path := "user://test_chat_settings.cfg"
	_chat.settings_path = path
	_chat.set_channel_muted(ChatSystemScript.CHANNEL_BOT, true)
	var other: Node = ChatSystemScript.new()
	other.settings_path = path
	other.load_settings()
	assert_true(other.is_muted(ChatSystemScript.CHANNEL_BOT))
	assert_false(other.is_muted(ChatSystemScript.CHANNEL_SYSTEM))
	other.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_autoload_derives_first_match_and_first_cash_once() -> void:
	# The real autoload with shipped chat.json, driven through EventBus.
	GameState.chat_flags.clear()
	EventBus.round_state_changed.emit(EventBus.ROUND_FREEZE, {"round": 1, "duration": 0.0})
	EventBus.round_state_changed.emit(EventBus.ROUND_FREEZE, {"round": 1, "duration": 0.0})
	assert_true(GameState.chat_flags.has("event:first_match"))
	assert_true(GameState.chat_flags.has("tut_welcome"))
	GameState.add_cash(10.0)
	assert_true(GameState.chat_flags.has("event:first_cash"))
	assert_true(GameState.chat_flags.has("seller_insert"))
	EventBus.cheat_toggled.emit("speed_hack", true)
	assert_true(GameState.chat_flags.has("event:cheat_first_use:speed_hack"))
	assert_true(GameState.chat_flags.has("seller_first_use_speed_hack"))
	ChatSystem.configure(DataRegistry.chat())  # drop queued lines so they do not leak into other tests


func test_chat_box_shows_fades_and_opens_log() -> void:
	var box: ChatBox = load("res://ui/chat/chat_box.tscn").instantiate()
	add_child_autofree(box)
	EventBus.chat_message_posted.emit(&"system", "SYSTEM", "Press B")
	assert_eq(box.recent_count(), 1)
	var box_cfg: Dictionary = ChatSystem.data()["box"]
	box._process(float(box_cfg["fade_after_s"]) + float(box_cfg["fade_time_s"]) + 0.1)
	assert_eq(box.recent_count(), 0, "corner line fades out")
	watch_signals(EventBus)
	box.open_log()
	assert_true(box.is_log_open())
	assert_signal_emitted_with_parameters(EventBus, "menu_toggled", [&"chat", true])
	box.close_log()
	assert_false(box.is_log_open())
