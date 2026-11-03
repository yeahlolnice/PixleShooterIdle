extends Control
## HUD. Reads only EventBus signals and GameState (initial values).

const CASH_TICK_SPEED := 4.0  ## shown value closes 1 - e^-speed*dt of the gap per frame

var _cash_shown := 0.0
var _cash_target := 0.0
var _state: StringName = &""
var _time_left := 0.0
var _round := 0
var _max_health := 1.0

@onready var health_label: Label = $Margin/Bottom/Health
@onready var ammo_label: Label = $Margin/Bottom/Ammo
@onready var cash_label: Label = $Margin/Top/Cash
@onready var timer_label: Label = $Margin/Top/Timer
@onready var freeze_label: Label = $FreezeLabel
@onready var summary_panel: PanelContainer = $SummaryPanel
@onready var summary_label: Label = $SummaryPanel/SummaryText


func _ready() -> void:
	_max_health = float(DataRegistry.player().get("max_health", 100))
	_cash_target = GameState.cash
	_cash_shown = _cash_target
	set_health(_max_health)
	set_ammo(0, 0)
	summary_panel.hide()
	freeze_label.hide()
	_add_cheat_strip()
	var feedback := HudFeedback.new()
	feedback.name = "Feedback"
	add_child(feedback)
	_refresh_cash()
	EventBus.cash_changed.connect(_on_cash_changed)
	EventBus.ammo_changed.connect(set_ammo)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.round_state_changed.connect(_on_round_state)
	EventBus.round_summary.connect(_on_round_summary)
	EventBus.game_state_loaded.connect(_on_loaded)


## Active-cheat list in the top-right corner, under the round timer.
func _add_cheat_strip() -> void:
	var strip := CheatStrip.new()
	strip.name = "CheatStrip"
	strip.anchor_left = 1.0
	strip.anchor_right = 1.0
	strip.offset_left = -320.0
	strip.offset_right = -16.0
	strip.offset_top = 64.0   # below the round timer
	strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(strip)


func _process(delta: float) -> void:
	if not is_equal_approx(_cash_shown, _cash_target):
		_cash_shown = lerpf(_cash_shown, _cash_target, 1.0 - exp(-CASH_TICK_SPEED * delta))
		if absf(_cash_target - _cash_shown) < 0.5:
			_cash_shown = _cash_target
		_refresh_cash()
	if _time_left > 0.0:
		_time_left = maxf(_time_left - delta, 0.0)
		_refresh_timer()


func set_health(value: float) -> void:
	health_label.text = "HP %d" % ceili(maxf(value, 0.0))


func set_ammo(in_mag: int, mag_size: int) -> void:
	ammo_label.text = "AMMO %d/%d" % [in_mag, mag_size] if mag_size > 0 else "AMMO ∞"


func _refresh_cash() -> void:
	cash_label.text = Fmt.cash(roundf(_cash_shown))


func _refresh_timer() -> void:
	var secs := ceili(_time_left)
	if _state == EventBus.ROUND_FREEZE:
		freeze_label.text = "BUY TIME  %d" % secs
		timer_label.text = "Round %d" % _round
	else:
		timer_label.text = "Round %d  %d:%02d" % [_round, secs / 60, secs % 60]


func _on_cash_changed(total: float, _delta: float) -> void:
	_cash_target = total


func _on_loaded() -> void:
	_cash_target = GameState.cash
	_cash_shown = _cash_target
	_refresh_cash()


func _on_player_damaged(_amount: float, health_left: float, _source: Node) -> void:
	set_health(health_left)


func _on_player_spawned(_player: Node) -> void:
	set_health(_max_health)


func _on_round_state(state: StringName, info: Dictionary) -> void:
	_state = state
	_round = int(info.get("round", 0))
	_time_left = float(info.get("duration", 0.0))
	freeze_label.visible = state == EventBus.ROUND_FREEZE
	summary_panel.visible = state == EventBus.ROUND_SUMMARY
	_refresh_timer()


func _on_round_summary(s: Dictionary) -> void:
	summary_label.text = "ROUND %d COMPLETE\nKills: %d\nHeadshots: %d\nBest streak: %d\nCash earned: %s\nDeaths: %d" % [
		s.get("round", 0), s.get("kills", 0), s.get("headshots", 0),
		s.get("best_streak", 0), Fmt.cash(float(s.get("cash", 0.0))), s.get("deaths", 0)]
