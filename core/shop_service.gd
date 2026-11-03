class_name ShopService
extends RefCounted
## UI-free gun purchasing. Prices and the gun list come from guns.json via
## DataRegistry; cash is validated and spent through GameState / Economy.
## The caller (BuyMenu) equips the returned gun through WeaponManager.

enum Result { OK, UNKNOWN_GUN, LOCKED, CANNOT_AFFORD, ALREADY_EQUIPPED, NOT_OWNED, MAXED, UNKNOWN_STAT }


## Guns offered for sale (everything in guns.json except the free starter).
static func catalog() -> Array:
	var out: Array = []
	var starter := DataRegistry.starter_gun_id()
	for g in DataRegistry.guns():
		if g["id"] != starter:
			out.append(g)
	return out


static func price(gun_id: String) -> float:
	return float(DataRegistry.gun(gun_id).get("price", 0.0))


static func is_unlocked(gun_id: String) -> bool:
	return GameState.kills >= int(DataRegistry.gun(gun_id).get("unlock_kills", 0))


## Owned guns (and the starter) cost nothing to switch back to.
static func is_owned(gun_id: String) -> bool:
	return gun_id == DataRegistry.starter_gun_id() or GameState.owns_gun(gun_id)


static func can_buy(gun_id: String) -> bool:
	return check(gun_id) == Result.OK


static func check(gun_id: String) -> Result:
	if DataRegistry.gun(gun_id).is_empty():
		return Result.UNKNOWN_GUN
	if not is_unlocked(gun_id):
		return Result.LOCKED
	if GameState.equipped_gun_id == gun_id or (gun_id == DataRegistry.starter_gun_id() and GameState.equipped_gun_id == ""):
		return Result.ALREADY_EQUIPPED
	if is_owned(gun_id):
		return Result.OK
	if not Economy.can_afford(GameState.cash, price(gun_id)):
		return Result.CANNOT_AFFORD
	return Result.OK


## Buys (or re-equips an owned) gun. Deducts exactly the price, records
## ownership and the equipped id. Returns a Result; only OK changes state.
static func buy(gun_id: String) -> Result:
	var r := check(gun_id)
	if r != Result.OK:
		return r
	if not is_owned(gun_id):
		if not GameState.try_spend(price(gun_id)):
			return Result.CANNOT_AFFORD
		GameState.add_owned_gun(gun_id)
	GameState.equipped_gun_id = gun_id
	return Result.OK


static func message(r: Result) -> String:
	match r:
		Result.OK: return "Equipped!"
		Result.UNKNOWN_GUN: return "Unknown gun"
		Result.LOCKED: return "Locked: not enough kills"
		Result.CANNOT_AFFORD: return "Not enough cash"
		Result.ALREADY_EQUIPPED: return "Already equipped"
		Result.NOT_OWNED: return "Buy the gun first"
		Result.MAXED: return "Fully upgraded"
		Result.UNKNOWN_STAT: return "Unknown upgrade"
	return ""


# --- Gun upgrades (TASK-024) ------------------------------------------------------
# guns.json "upgrades": stat -> {name, step, max_level, min_base_cost, cost_mult, cost_growth}.
# Level n multiplies the stat by 1 + step * n. Cost of the next level:
# max(gun price, min_base_cost) * cost_mult * cost_growth ^ owned_level.

## The gun in hand ("" in GameState means the starter).
static func equipped_id() -> String:
	return GameState.equipped_gun_id if GameState.equipped_gun_id != "" else DataRegistry.starter_gun_id()


static func upgrade_stats() -> Array:
	return DataRegistry.gun_upgrades().keys()


static func upgrade_level(gun_id: String, stat: String) -> int:
	return GameState.gun_upgrade_level(gun_id, stat)


## Multiplier the owned level gives (1.0 = not upgraded).
static func upgrade_mult(gun_id: String, stat: String) -> float:
	var def: Dictionary = DataRegistry.gun_upgrades().get(stat, {})
	return 1.0 + float(def.get("step", 0.0)) * upgrade_level(gun_id, stat)


static func upgrade_cost(gun_id: String, stat: String) -> float:
	var def: Dictionary = DataRegistry.gun_upgrades().get(stat, {})
	var base := maxf(price(gun_id), float(def.get("min_base_cost", 0.0)))
	return Economy.cost(base * float(def.get("cost_mult", 1.0)), float(def.get("cost_growth", 1.0)), upgrade_level(gun_id, stat))


static func check_upgrade(gun_id: String, stat: String) -> Result:
	if DataRegistry.gun(gun_id).is_empty():
		return Result.UNKNOWN_GUN
	var def: Dictionary = DataRegistry.gun_upgrades().get(stat, {})
	if def.is_empty():
		return Result.UNKNOWN_STAT
	if not is_owned(gun_id):
		return Result.NOT_OWNED
	if upgrade_level(gun_id, stat) >= int(def["max_level"]):
		return Result.MAXED
	if not Economy.can_afford(GameState.cash, upgrade_cost(gun_id, stat)):
		return Result.CANNOT_AFFORD
	return Result.OK


## Buys one level of `stat` for `gun_id`. Only OK changes state; emits gun_upgraded.
static func buy_upgrade(gun_id: String, stat: String) -> Result:
	var r := check_upgrade(gun_id, stat)
	if r != Result.OK:
		return r
	if not GameState.try_spend(upgrade_cost(gun_id, stat)):
		return Result.CANNOT_AFFORD
	var level := upgrade_level(gun_id, stat) + 1
	GameState.set_gun_upgrade_level(gun_id, stat, level)
	EventBus.gun_upgraded.emit(gun_id, stat, level)
	return Result.OK
