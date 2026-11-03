class_name CheatTargeting
extends RefCounted
## Shared aim helpers for Aimbot, Triggerbot and Spinbot: which bots are alive
## and visible from the player's camera, how far each head is off the
## crosshair, and which bot (if any) is under the crosshair.
## Line of sight uses Layers.WORLD only, so bots and the player never block it.

## Name of the bot's head mesh (Bot._build_body).
const HEAD_NODE := "Head"


## True while a cheat may move the aim or fire for `player`: alive, no menu
## open, camera present.
static func can_act(player: Node) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	if player.get("is_dead") == true or player.get("input_enabled") == false:
		return false
	return player.get("camera") is Camera3D


## Alive, not being freed, and not dead.
static func is_live(bot: Variant) -> bool:
	if not (is_instance_valid(bot) and bot is Node3D) or bot.is_queued_for_deletion():
		return false
	return not (bot.has_method("is_dead") and bot.is_dead())


static func head_of(bot: Node3D) -> Vector3:
	var head := bot.get_node_or_null(HEAD_NODE) as Node3D
	return head.global_position if head else bot.global_position


## Live bots whose head the camera can see, as
## [{"bot": Node3D, "head": Vector3, "angle_deg": degrees off the crosshair}].
static func visible_targets(camera: Camera3D) -> Array:
	var out: Array = []
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var space := camera.get_world_3d().direct_space_state
	for bot in camera.get_tree().get_nodes_in_group("bots"):
		if not is_live(bot):
			continue
		var head := head_of(bot)
		var query := PhysicsRayQueryParameters3D.create(origin, head, Layers.WORLD)
		if not space.intersect_ray(query).is_empty():
			continue
		out.append({"bot": bot, "head": head, "angle_deg": rad_to_deg(forward.angle_to(head - origin))})
	return out


## The visible target closest to the crosshair within `max_angle_deg`, or {}.
static func best_target(camera: Camera3D, max_angle_deg: float) -> Dictionary:
	var best := {}
	for t in visible_targets(camera):
		if t["angle_deg"] <= max_angle_deg and (best.is_empty() or t["angle_deg"] < best["angle_deg"]):
			best = t
	return best


## The live bot whose hitbox the crosshair ray hits first within `range_m`, or null.
static func bot_under_crosshair(camera: Camera3D, range_m: float) -> Node3D:
	var origin := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin - camera.global_transform.basis.z * range_m, Layers.WORLD | Layers.HITBOXES)
	query.collide_with_areas = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit["collider"]
	var bot: Variant = collider.get_meta("bot") if collider.has_meta("bot") else null
	return bot if is_live(bot) else null
