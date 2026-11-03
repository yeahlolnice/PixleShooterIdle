class_name ArenaService
extends RefCounted
## UI-free arena progression (TASK-026). Arenas come from arenas.json in
## "order"; each unlocks at its `unlock_kills` lifetime kills (missing = 0), so
## an unlocked arena stays unlocked through bans. The pick is saved in
## GameState.current_arena_id; select() emits EventBus.arena_selected and Main
## rebuilds the world.


static func unlock_kills(arena_id: String) -> int:
	return int(DataRegistry.arena(arena_id).get("unlock_kills", 0))


static func is_unlocked(arena_id: String) -> bool:
	return not DataRegistry.arena(arena_id).is_empty() and GameState.lifetime_kills >= unlock_kills(arena_id)


## The arena to play: the saved pick if it still exists and is unlocked, else the first.
static func selected_id() -> String:
	var id := GameState.current_arena_id
	return id if id != "" and is_unlocked(id) else DataRegistry.first_arena_id()


## Picks `arena_id`. False (and no change) when it is unknown, locked or already picked.
static func select(arena_id: String) -> bool:
	if not is_unlocked(arena_id) or arena_id == selected_id():
		return false
	GameState.current_arena_id = arena_id
	EventBus.arena_selected.emit(arena_id)
	return true


## Arena ids whose unlock_kills is exactly `lifetime_kills` (just crossed with this kill).
static func unlocked_at(lifetime_kills: int) -> Array:
	var out: Array = []
	for a in DataRegistry.arenas():
		var need := int(a.get("unlock_kills", 0))
		if need > 0 and need == lifetime_kills:
			out.append(a["id"])
	return out
