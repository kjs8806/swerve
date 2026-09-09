extends Control

signal level_selected(level_index: int)
signal car_selected(car_id: String)
signal purchase_requested(car_id: String)

const LOCKED_TINT := Color(0.28, 0.32, 0.4, 0.82)
const SELECTED_TINT := Color(0.35, 0.95, 1.0)
const VEHICLE_FRAME_COUNT := 5

@onready var grid: GridContainer = $Backdrop/Panel/Layout/LevelGrid
@onready var progress_label: Label = $Backdrop/Panel/Layout/ProgressLabel
@onready var gold_label: Label = $Backdrop/Panel/Layout/GoldLabel
@onready var car_bar: HBoxContainer = $Backdrop/Panel/Layout/CarBar
@onready var shop_overlay: Control = $ShopOverlay
@onready var shop_balance: Label = $ShopOverlay/Shade/ShopPanel/Layout/Balance
@onready var shop_items: VBoxContainer = $ShopOverlay/Shade/ShopPanel/Layout/ShopItems
@onready var shop_status: Label = $ShopOverlay/Shade/ShopPanel/Layout/Status

var wallet_gold: int = 0
var owned_ids: Array[String] = []
var selected_id: String = CarCatalog.DEFAULT_CAR_ID


func _ready() -> void:
	$Backdrop/Panel/Layout/ShopButton.pressed.connect(_open_shop)
	$ShopOverlay/Shade/ShopPanel/Layout/CloseButton.pressed.connect(_close_shop)


func configure(highest_unlocked: int, total_gold: int, owned_car_ids: Array[String], selected_car_id: String) -> void:
	wallet_gold = total_gold
	owned_ids = owned_car_ids.duplicate()
	selected_id = selected_car_id
	_rebuild_levels(highest_unlocked)
	_rebuild_car_bar()
	_rebuild_shop()
	gold_label.text = "GOLD  •  %d" % wallet_gold


func _rebuild_levels(highest_unlocked: int) -> void:
	_clear_children(grid)
	var unlocked_count := 0
	for index in range(LevelCatalog.LEVELS.size()):
		var config := LevelCatalog.get_level(index)
		if config.unlocked_by_default or index <= highest_unlocked:
			unlocked_count += 1
	progress_label.text = "%d / %d LEVELS UNLOCKED" % [unlocked_count, LevelCatalog.LEVELS.size()]
	for index in range(LevelCatalog.LEVELS.size()):
		var config := LevelCatalog.get_level(index)
		var unlocked := config.unlocked_by_default or index <= highest_unlocked
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(138.0, 86.0)
		card.add_theme_constant_override("separation", 2)
		var preview := TextureButton.new()
		preview.custom_minimum_size = Vector2(138.0, 60.0)
		preview.texture_normal = config.background_texture
		preview.ignore_texture_size = true
		preview.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		preview.disabled = not unlocked
		preview.modulate = Color.WHITE if unlocked else LOCKED_TINT
		preview.tooltip_text = config.city_name if unlocked else "Complete Level %d to unlock" % index
		preview.pressed.connect(func(): level_selected.emit(index))
		card.add_child(preview)
		var label := Label.new()
		label.text = ("BONUS  •  %s" % config.city_name.to_upper() if config.unlocked_by_default and not config.advances_progression else ("LEVEL %02d  •  %s" % [config.level_number, config.city_name] if unlocked else "LEVEL %02d  •  LOCKED" % config.level_number))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0) if unlocked else Color(0.5, 0.55, 0.63))
		card.add_child(label)
		grid.add_child(card)


func _rebuild_car_bar() -> void:
	_clear_children(car_bar)
	for car in CarCatalog.CARS:
		var button := Button.new()
		var owned := car.id in owned_ids
		button.custom_minimum_size = Vector2(145.0, 62.0)
		button.icon = _car_preview(car)
		button.expand_icon = true
		button.text = ("  %s  ✓" % car.display_name) if car.id == selected_id else "  %s" % car.display_name
		button.disabled = not owned
		button.modulate = SELECTED_TINT if car.id == selected_id else (Color.WHITE if owned else LOCKED_TINT)
		button.tooltip_text = "Selected" if car.id == selected_id else ("Select %s" % car.display_name if owned else "Buy in Shop")
		button.pressed.connect(func(): car_selected.emit(car.id))
		car_bar.add_child(button)


func _rebuild_shop() -> void:
	_clear_children(shop_items)
	shop_balance.text = "AVAILABLE GOLD  •  %d" % wallet_gold
	for car in CarCatalog.CARS:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 64.0
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(96.0, 54.0)
		icon.texture = _car_preview(car)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var name_label := Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = "%s\nStandard handling" % car.display_name
		name_label.add_theme_font_size_override("font_size", 18)
		row.add_child(name_label)
		var buy := Button.new()
		var owned := car.id in owned_ids
		buy.custom_minimum_size = Vector2(150.0, 48.0)
		buy.text = "OWNED" if owned else "%d GOLD" % car.cost
		buy.disabled = owned
		buy.pressed.connect(func(): purchase_requested.emit(car.id))
		row.add_child(buy)
		shop_items.add_child(row)


func show_purchase_result(message: String, success: bool) -> void:
	shop_status.text = message
	shop_status.add_theme_color_override("font_color", Color(0.35, 1.0, 0.62) if success else Color(1.0, 0.45, 0.4))


func _open_shop() -> void:
	shop_status.text = ""
	shop_overlay.visible = true


func _close_shop() -> void:
	shop_overlay.visible = false


func _car_preview(car: CarDef) -> AtlasTexture:
	var preview := AtlasTexture.new()
	preview.atlas = car.angle_sheet
	var frame_width: float = car.angle_sheet.get_width() / float(VEHICLE_FRAME_COUNT)
	preview.region = Rect2(frame_width * 2.0, 0.0, frame_width, car.angle_sheet.get_height())
	return preview


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
