extends Control

signal level_selected(level_index: int)

const LOCKED_TINT := Color(0.28, 0.32, 0.4, 0.82)

@onready var grid: GridContainer = $Backdrop/Panel/Layout/LevelGrid
@onready var progress_label: Label = $Backdrop/Panel/Layout/ProgressLabel
@onready var gold_label: Label = $Backdrop/Panel/Layout/GoldLabel


func configure(highest_unlocked: int, total_gold: int) -> void:
	for child in grid.get_children():
		child.queue_free()
	var unlocked_count := 0
	for index in range(LevelCatalog.LEVELS.size()):
		var config := LevelCatalog.get_level(index)
		if config.unlocked_by_default or index <= highest_unlocked:
			unlocked_count += 1
	progress_label.text = "%d / %d LEVELS UNLOCKED" % [unlocked_count, LevelCatalog.LEVELS.size()]
	gold_label.text = "GOLD  •  %d" % total_gold

	for index in range(LevelCatalog.LEVELS.size()):
		var config := LevelCatalog.get_level(index)
		var unlocked := config.unlocked_by_default or index <= highest_unlocked
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(150.0, 120.0)
		card.add_theme_constant_override("separation", 4)

		var preview := TextureButton.new()
		preview.custom_minimum_size = Vector2(150.0, 78.0)
		preview.texture_normal = config.background_texture
		preview.ignore_texture_size = true
		preview.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		preview.disabled = not unlocked
		preview.modulate = Color.WHITE if unlocked else LOCKED_TINT
		preview.tooltip_text = config.city_name if unlocked else "Complete Level %d to unlock" % index
		preview.pressed.connect(func(): level_selected.emit(index))
		card.add_child(preview)

		var label := Label.new()
		if config.unlocked_by_default and not config.advances_progression:
			label.text = "BONUS  •  %s" % config.city_name.to_upper()
		else:
			label.text = "LEVEL %02d  •  %s" % [config.level_number, config.city_name] if unlocked else "LEVEL %02d  •  LOCKED" % config.level_number
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0) if unlocked else Color(0.5, 0.55, 0.63))
		card.add_child(label)
		grid.add_child(card)
