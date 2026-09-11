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
	{"id":"coin_scanner", "name":"Coin Scanner", "price":80, "rarity":"STANDARD", "ability":"coin_scanner", "description":"Highlights coin lanes and spawns coins sooner.", "atlas":7},
]


static func get_part(part_id: String) -> Dictionary:
	for part in PARTS:
		if part["id"] == part_id:
			return part
	return {}


static func has_part(part_id: String) -> bool:
	return not get_part(part_id).is_empty()


static func icon(part: Dictionary) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	var cell := Vector2(ATLAS.get_width() / 4.0, ATLAS.get_height() / 2.0)
	var index := int(part["atlas"])
	texture.region = Rect2(Vector2(index % 4, index / 4) * cell, cell)
	return texture


static func refresh_cost(refresh_count: int) -> int:
	return REFRESH_BASE_COST + REFRESH_STEP_COST * refresh_count


static func roll_offers(owned_ids: Array[String], rng_seed: int, wallet_gold: int = -1) -> Array[String]:
	var pool: Array[String] = []
	for part in PARTS:
		if part["id"] not in owned_ids:
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
