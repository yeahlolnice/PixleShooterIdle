class_name HitFx
extends Node3D
## World-space juice (TASK-027): floating damage numbers on bot_damaged
## (gold on headshots) and "+$240" over the body on kill_rewarded. Labels
## billboard, draw over walls, rise and fade, then free themselves.

const RISE_M := 0.9
const LIFE_S := 0.7
const CASH_LIFE_S := 1.1
## Screen-constant sizes (fixed_size labels), so pop-ups read the same near and far.
const DAMAGE_PIXEL := 0.0016
const CASH_PIXEL := 0.0022
const HEAD_HEIGHT := Vector3(0, 1.9, 0)
const CASH_HEIGHT := Vector3(0, 2.3, 0)


func _ready() -> void:
	EventBus.bot_damaged.connect(_on_bot_damaged)
	EventBus.kill_rewarded.connect(_on_kill_rewarded)


func _on_bot_damaged(_bot: Node, info: Dictionary) -> void:
	var headshot := bool(info.get("headshot", false))
	spawn_label("-%d" % roundi(float(info.get("amount", 0.0))), info.get("position", Vector3.ZERO) + HEAD_HEIGHT,
		DataRegistry.color("cash") if headshot else Color.WHITE, DAMAGE_PIXEL * (1.3 if headshot else 1.0), LIFE_S)


func _on_kill_rewarded(cash: float, info: Dictionary) -> void:
	spawn_label("+" + Fmt.cash(cash), info.get("position", Vector3.ZERO) + CASH_HEIGHT,
		DataRegistry.color("cash"), CASH_PIXEL, CASH_LIFE_S)


func spawn_label(text: String, at: Vector3, color: Color, pixel: float, life: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.outline_size = 10
	l.font_size = 48
	l.pixel_size = pixel
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	add_child(l)
	l.global_position = at
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position", at + Vector3(0, RISE_M, 0), life)
	tw.tween_property(l, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)
	return l
