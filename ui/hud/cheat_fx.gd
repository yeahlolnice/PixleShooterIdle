class_name CheatFx
extends Control
## On-screen cheat visuals (TASK-030), so cheats look as loud as they are:
##   Aimbot      FOV circle around the crosshair, sized from its fov_deg against
##               the camera FOV (covers the screen at max level)
##   God Mode    rainbow shimmer round the screen edge while invulnerable
##   Triggerbot  red ring flash on the crosshair when it fires (cheat_fired)
##   Spinbot     white whip streak across the screen when it snaps and fires
## Reads CheatSystem.effect() and the player (player_spawned / "player" group).

const FLASH_S := 0.12
const STREAK_S := 0.18
const SHIMMER_PX := 10.0
const SHIMMER_HUE_SPEED := 0.6   ## hue cycles per second

var player: Object = null
var _flash_left := 0.0
var _streak_left := 0.0
var _hue := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.player_spawned.connect(func(p): player = p)
	EventBus.cheat_fired.connect(_on_cheat_fired)


## Screen radius (pixels) of a cone `fov_deg` off the crosshair, for a camera
## with vertical FOV `camera_fov_deg` on a viewport `height_px` tall. Cones at or
## past 90 degrees return a radius that covers the whole screen.
static func fov_radius_px(fov_deg: float, camera_fov_deg: float, height_px: float, screen_size: Vector2) -> float:
	if fov_deg <= 0.0:
		return 0.0
	if fov_deg >= 89.0:
		return screen_size.length()
	return tan(deg_to_rad(fov_deg)) / tan(deg_to_rad(camera_fov_deg) * 0.5) * height_px * 0.5


func aimbot_radius() -> float:
	var fov := float(CheatSystem.effect("aimbot", "fov_deg"))
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if fov <= 0.0 or cam == null:
		return 0.0
	return fov_radius_px(fov, cam.fov, size.y, size)


func shows_god_shimmer() -> bool:
	var p := _player()
	return p != null and p.has_method("is_invulnerable") and p.is_invulnerable()


func flash_active() -> bool:
	return _flash_left > 0.0


func streak_active() -> bool:
	return _streak_left > 0.0


func _player() -> Object:
	if not is_instance_valid(player) and is_inside_tree():
		player = get_tree().get_first_node_in_group("player")
	return player if is_instance_valid(player) else null


func _on_cheat_fired(cheat_id: String) -> void:
	if cheat_id == "triggerbot":
		_flash_left = FLASH_S
	elif cheat_id == "spinbot":
		_streak_left = STREAK_S


func _process(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	_streak_left = maxf(0.0, _streak_left - delta)
	_hue = fposmod(_hue + SHIMMER_HUE_SPEED * delta, 1.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := aimbot_radius()
	if r > 0.0 and r < size.length():
		draw_arc(c, r, 0.0, TAU, 96, Color(1, 0.25, 0.25, 0.55), 2.0, true)
	if shows_god_shimmer():
		for i in 4:
			var col := Color.from_hsv(fposmod(_hue + i * 0.25, 1.0), 0.8, 1.0, 0.35)
			match i:
				0: draw_rect(Rect2(0, 0, size.x, SHIMMER_PX), col)
				1: draw_rect(Rect2(size.x - SHIMMER_PX, 0, SHIMMER_PX, size.y), col)
				2: draw_rect(Rect2(0, size.y - SHIMMER_PX, size.x, SHIMMER_PX), col)
				3: draw_rect(Rect2(0, 0, SHIMMER_PX, size.y), col)
	if _flash_left > 0.0:
		draw_arc(c, 18.0, 0.0, TAU, 32, Color(1, 0.2, 0.2, _flash_left / FLASH_S), 3.0, true)
	if _streak_left > 0.0:
		var a := _streak_left / STREAK_S
		draw_line(Vector2(0, c.y), Vector2(size.x, c.y), Color(1, 1, 1, 0.5 * a), 6.0 * a)
