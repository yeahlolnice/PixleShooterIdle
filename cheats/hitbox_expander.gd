class_name HitboxExpander
extends CheatBase
## Hitbox Expander (Combat): bot head hitboxes grow by `head_scale` (1.5x at
## level 1 -> 4x at max), so more shots count as headshots and near misses hit.
## Only the invisible hitbox grows, not the head mesh. Sets the static
## Bot.head_hitbox_scale (bots spawned later read it in _build_body) and resizes
## the bots already in the scene; remove() puts every head back to 1x.

const BOTS_GROUP := "bots"


func apply(player: Object, level: int) -> void:
	super.apply(player, level)
	_set_scale(player, maxf(float(value_at("head_scale", level)), 1.0))


func remove(player: Object) -> void:
	super.remove(player)
	_set_scale(player, 1.0)


func _set_scale(player: Object, head_scale: float) -> void:
	Bot.head_hitbox_scale = head_scale
	if player is Node and (player as Node).is_inside_tree():
		for bot in (player as Node).get_tree().get_nodes_in_group(BOTS_GROUP):
			if bot.has_method("apply_head_hitbox_scale"):
				bot.apply_head_hitbox_scale()
