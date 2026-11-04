class_name SfxPlayer
extends Node
## Plays SfxSynth sounds for gameplay EventBus signals (TASK-028) through a
## small pool of players on the "SFX" bus (created if missing; the settings
## menu, TASK-044, drives its volume). Gunshots and reloads are played by each
## Weapon itself. `played` logs recent sound names for tests.

const BUS := "SFX"
const POOL := 10
const HIT_GAP_S := 0.04      ## shotgun pellets / LMG: at most one hit sound per gap
const LOG_MAX := 50

var played: Array[String] = []
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last_hit_ms := -100000


## Makes sure the "SFX" bus exists (sends to Master). Safe to call any time.
static func ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, "Master")


func _ready() -> void:
	ensure_bus()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_pool.append(p)
	EventBus.bot_damaged.connect(func(_bot, info): play_hit(bool(info.get("headshot", false))))
	EventBus.kill_rewarded.connect(func(_cash, _info): play("kill"))
	EventBus.loot_collected.connect(func(_value): play("loot"))
	EventBus.player_damaged.connect(func(_a, _h, _s): play("hurt", -3.0))
	EventBus.player_died.connect(func(_info): play("death"))
	EventBus.round_state_changed.connect(_on_round_state)
	EventBus.cheat_purchased.connect(func(_id, _lvl): play("inject"))
	EventBus.cheat_unlocked.connect(func(_id): play("unlock"))
	EventBus.arena_selected.connect(func(_id): play("unlock"))
	EventBus.gun_upgraded.connect(func(_id, _s, _l): play("buy"))
	EventBus.menu_toggled.connect(func(_id, open): play("menu_open" if open else "menu_close", -6.0))
	EventBus.scope_changed.connect(func(_on): play("scope", -4.0))
	EventBus.multi_kill.connect(func(_c, _m): play("unlock", -2.0))
	EventBus.bonus_paid.connect(func(_r, _c, _p): play("loot"))


## Plays `sound_name` on the next free pooled player. Returns the player.
func play(sound_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.04) -> AudioStreamPlayer:
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = SfxSynth.get_sound(sound_name)
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	if p.is_inside_tree():
		p.play()
	played.append(sound_name)
	if played.size() > LOG_MAX:
		played.remove_at(0)
	return p


## Hit tick (headshot ding), rate-limited so pellets and LMGs don't stack.
func play_hit(headshot: bool) -> void:
	var now := Time.get_ticks_msec()
	if not headshot and now - _last_hit_ms < int(HIT_GAP_S * 1000.0):
		return
	_last_hit_ms = now
	play("headshot" if headshot else "hit", -2.0)


func _on_round_state(state: StringName, _info: Dictionary) -> void:
	if state == EventBus.ROUND_LIVE:
		play("round_live")
	elif state == EventBus.ROUND_SUMMARY:
		play("round_end")
