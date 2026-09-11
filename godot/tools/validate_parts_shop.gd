extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_expect(PartCatalog.PARTS.size() == 8, "Expected eight parts")
	var ids: Array[String] = []
	for part in PartCatalog.PARTS:
		_expect(not ids.has(part["id"]), "Duplicate part ID: %s" % part["id"])
		ids.append(part["id"])
		_expect(int(part["price"]) > 0, "%s has invalid price" % part["name"])
		_expect(PartCatalog.icon(part) != null, "%s has no icon" % part["name"])
	var offers := PartCatalog.roll_offers([], 12345)
	_expect(offers.size() == 3, "A refresh must produce three offers")
	_expect(offers[0] != offers[1] and offers[1] != offers[2] and offers[0] != offers[2], "Refresh produced duplicates")
	_expect(PartCatalog.refresh_cost(0) == 3 and PartCatalog.refresh_cost(3) == 9, "Refresh pricing is incorrect")
	var almost_all := ids.duplicate()
	almost_all.resize(7)
	_expect(PartCatalog.roll_offers(almost_all, 99).size() == 1, "Owned parts were not excluded")
	_expect(float(PartCatalog.get_part("turbo_dynamo")["description"].find("35%")) >= 0, "Turbo Dynamo must extend duration by 35%")
	await _validate_transactions()
	if failures.is_empty():
		print("PARTS SHOP VALIDATION PASSED: catalog, economy transactions, five-slot cap, persistence, pricing, and Turbo Dynamo.")
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
