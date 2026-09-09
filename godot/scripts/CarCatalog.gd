extends RefCounted
class_name CarCatalog

const DEFAULT_CAR_ID := "default"
const CARS: Array[CarDef] = [
	preload("res://cars/default.tres"),
	preload("res://cars/comet.tres"),
	preload("res://cars/apex.tres"),
]


static func get_car(car_id: String) -> CarDef:
	for car in CARS:
		if car.id == car_id:
			return car
	return CARS[0]


static func has_car(car_id: String) -> bool:
	for car in CARS:
		if car.id == car_id:
			return true
	return false
