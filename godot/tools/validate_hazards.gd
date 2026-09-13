extends SceneTree

# Covers the three control-disruption hazards and the parts that counter them:
# oil patches (spinout), EMP zones (turbo lockout) and wind gusts (lane shove).
# Each case drives the real _update_game() collision path rather than calling
# the trigger helpers directly, so a hazard that stops being reachable from a
# spawned obstacle fails here instead of passing on a technicality.

var failures: Array[String] = []


func _initialize() -> void:
	# Same Godot quirk documented in validate_parts_shop.gd: referencing the
	# class directly warms up its global registration before LevelCatalog's
	# static lookups hand back LevelConfig resources.
	LevelConfig.new()
	var packed := load("res://scenes/Main.tscn") as PackedScene
	_expect(packed != null, "Main scene could not be loaded")
	if packed == null:
		_finish()
		return
	var race = packed.instantiate()
	root.add_child(race)
	await process_frame

	var dt := 1.0 / 60.0
	_validate_oil(race, dt)
	_validate_emp(race, dt)
	_validate_wind(race, dt)

	race.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("HAZARD VALIDATION PASSED: oil spinout, EMP turbo lockout, wind gusts, and their counter parts.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _slick(lane: int) -> Dictionary:
	return {"lane": lane, "p": 0.97, "resolved": false, "dodged": false, "was_near": false, "kind": "slick", "variant": 0}


func _emp(lane: int) -> Dictionary:
	return {"lane": lane, "p": 0.97, "resolved": false, "dodged": false, "was_near": false, "kind": "emp", "variant": 0}


func _place(race, lane: int) -> void:
	race.player_lane = lane
	race.player_lane_visual = float(lane)
	race.obstacles.clear()


# Crossing oil costs control, not coins: the car spins, steering is locked out
# for the duration, and speed collapses to a dead stop before handing back.
func _validate_oil(race, dt: float) -> void:
	race._start_level(0)
	_place(race, 2)
	race.obstacles.append(_slick(2))
	race._update_game(dt)
	_expect(race.slide_t > 0.0, "Crossing an oil patch did not start a spinout")
	# Clear the real-time debounce first, so a blocked swerve proves the
	# spinout lock rather than the ordinary lane-change cooldown.
	race.lane_change_lock_until = 0
	race.try_swerve(1)
	_expect(race.player_lane == 2, "A spinout did not lock steering out")

	race.slide_t = race.SLICK_SLIDE_DURATION * 0.5
	_expect(race._oil_spinout_speed_multiplier() == 0.0, "Mid-spinout the car should be fully stalled")
	var stalled_speed: float = race.current_speed()
	race.slide_t = 0.0
	_expect(race.current_speed() > stalled_speed, "The spinout stall never reaches current_speed()")
	race.slide_t = race.SLICK_SLIDE_DURATION * 0.1
	_expect(race._oil_spinout_speed_multiplier() > 0.5, "Speed did not recover as the spinout ended")
	race.slide_t = 0.0

	race._start_level(0)
	_place(race, 2)
	race.owned_part_ids.assign(["grip_tires"])
	race.obstacles.append(_slick(2))
	race._update_game(dt)
	_expect(race.slide_t == 0.0, "Grip Tires did not prevent the spinout")
	race.lane_change_lock_until = 0
	race.try_swerve(1)
	_expect(race.player_lane == 3, "Grip Tires did not leave steering available across oil")
	race.owned_part_ids.clear()


# EMP is the one hazard that must be able to catch a turbo run, so unlike every
# other hazard it applies straight through invincibility.
func _validate_emp(race, dt: float) -> void:
	race._start_level(0)
	_place(race, 2)
	race.turbo_gauge = 80.0
	race.is_turbo = true
	race.invincible = true
	race.obstacles.append(_emp(2))
	race._update_game(dt)
	_expect(not race.is_turbo, "An EMP zone did not deactivate active turbo")
	_expect(race.turbo_gauge == 0.0, "An EMP zone did not zero the turbo gauge")
	_expect(race.emp_t > 0.0, "An EMP zone did not start its disable window")

	# The near-miss reward path must not refill the gauge while EMP is active.
	race.obstacles.clear()
	race.obstacles.append({"lane": 1, "p": 1.08, "resolved": false, "dodged": true, "was_near": false, "kind": "hazard", "variant": 0})
	var gauge_before: float = race.turbo_gauge
	race._update_game(dt)
	_expect(race.turbo_gauge == gauge_before, "Near misses charged turbo during an EMP lockout")

	race._start_level(0)
	_place(race, 2)
	race.owned_part_ids.assign(["faraday_coil"])
	race.obstacles.append(_emp(2))
	race._update_game(dt)
	_expect(race.emp_t < race.EMP_DURATION * 0.5, "Faraday Coil did not meaningfully cut the EMP window")
	race.owned_part_ids.clear()


# A gust telegraphs, then shoves one lane toward the push unless the player
# swerves into it first - or the Stabilizer cancels the shove outright.
func _validate_wind(race, dt: float) -> void:
	# New York (index 5) isn't unlocked_by_default, and _start_level() silently
	# no-ops past the player's unlock progress - without this, every call
	# below would leave the race on whatever level a prior test left active.
	race.highest_unlocked_level = 5
	race._start_level(5) # New York, wind_enabled
	_place(race, 2)
	race.wind_active = true
	race.wind_direction = 1.0
	race.wind_gust_t = 0.001
	race.wind_countered = false
	race._update_game(dt)
	_expect(race.player_lane == 3, "An uncountered gust did not shove the player toward the push")
	_expect(not race.wind_active, "The gust did not end once resolved")

	race._start_level(5)
	_place(race, 2)
	race.wind_active = true
	race.wind_direction = 1.0
	race.wind_countered = false
	race.wind_gust_t = 1.0
	race.lane_change_lock_until = 0
	race.try_swerve(-1) # opposite the rightward push
	_expect(race.wind_countered, "Swerving into the push did not counter the gust")
	race.wind_gust_t = 0.001
	race._update_game(dt)
	_expect(race.player_lane == 1, "A countered gust still applied its forced shove")

	race._start_level(5)
	_place(race, 2)
	race.owned_part_ids.assign(["stabilizer"])
	race.wind_active = true
	race.wind_direction = 1.0
	race.wind_gust_t = 0.001
	race.wind_countered = false
	race._update_game(dt)
	_expect(race.player_lane == 2, "Stabilizer did not prevent the forced shove")
	race.owned_part_ids.clear()
