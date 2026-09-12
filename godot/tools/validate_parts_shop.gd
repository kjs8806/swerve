extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	# Godot quirk specific to raw `--script` SceneTree entry points: the first
	# LevelConfig-scripted resource loaded transitively through a static
	# function (LevelCatalog.get_level(), reached below via Main.tscn/Race.gd)
	# can come back reporting its class as plain `Resource` instead of
	# `LevelConfig`, which then fails every strictly-typed read/assignment of
	# it. Referencing the class directly first warms up its global
	# registration so every subsequent load resolves correctly. Confirmed
	# via isolated repro; normal gameplay never hits this because the engine
	# warms it up before instantiating the real project's main scene.
	LevelConfig.new()
	_expect(PartCatalog.PARTS.size() == 20, "Expected twenty parts")
	var ids: Array[String] = []
	for part in PartCatalog.PARTS:
		_expect(not ids.has(part["id"]), "Duplicate part ID: %s" % part["id"])
		ids.append(part["id"])
		_expect(int(part["price"]) > 0, "%s has invalid price" % part["name"])
		_expect(PartCatalog.icon(part) != null, "%s has no icon" % part["name"])
	_expect("coin_scanner" not in ids, "Removed Coin Scanner is still in the catalog")
	var offers := PartCatalog.roll_offers([], 12345)
	_expect(offers.size() == 3, "A refresh must produce three offers")
	_expect(offers[0] != offers[1] and offers[1] != offers[2] and offers[0] != offers[2], "Refresh produced duplicates")
	_expect(PartCatalog.refresh_cost(0) == 3 and PartCatalog.refresh_cost(3) == 9, "Refresh pricing is incorrect")
	_expect(PartCatalog.refresh_cost(0, true) == 2 and PartCatalog.refresh_cost(3, true) == 8, "Savings Coil discount is incorrect")
	var next_offers := PartCatalog.roll_offers([], 54321, -1, offers)
	for part_id in next_offers:
		_expect(part_id not in offers, "Refresh repeated an already shown item")
	var almost_all := ids.duplicate()
	almost_all.resize(19)
	_expect(PartCatalog.roll_offers(almost_all, 99).size() == 1, "Owned parts were not excluded")
	_expect(float(PartCatalog.get_part("turbo_dynamo")["description"].find("35%")) >= 0, "Turbo Dynamo must extend duration by 35%")
	_expect(float(PartCatalog.get_part("slipstream_coil")["description"].find("25%")) >= 0, "Slipstream Coil must advertise 25% near-miss charge")
	_expect(float(PartCatalog.get_part("impact_reserve")["description"].find("half")) >= 0, "Impact Reserve must advertise half-charge retention")
	_expect(float(PartCatalog.get_part("faraday_coil")["description"].find("70%")) >= 0, "Faraday Coil must advertise a 70% EMP disable cut")
	await _validate_transactions()
	if failures.is_empty():
		print("PARTS SHOP VALIDATION PASSED: catalog, unseen offers, economy transactions, five-slot cap, persistence, pricing, and abilities.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _validate_transactions() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	_expect(packed != null, "Main scene could not be loaded")
	if packed == null:
		return
	var race = packed.instantiate()
	root.add_child(race)
	await process_frame
	_expect(race.total_gold == 0, "Fresh save must start with zero gold")
	_expect(race.owned_part_ids.is_empty(), "Fresh save must start without parts")
	var offers_before_win: Array[String] = race.shop_offer_ids.duplicate()
	race.shop_refresh_count = 2
	race.active_level_index = 0
	race.active_level = LevelCatalog.get_level(0)
	race.distance = race.active_level.finish_distance
	# _update_game() no-ops entirely unless PLAYING - _ready() leaves the
	# fresh instance in READY (showing the level select lobby), so without
	# this the win-condition check below never actually runs.
	race.state = 1 # Race.State.PLAYING
	race._update_game(0.0)
	_expect(race.lobby_level_index == 1, "Winning level 1 did not make level 2 the lobby default")
	_expect(race.shop_offer_ids != offers_before_win, "Winning a level did not refresh the shop")
	_expect(race.shop_refresh_count == 0, "Free victory refresh did not reset refresh pricing")

	var test_part: Dictionary = PartCatalog.PARTS[0]
	var test_id := str(test_part["id"])
	var price := int(test_part["price"])
	race.total_gold = price + 20
	race.shop_offer_ids.assign([test_id])
	race._on_part_purchase_requested(test_id)
	_expect(test_id in race.owned_part_ids, "A valid affordable part was not purchased")
	_expect(race.total_gold == 20, "Purchase did not deduct the exact price")

	var refresh_before: int = race.total_gold
	race._on_shop_refresh_requested()
	_expect(race.total_gold == refresh_before - 3, "First refresh did not cost three gold")
	_expect(race.shop_refresh_count == 1, "Refresh counter did not advance")

	race._on_part_sell_requested(test_id)
	_expect(test_id not in race.owned_part_ids, "Sold part remained installed")
	_expect(race.total_gold == refresh_before - 3 + price / 2, "Sellback was not exactly half price")

	var five_ids: Array[String] = []
	for index in range(PartCatalog.MAX_OWNED):
		five_ids.append(str(PartCatalog.PARTS[index]["id"]))
	race.owned_part_ids.assign(five_ids)
	var blocked_id := str(PartCatalog.PARTS[PartCatalog.MAX_OWNED]["id"])
	race.shop_offer_ids.assign([blocked_id])
	race.total_gold = 9999
	race._on_part_purchase_requested(blocked_id)
	_expect(race.owned_part_ids.size() == PartCatalog.MAX_OWNED, "The five-part slot limit was bypassed")
	_expect(blocked_id not in race.owned_part_ids, "A sixth part was installed")

	race._save_progress()
	var save := ConfigFile.new()
	_expect(save.load("user://progress.cfg") == OK, "Progress file was not written")
	_expect(int(save.get_value("economy", "total_gold", -1)) == 9999, "Wallet did not persist")
	var saved_parts: PackedStringArray = save.get_value("garage", "owned_part_ids", PackedStringArray())
	_expect(saved_parts.size() == PartCatalog.MAX_OWNED, "Owned parts did not persist")
	race.queue_free()
	await process_frame
