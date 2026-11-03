extends Node
## Event-driven chat feed. Every player instruction (controls, buy menu, mod
## menu) arrives here as a chat line; there are no tutorial pop-ups.
##
## Listens to EventBus gameplay signals and `chat_event`, matches them against
## the triggers in data/chat.json and posts lines through
## EventBus.chat_message_posted(channel, sender, text). See docs/DATA.md for the
## trigger format and docs/ARCHITECTURE.md for the event names.
##
## Once-only triggers are recorded in GameState.chat_flags (saved with the game)
## when their line actually posts, so the tutorial never repeats and a save made
## while a delayed line is still queued does not lose it. Channel mutes are a player setting stored in
## settings_path, not in the save.

## A channel was muted or unmuted (the chat UI rebuilds its view).
signal mute_changed(channel: StringName, muted: bool)

const CHANNEL_SYSTEM := &"system"
const CHANNEL_SELLER := &"seller"
const CHANNEL_BOT := &"bot"
const SETTINGS_PATH := "user://settings.cfg"
## Prefix for chat_flags entries that gate derived "first_*" events (not trigger ids).
const EVENT_FLAG_PREFIX := "event:"

## Every posted line, muted or not, oldest first: {channel, sender, text}.
var history: Array[Dictionary] = []
## channel -> true for muted channels.
var muted_channels: Dictionary = {}
## Where mute settings persist; "" disables persistence (tests).
var settings_path := SETTINGS_PATH
var rng := RandomNumberGenerator.new()

var _data: Dictionary = {}
var _pending: Array[Dictionary] = []  # {time_left, seq, channel, sender, text, flags}
var _seq := 0


func _ready() -> void:
	rng.randomize()
	configure(DataRegistry.chat())
	load_settings()
	EventBus.chat_event.connect(handle_event)
	EventBus.round_state_changed.connect(_on_round_state)
	EventBus.cash_changed.connect(_on_cash_changed)
	EventBus.cheat_unlocked.connect(func(id: String): handle_event(&"cheat_unlocked", {"cheat_id": id}))
	EventBus.cheat_purchased.connect(func(id: String, level: int): handle_event(&"cheat_purchased", {"cheat_id": id, "level": level}))
	EventBus.cheat_toggled.connect(_on_cheat_toggled)
	EventBus.player_died.connect(func(_info: Dictionary): handle_event(&"player_died", {}))
	EventBus.bot_killed.connect(_on_bot_killed)


func _process(delta: float) -> void:
	tick(delta)


## Replaces the chat data (chat.json root) and drops queued lines. Tests pass fixtures.
func configure(data: Dictionary) -> void:
	_data = data
	_pending.clear()


func data() -> Dictionary:
	return _data


# --- Triggers -----------------------------------------------------------------

