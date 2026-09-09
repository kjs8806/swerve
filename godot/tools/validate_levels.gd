extends SceneTree

const LANE_COUNT := 5
const ROAD_LENGTH := 260.0
const MIN_SAFE_WAVE_INTERVAL := 0.48
const RESPONSE_TIME_FOR_TWO_CHANGES := 2.0 * (0.14 + 0.09)
const WAVES_PER_LEVEL := 10000

var failures: Array[String] = []


func _initialize() -> void:
	if LevelCatalog.MAIN_LEVEL_COUNT != 10 or LevelCatalog.LEVELS.size() != 11:
		_fail("Expected 10 campaign levels plus 1 bonus level, found %d total" % LevelCatalog.LEVELS.size())

	var previous_start_speed := -INF
	var previous_ramp_window := INF
	for level_index in range(LevelCatalog.LEVELS.size()):
		var config := LevelCatalog.get_level(level_index)
		_validate_config(config, level_index, previous_start_speed, previous_ramp_window)
		_simulate_waves(config, level_index)
		previous_start_speed = config.base_speed_start
		previous_ramp_window = config.obstacle_ramp_seconds

	if failures.is_empty():
		print("LEVEL VALIDATION PASSED: 11 configs, %d simulated waves, no trapped lane states." % (WAVES_PER_LEVEL * LevelCatalog.LEVELS.size()))
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _validate_config(config: LevelConfig, index: int, previous_speed: float, previous_window: float) -> void:
	var prefix := "Level %d (%s)" % [index + 1, config.city_name]
	if config.level_number != index + 1:
		_fail("%s has level_number %d" % [prefix, config.level_number])
	if config.background_texture == null:
		_fail("%s has no background texture" % prefix)
	elif config.background_texture.get_width() < 1600 or config.background_texture.get_height() < 900:
		_fail("%s background is below 1600x900" % prefix)
	if config.base_speed_start <= previous_speed:
		_fail("%s start speed does not rise from the previous level" % prefix)
	if config.obstacle_ramp_seconds >= previous_window:
		_fail("%s difficulty window does not tighten from the previous level" % prefix)
	if config.obstacle_count_start < 1 or config.obstacle_count_max > LANE_COUNT - 1:
		_fail("%s obstacle count is outside the safe range" % prefix)
	if config.obstacle_count_start > config.obstacle_count_max:
		_fail("%s obstacle count range is reversed" % prefix)
	if config.obstacle_interval_end < MIN_SAFE_WAVE_INTERVAL:
		_fail("%s minimum wave interval is below %.2fs" % [prefix, MIN_SAFE_WAVE_INTERVAL])
	if MIN_SAFE_WAVE_INTERVAL < RESPONSE_TIME_FOR_TWO_CHANGES:
		_fail("Global wave interval cannot accommodate two lane-change inputs")
	if config.coin_interval_min > config.coin_interval_max or config.turbo_spawn_min > config.turbo_spawn_max:
		_fail("%s has a reversed pickup interval" % prefix)
	if index < LevelCatalog.MAIN_LEVEL_COUNT:
		if config.unlocked_by_default or not config.advances_progression:
			_fail("%s must remain part of sequential campaign progression" % prefix)
	else:
		if not config.unlocked_by_default or config.advances_progression:
			_fail("%s must be an always-unlocked, non-progression bonus" % prefix)

	var no_hit_distance := _distance_possible(config)
	if no_hit_distance < config.finish_distance:
		_fail("%s cannot be finished without boosts (%.0f < %.0f)" % [prefix, no_hit_distance, config.finish_distance])
	print("%02d %-10s finish margin %5.1f%% | waves %.2f→%.2fs | obstacles %d→%d" % [
		config.level_number,
		config.city_name,
		(no_hit_distance / config.finish_distance - 1.0) * 100.0,
		config.obstacle_interval_start,
		config.obstacle_interval_end,
		config.obstacle_count_start,
		config.obstacle_count_max,
	])


func _distance_possible(config: LevelConfig) -> float:
	var elapsed := 0.0
	var distance := 0.0
	const STEP := 0.01
	while elapsed < config.race_time:
		var dt := minf(STEP, config.race_time - elapsed)
		distance += minf(config.base_speed_max, config.base_speed_start + config.base_speed_ramp * elapsed) * dt
		elapsed += dt
	return distance


func _simulate_waves(config: LevelConfig, level_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9173 + level_index * 104729
	var occupied_until: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var elapsed := 0.0
	for wave_index in range(WAVES_PER_LEVEL):
		var interval := maxf(MIN_SAFE_WAVE_INTERVAL, config.obstacle_interval_at(elapsed))
		interval = maxf(MIN_SAFE_WAVE_INTERVAL, interval * rng.randf_range(0.85, 1.15))
		if interval < RESPONSE_TIME_FOR_TWO_CHANGES:
			_fail("Level %d wave %d is too tightly spaced" % [level_index + 1, wave_index])
		elapsed += interval

		var available: Array[int] = []
		for lane in range(LANE_COUNT):
			if occupied_until[lane] <= elapsed:
				available.append(lane)
		var requested := config.obstacle_count_at(elapsed, rng.randf())
		var spawn_count := mini(requested, maxi(0, available.size() - 1))
		available.shuffle()
		var speed := minf(config.base_speed_max, config.base_speed_start + config.base_speed_ramp * elapsed)
		var lifetime := ROAD_LENGTH / speed
		for i in range(spawn_count):
			occupied_until[available[i]] = elapsed + lifetime

		var blocked := 0
		for lane in range(LANE_COUNT):
			if occupied_until[lane] > elapsed:
				blocked += 1
		if blocked >= LANE_COUNT:
			_fail("Level %d wave %d trapped all lanes" % [level_index + 1, wave_index])
			return


func _fail(message: String) -> void:
	failures.append(message)
