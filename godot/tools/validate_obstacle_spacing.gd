extends SceneTree

const ROAD_LENGTH := 260.0
const REMOVE_AT := 1.18
const ATTEMPTS_PER_LEVEL := 500


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var race = load("res://scenes/Main.tscn").instantiate()
	root.add_child(race)
	await process_frame
	var total_spawned := 0
	for level_index in range(LevelCatalog.LEVELS.size()):
		race.active_level = LevelCatalog.get_level(level_index)
		race.obstacles.clear()
		race.time = 0.0
		var spawned_for_level := 0
		for attempt in range(ATTEMPTS_PER_LEVEL):
			var dt: float = maxf(0.48, race.active_level.obstacle_interval_at(race.time) * 0.85)
			var speed: float = minf(race.active_level.base_speed_max, race.active_level.base_speed_start + race.active_level.base_speed_ramp * race.time)
			var dp := speed / ROAD_LENGTH * dt
			for obstacle in race.obstacles:
				obstacle["p"] += dp
			race.obstacles = race.obstacles.filter(func(obstacle): return obstacle["p"] < REMOVE_AT)
			var before: int = race.obstacles.size()
			race._spawn_obstacle_wave()
			spawned_for_level += race.obstacles.size() - before
			race.time += dt
			_validate_visible_objects(race)

		assert(spawned_for_level > ATTEMPTS_PER_LEVEL / 4, "Separation rules suppress too many obstacles")
		total_spawned += spawned_for_level
		print("Level %02d: %d separated objects spawned" % [level_index + 1, spawned_for_level])
	print("OVERLAP VALIDATION PASSED: %d objects, zero overlaps." % total_spawned)
	quit(0)


func _validate_visible_objects(race: Node) -> void:
	var occupied_lanes := {}
	for obstacle in race.obstacles:
		assert(not occupied_lanes.has(obstacle["lane"]), "Two visible objects share a lane")
		occupied_lanes[obstacle["lane"]] = true
	assert(occupied_lanes.size() <= 4, "No lane left free")
	for i in range(race.obstacles.size()):
		for j in range(i + 1, race.obstacles.size()):
			var a: Rect2 = race._obstacle_bounds_at(race.obstacles[i], race.obstacles[i]["p"]).grow(5.0)
			var b: Rect2 = race._obstacle_bounds_at(race.obstacles[j], race.obstacles[j]["p"]).grow(5.0)
			assert(not a.intersects(b), "Visible obstacle bounds overlap")
