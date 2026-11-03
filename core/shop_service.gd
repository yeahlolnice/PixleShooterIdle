class_name ShopService
extends RefCounted
## UI-free gun purchasing. Prices and the gun list come from guns.json via
## DataRegistry; cash is validated and spent through GameState / Economy.
## The caller (BuyMenu) equips the returned gun through WeaponManager.

enum Result { OK, UNKNOWN_GUN, LOCKED, CANNOT_AFFORD, ALREADY_EQUIPPED }


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
	return ""
