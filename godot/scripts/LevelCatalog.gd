extends RefCounted
class_name LevelCatalog

const LEVELS: Array[LevelConfig] = [
	preload("res://levels/level_01_sydney.tres"),
	preload("res://levels/level_02_rio.tres"),
	preload("res://levels/level_03_paris.tres"),
	preload("res://levels/level_04_london.tres"),
	preload("res://levels/level_05_singapore.tres"),
	preload("res://levels/level_06_new_york.tres"),
	preload("res://levels/level_07_dubai.tres"),
	preload("res://levels/level_08_mumbai.tres"),
	preload("res://levels/level_09_hong_kong.tres"),
	preload("res://levels/level_10_tokyo.tres"),
]


static func get_level(index: int) -> LevelConfig:
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]