## Runs every trigger for `event_name`. Lines with no delay post now; others are
## queued for tick(). Once-only flags (and `gate_flag`, if given) are written to
## GameState.chat_flags when the line posts; `gate_flag` is written at once if
## nothing is queued. Returns the lines produced (muted ones included), each
## {channel, sender, text, delay_s, trigger_id}.
func handle_event(event_name: StringName, payload: Dictionary = {}, gate_flag := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ctx := _context(payload)
	for trigger in _data.get("triggers", []):
		if trigger["event"] != String(event_name) or not matches(trigger, ctx):
			continue
		var flag := once_flag(trigger, ctx)
		if flag != "" and is_fired(flag):
			continue
		if trigger.has("chance") and rng.randf() >= float(trigger["chance"]):
			continue
		var flags: Array[String] = []
		if flag != "":
			flags.append(flag)
		if gate_flag != "":
			flags.append(gate_flag)
		var lines: Array = trigger["lines"]
		var channel := StringName(trigger["channel"])
		var msg := {
			"trigger_id": trigger["id"],
			"channel": channel,
			"sender": _sender(trigger, ctx),
			"text": substitute(lines[rng.randi() % lines.size()], ctx),
			"delay_s": float(trigger.get("delay_s", 0.0)),
		}
		out.append(msg)
		if msg["delay_s"] <= 0.0:
			_mark_fired(flags.filter(func(f): return f != gate_flag))  # gate: see below
			post(channel, msg["sender"], msg["text"])
		else:
			_seq += 1
			_pending.append({"time_left": msg["delay_s"], "seq": _seq, "channel": channel, "sender": msg["sender"], "text": msg["text"], "flags": flags})
	if gate_flag != "" and not is_fired(gate_flag):
		_mark_fired([gate_flag])  # nothing still queued under the gate: the event is done
	return out


## Advances queued lines by `delta` seconds and posts the ones that are due, in order.
func tick(delta: float) -> void:
	if _pending.is_empty():
		return
	var due: Array[Dictionary] = []
	var waiting: Array[Dictionary] = []
	for p in _pending:
		p["time_left"] -= delta
		if p["time_left"] <= 0.0:
			due.append(p)
		else:
			waiting.append(p)
	_pending = waiting
	due.sort_custom(func(a, b): return a["time_left"] < b["time_left"] or (a["time_left"] == b["time_left"] and a["seq"] < b["seq"]))
	for p in due:
		# A gate flag shared by several lines is saved with the last one still queued.
		_mark_fired(p["flags"].filter(func(f): return not is_fired(f)))
		post(p["channel"], p["sender"], p["text"])


func pending_count() -> int:
	return _pending.size()


## True if `flag` is saved in GameState.chat_flags or held by a queued line
## (so a trigger cannot queue twice while its first line is still waiting).
func is_fired(flag: String) -> bool:
	if GameState.chat_flags.has(flag):
		return true
	for p in _pending:
		if p["flags"].has(flag):
			return true
	return false


## Records a line and shows it unless its channel is muted. Returns true if shown.
func post(channel: StringName, sender: String, text: String) -> bool:
	history.append({"channel": channel, "sender": sender, "text": text})
	var cap := int(_data.get("box", {}).get("log_max_lines", 0))
	while cap > 0 and history.size() > cap:
		history.remove_at(0)
	if is_muted(channel):
		return false
	EventBus.chat_message_posted.emit(channel, sender, text)
	return true


## Lines the player should currently see in the log (mute filter applied).
func visible_history() -> Array[Dictionary]:
	return filter_muted(history, muted_channels)


# --- Mute setting ---------------------------------------------------------------

func is_muted(channel: StringName) -> bool:
	return muted_channels.get(String(channel), false)


func set_channel_muted(channel: StringName, muted: bool) -> void:
	if muted:
		muted_channels[String(channel)] = true
	else:
		muted_channels.erase(String(channel))
	save_settings()
	mute_changed.emit(channel, muted)


func load_settings() -> void:
	if settings_path == "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	muted_channels.clear()
	for channel in cfg.get_value("chat", "muted_channels", []):
		muted_channels[String(channel)] = true


func save_settings() -> void:
	if settings_path == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(settings_path)  # keep other sections; a missing file is fine
	cfg.set_value("chat", "muted_channels", muted_channels.keys())
	cfg.save(settings_path)


# --- Display helpers -----------------------------------------------------------------

## Palette colour for a channel (chat.json channels.<id>.color).
func channel_color(channel: StringName) -> Color:
	var name: String = _data.get("channels", {}).get(String(channel), {}).get("color", "missing")
	return DataRegistry.color(name)


## One display line, e.g. "[SYSTEM] Press B" (chat.json channels.<id>.format).
func format_line(channel: StringName, sender: String, text: String) -> String:
	var fmt: String = _data.get("channels", {}).get(String(channel), {}).get("format", "{sender}: {text}")
	return fmt.replace("{sender}", sender).replace("{text}", text)


## A UI string from chat.json "ui".
func ui_text(key: String) -> String:
	return str(_data.get("ui", {}).get(key, key))


# --- Pure helpers (static, unit-tested) ---------------------------------------------

## Replaces {key} with ctx values; unknown keys stay as written.
static func substitute(template: String, ctx: Dictionary) -> String:
	var out := template
	for key in ctx:
		out = out.replace("{%s}" % key, format_value(ctx[key]))
	return out


## Whole floats print without ".0" so "$12" not "$12.0"; bools as "true"/"false".
static func format_value(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v):
		return str(int(v))
	return str(v)


## True when every trigger.when[key] equals the formatted ctx[key].
static func matches(trigger: Dictionary, ctx: Dictionary) -> bool:
	var conditions: Dictionary = trigger.get("when", {})
	for key in conditions:
		if not ctx.has(key) or format_value(ctx[key]) != str(conditions[key]):
			return false
	return true


## The GameState.chat_flags key for a once-only trigger, "" for repeating ones.
## once_key (with placeholders) lets one trigger fire once per cheat.
static func once_flag(trigger: Dictionary, ctx: Dictionary) -> String:
	if not trigger.get("once", false):
		return ""
	return substitute(str(trigger.get("once_key", trigger["id"])), ctx)


## Lines from `lines` whose channel is not in `muted`.
static func filter_muted(lines: Array[Dictionary], muted: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in lines:
		if not muted.get(String(m["channel"]), false):
			out.append(m)
	return out


# --- Internals -------------------------------------------------------------------------

## Payload plus derived placeholders (cheat_name from cheat_id).
func _context(payload: Dictionary) -> Dictionary:
	var ctx := payload.duplicate()
	if ctx.has("cheat_id") and not ctx.has("cheat_name"):
		ctx["cheat_name"] = _cheat_name(str(ctx["cheat_id"]))
	return ctx


func _cheat_name(cheat_id: String) -> String:
	return str(DataRegistry.cheat(cheat_id).get("name", cheat_id.capitalize()))


## trigger.sender > payload.bot_name > channel sender > random bot name.
func _sender(trigger: Dictionary, ctx: Dictionary) -> String:
	if trigger.has("sender"):
		return str(trigger["sender"])
	if trigger["channel"] == String(CHANNEL_BOT) and ctx.has("bot_name"):
		return str(ctx["bot_name"])
	var sender: String = _data.get("channels", {}).get(trigger["channel"], {}).get("sender", "")
	if sender != "":
		return sender
	var names: Array = _data.get("bot_names", [])
	return str(names[rng.randi() % names.size()]) if not names.is_empty() else ""


func _mark_fired(flags: Array) -> void:
	for f in flags:
		GameState.chat_flags[f] = true


## Fires a derived event only the first time ever. The event flag is saved in
## chat_flags once its last queued line posts, like once-only triggers.
func _first_time(event_name: String, payload: Dictionary = {}) -> void:
	var flag := EVENT_FLAG_PREFIX + event_name
	if is_fired(flag):
		return
	handle_event(StringName(event_name.get_slice(":", 0)), payload, flag)


func _on_round_state(state: StringName, info: Dictionary) -> void:
	var round_payload := {"round": int(info.get("round", 0))}
	if state == EventBus.ROUND_FREEZE:
		_first_time("first_match")
		handle_event(&"round_start", round_payload)
	elif state == EventBus.ROUND_LIVE:
		handle_event(&"round_live", round_payload)


func _on_cash_changed(total: float, delta: float) -> void:
	if delta > 0.0:
		_first_time("first_cash", {"amount": delta, "total": total})


func _on_cheat_toggled(cheat_id: String, enabled: bool) -> void:
	if enabled:
		_first_time("cheat_first_use:" + cheat_id, {"cheat_id": cheat_id})


func _on_bot_killed(_bot: Node, info: Dictionary) -> void:
	handle_event(&"bot_killed", {"headshot": info.get("headshot", false), "bot_type": info.get("bot_type", "")})
