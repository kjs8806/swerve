extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	var race = packed.instantiate()
	root.add_child(race)
	await process_frame

	_expect(race.total_gold == 0, "Fresh wallet must start at zero")
	_expect(race.owned_car_ids == [CarCatalog.DEFAULT_CAR_ID], "Fresh save must own only Default")
	_expect(race.selected_car_id == CarCatalog.DEFAULT_CAR_ID, "Fresh save must select Default")

	race._on_purchase_requested("apex")
	_expect(race.total_gold == 0, "Unaffordable purchase changed the wallet")
	_expect("apex" not in race.owned_car_ids, "Unaffordable purchase unlocked a car")

	race.total_gold = 100
	race._on_purchase_requested("apex")
	_expect(race.total_gold == 20, "Apex purchase did not deduct exactly 80 gold")
	_expect("apex" in race.owned_car_ids, "Purchased car was not added to ownership")
	_expect(race.selected_car_id == "apex", "Purchased car was not selected")

	race.race_gold = 7
	race.race_gold_banked = false
	race._bank_race_gold()
	race._bank_race_gold()
	_expect(race.total_gold == 27, "Race gold must be banked exactly once")
	race.queue_free()
	await process_frame

	var reloaded = packed.instantiate()
	root.add_child(reloaded)
	await process_frame
	_expect(reloaded.total_gold == 27, "Wallet did not persist after reload")
	_expect("apex" in reloaded.owned_car_ids, "Ownership did not persist after reload")
	_expect(reloaded.selected_car_id == "apex", "Selection did not persist after reload")
	reloaded.queue_free()
	await process_frame

	if failures.is_empty():
		print("CAR SHOP VALIDATION PASSED: fresh save, affordability, ownership, selection, and race banking.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
