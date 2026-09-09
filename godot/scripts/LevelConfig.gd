extends Resource
class_name LevelConfig

@export var level_number: int = 1
@export var city_name: String = "City"
@export var background_texture: Texture2D

@export_group("Race")
@export var base_speed_start: float = 150.0
@export var base_speed_ramp: float = 3.2
@export var base_speed_max: float = 340.0
@export var finish_distance: float = 13000.0
@export var race_time: float = 60.0

@export_group("Obstacle waves")
@export_range(1, 3) var obstacle_count_start: int = 1
@export_range(1, 3) var obstacle_count_max: int = 3
@export var obstacle_ramp_seconds: float = 40.0
@export var obstacle_interval_start: float = 1.3
@export var obstacle_interval_end: float = 0.6
@export_range(0.0, 1.0) var hazard_chance_start: float = 0.20
@export_range(0.0, 1.0) var hazard_chance_end: float = 0.32

@export_group("Pickups")
@export var coin_interval_min: float = 1.6
@export var coin_interval_max: float = 2.8
@export_range(1, 5) var coin_run_min: int = 1
@export_range(1, 5) var coin_run_max: int = 3
@export var turbo_spawn_min: float = 7.0
@export var turbo_spawn_max: float = 11.0


func difficulty_at(elapsed: float) -> float:
	return clampf(elapsed / maxf(obstacle_ramp_seconds, 0.1), 0.0, 1.0)


func obstacle_count_at(elapsed: float, roll: float) -> int:
	var desired := lerpf(float(obstacle_count_start), float(obstacle_count_max), difficulty_at(elapsed))
	var lower := int(floor(desired))
	return clampi(lower + (1 if roll < desired - lower else 0), obstacle_count_start, obstacle_count_max)


func obstacle_interval_at(elapsed: float) -> float:
	return lerpf(obstacle_interval_start, obstacle_interval_end, difficulty_at(elapsed))


func hazard_chance_at(elapsed: float) -> float:
	return lerpf(hazard_chance_start, hazard_chance_end, difficulty_at(elapsed))
