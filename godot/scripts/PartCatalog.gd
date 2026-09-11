extends RefCounted
class_name PartCatalog

const MAX_OWNED := 5
const OFFER_COUNT := 3
const REFRESH_BASE_COST := 3
const REFRESH_STEP_COST := 2
const ATLAS := preload("res://assets/hud/parts-atlas-hd.png")

const PARTS := [
	{"id":"flux_magnet", "name":"Flux Magnet", "price":60, "rarity":"STANDARD", "ability":"magnet", "description":"Pulls nearby coins from adjacent lanes.", "atlas":0},
	{"id":"golden_gearbox", "name":"Golden Gearbox", "price":160, "rarity":"PROTOTYPE", "ability":"double_gold", "description":"Every collected coin is worth 2 gold.", "atlas":1},
	{"id":"redline_engine", "name":"Redline Engine", "price":120, "rarity":"TUNED", "ability":"speed", "description":"Increases driving speed by 7%.", "atlas":2},
	{"id":"vector_wheel", "name":"Vector Wheel", "price":90, "rarity":"TUNED", "ability":"steering", "description":"Makes lane changes 18% faster.", "atlas":3},
	{"id":"stormcut_wipers", "name":"StormCut Wipers", "price":70, "rarity":"STANDARD", "ability":"wipers", "description":"Clears most rain from the driver's view.", "atlas":4},
	{"id":"rallycore_suspension", "name":"RallyCore Suspension", "price":100, "rarity":"TUNED", "ability":"suspension", "description":"Reduces collision slowdown and recovery by 40%.", "atlas":5},
	{"id":"turbo_dynamo", "name":"Turbo Dynamo", "price":130, "rarity":"PROTOTYPE", "ability":"turbo_duration", "description":"Extends every turbo activation by 35%.", "atlas":6},
	{"id":"turbo_vacuum", "name":"Turbo Vacuum", "price":150, "rarity":"PROTOTYPE", "ability":"turbo_vacuum", "description":"Collects coins from every lane while turbo is active.", "icon_path":"res://assets/hud/parts/turbo-vacuum.png"},
	{"id":"momentum_crown", "name":"Momentum Crown", "price":170, "rarity":"PROTOTYPE", "ability":"momentum_crown", "description":"Coins are worth 3 gold at a 10x combo or higher.", "icon_path":"res://assets/hud/parts/momentum-crown.png"},
	{"id":"nitro_capacitor", "name":"Nitro Capacitor", "price":125, "rarity":"TUNED", "ability":"nitro_capacitor", "description":"Coins collected during turbo extend it by 0.25 seconds.", "icon_path":"res://assets/hud/parts/nitro-capacitor.png"},
	{"id":"phantom_differential", "name":"Phantom Differential", "price":145, "rarity":"PROTOTYPE", "ability":"phantom_differential", "description":"Ignores the first collision in each race.", "icon_path":"res://assets/hud/parts/phantom-differential.png"},
	{"id":"quickshift_transmission", "name":"Quickshift Transmission", "price":105, "rarity":"TUNED", "ability":"quickshift", "description":"Every 5 clean lane changes grants a short speed boost.", "icon_path":"res://assets/hud/parts/quickshift-transmission.png"},
	{"id":"golden_alternator", "name":"Golden Alternator", "price":95, "rarity":"TUNED", "ability":"golden_alternator", "description":"Every 10th collected coin awards 1 bonus gold.", "icon_path":"res://assets/hud/parts/golden-alternator.png"},
	{"id":"savings_coil", "name":"Savings Coil", "price":75, "rarity":"STANDARD", "ability":"savings_coil", "description":"Reduces every shop refresh cost by 1 gold.", "icon_path":"res://assets/hud/parts/savings-coil.png"},
	{"id":"nightvision_visor", "name":"NightVision Visor", "price":110, "rarity":"TUNED", "ability":"nightvision", "description":"Cuts fog and rain obstruction in half.", "icon_path":"res://assets/hud/parts/nightvision-visor.png"},
	{"id":"slipstream_coil", "name":"Slipstream Coil", "price":120, "rarity":"TUNED", "ability":"near_miss_charge", "description":"Near misses fill 25% turbo instead of 20%.", "icon_path":"res://assets/hud/parts/slipstream-coil.png"},
	{"id":"impact_reserve", "name":"Impact Reserve", "price":140, "rarity":"PROTOTYPE", "ability":"turbo_retention", "description":"Keeps half of your turbo charge when a collision breaks the combo.", "icon_path":"res://assets/hud/parts/impact-reserve.png"},
]


static func get_part(part_id: String) -> Dictionary:
	for part in PARTS:
		if part["id"] == part_id:
			return part
	return {}


static func has_part(part_id: String) -> bool:
	return not get_part(part_id).is_empty()


static func icon(part: Dictionary) -> Texture2D:
	if part.has("icon_path"):
		return load(str(part["icon_path"])) as Texture2D
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	var cell := Vector2(ATLAS.get_width() / 4.0, ATLAS.get_height() / 2.0)
	var index := int(part["atlas"])
	texture.region = Rect2(Vector2(index % 4, index / 4) * cell, cell)
	return texture


static func refresh_cost(refresh_count: int, discounted: bool = false) -> int:
	return maxi(1, REFRESH_BASE_COST + REFRESH_STEP_COST * refresh_count - (1 if discounted else 0))


static func roll_offers(owned_ids: Array[String], rng_seed: int, wallet_gold: int = -1, excluded_ids: Array[String] = []) -> Array[String]:
	var pool: Array[String] = []
	for part in PARTS:
		if part["id"] not in owned_ids and part["id"] not in excluded_ids:
			pool.append(part["id"])
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in range(pool.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, i)
		var value := pool[i]
		pool[i] = pool[swap_index]
		pool[swap_index] = value
	var result: Array[String] = pool.slice(0, mini(OFFER_COUNT, pool.size()))
	if wallet_gold >= 0 and not result.is_empty():
		var result_has_affordable := false
		for part_id in result:
			result_has_affordable = result_has_affordable or int(get_part(part_id)["price"]) <= wallet_gold
		if not result_has_affordable:
			for part_id in pool:
				if int(get_part(part_id)["price"]) <= wallet_gold:
					result[result.size() - 1] = part_id
					break
	return result
