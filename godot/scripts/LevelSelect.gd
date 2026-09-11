extends Control

signal level_selected(level_index: int)
signal part_purchase_requested(part_id: String)
signal part_sell_requested(part_id: String)
signal shop_refresh_requested

const LOCKED_TINT := Color(0.20, 0.23, 0.31, 0.86)
const RARITY_COLORS := {"STANDARD": Color("35d8ff"), "TUNED": Color("a968ff"), "PROTOTYPE": Color("ffcf42")}

@onready var backdrop: TextureRect = $Backdrop
@onready var city_name: Label = $Shade/Margin/Layout/Main/CityPanel/CityName
@onready var level_meta: Label = $Shade/Margin/Layout/Main/CityPanel/LevelMeta
@onready var city_preview: TextureRect = $Shade/Margin/Layout/Main/CityPanel/CityPreview
@onready var conditions: Label = $Shade/Margin/Layout/Main/CityPanel/Conditions
@onready var gold_label: Label = $Shade/Margin/Layout/TopBar/Gold
@onready var car_preview: TextureRect = $Shade/Margin/Layout/Main/GaragePanel/CarPreview
@onready var loadout: HBoxContainer = $Shade/Margin/Layout/Main/GaragePanel/Loadout
@onready var loadout_description: Label = $Shade/Margin/Layout/Main/GaragePanel/LoadoutDescription
@onready var shop_overlay: Control = $ShopOverlay
@onready var offers: HBoxContainer = $ShopOverlay/Shade/Panel/Layout/Offers
@onready var shop_gold: Label = $ShopOverlay/Shade/Panel/Layout/Header/Gold
@onready var capacity: Label = $ShopOverlay/Shade/Panel/Layout/Header/Capacity
@onready var shop_active_parts: HBoxContainer = $ShopOverlay/Shade/Panel/Layout/ActiveParts
@onready var shop_part_description: Label = $ShopOverlay/Shade/Panel/Layout/ActivePartDescription
@onready var refresh_button: Button = $ShopOverlay/Shade/Panel/Layout/Actions/Refresh
@onready var sell_button: Button = $ShopOverlay/Shade/Panel/Layout/Actions/Sell
@onready var status: Label = $ShopOverlay/Shade/Panel/Layout/Status

var highest_unlocked := 0
var wallet_gold := 0
var owned_parts: Array[String] = []
var shop_offers: Array[String] = []
var refresh_count := 0
var selected_level := 0
var selected_part := ""
var pending_sell_id := ""


func _ready() -> void:
	$Shade/Margin/Layout/Main/CityPanel/Carousel/Previous.pressed.connect(func(): _change_level(-1))
	$Shade/Margin/Layout/Main/CityPanel/Carousel/Next.pressed.connect(func(): _change_level(1))
	$Shade/Margin/Layout/Main/GaragePanel/Actions/Shop.pressed.connect(_open_shop)
	$Shade/Margin/Layout/Main/GaragePanel/Actions/Start.pressed.connect(_start_selected_level)
	$ShopOverlay/Shade/Panel/Layout/Actions/Refresh.pressed.connect(func(): shop_refresh_requested.emit())
	$ShopOverlay/Shade/Panel/Layout/Actions/Sell.pressed.connect(_request_sell)
	$ShopOverlay/Shade/Panel/Layout/Actions/Close.pressed.connect(func(): shop_overlay.visible = false)


func configure(unlocked: int, gold: int, part_ids: Array[String] = [], offer_ids: Array[String] = [], shop_refresh_count: int = 0) -> void:
	highest_unlocked = unlocked
	wallet_gold = gold
	owned_parts = part_ids.duplicate()
	shop_offers = offer_ids.duplicate()
	refresh_count = shop_refresh_count
	gold_label.text = "◆  %d GOLD" % wallet_gold
	_rebuild_lobby()
	_rebuild_shop()


func _rebuild_lobby() -> void:
	var config := LevelCatalog.get_level(selected_level)
	var unlocked := config.unlocked_by_default or selected_level <= highest_unlocked
	backdrop.texture = config.background_texture
	city_preview.texture = config.background_texture
	city_preview.modulate = Color.WHITE if unlocked else LOCKED_TINT
	city_name.text = config.city_name.to_upper() if unlocked else "LOCKED"
	level_meta.text = ("BONUS EVENT" if not config.advances_progression else "LEVEL %02d / %02d" % [config.level_number, LevelCatalog.MAIN_LEVEL_COUNT])
	conditions.text = _condition_text(config.city_name) if unlocked else "Complete the previous level to unlock"
	$Shade/Margin/Layout/Main/GaragePanel/Actions/Start.disabled = not unlocked
	_rebuild_loadout()


func _rebuild_loadout() -> void:
	_clear(loadout)
	for slot in range(PartCatalog.MAX_OWNED):
		var panel := Button.new()
		panel.custom_minimum_size = Vector2(72, 64)
		if slot < owned_parts.size():
			var part := PartCatalog.get_part(owned_parts[slot])
			panel.icon = PartCatalog.icon(part)
			panel.expand_icon = true
			panel.tooltip_text = "%s — %s" % [part["name"], part["description"]]
			panel.pressed.connect(func(): _show_active_part(part["id"], false))
		else:
			panel.text = "+"
			panel.disabled = true
		loadout.add_child(panel)
	$Shade/Margin/Layout/Main/GaragePanel/LoadoutTitle.text = "ACTIVE PARTS  •  %d/%d" % [owned_parts.size(), PartCatalog.MAX_OWNED]
	if owned_parts.is_empty():
		loadout_description.text = "Purchase parts to add abilities to your car."


func _rebuild_shop() -> void:
	_clear(offers)
	shop_gold.text = "◆  %d GOLD" % wallet_gold
	capacity.text = "PARTS  %d/%d" % [owned_parts.size(), PartCatalog.MAX_OWNED]
	refresh_button.text = "REFRESH  •  %d GOLD" % PartCatalog.refresh_cost(refresh_count)
	refresh_button.disabled = wallet_gold < PartCatalog.refresh_cost(refresh_count)
	for part_id in shop_offers:
		var part := PartCatalog.get_part(part_id)
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(215, 250)
		var rarity := Label.new()
		rarity.text = part["rarity"]
		rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rarity.add_theme_color_override("font_color", RARITY_COLORS[part["rarity"]])
		card.add_child(rarity)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(180, 126)
		icon.texture = PartCatalog.icon(part)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.add_child(icon)
		var title := Label.new()
		title.text = part["name"].to_upper()
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 20)
		card.add_child(title)
		var description := Label.new()
		description.text = part["description"]
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_child(description)
		var buy := Button.new()
		buy.text = "BUY  •  %d GOLD" % part["price"]
		buy.disabled = wallet_gold < int(part["price"]) or owned_parts.size() >= PartCatalog.MAX_OWNED
		buy.pressed.connect(func(): part_purchase_requested.emit(part_id))
		card.add_child(buy)
		offers.add_child(card)
	if shop_offers.is_empty():
		var empty := Label.new()
		empty.text = "ALL AVAILABLE PARTS OWNED"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		offers.add_child(empty)
	_rebuild_active_parts()


func _rebuild_active_parts() -> void:
	_clear(shop_active_parts)
	if selected_part not in owned_parts:
		selected_part = ""
		_cancel_sell_confirmation()
		shop_part_description.text = "Select an active part to view its ability and sell value."
	for slot in range(PartCatalog.MAX_OWNED):
		var button := Button.new()
		button.custom_minimum_size = Vector2(72, 64)
		if slot < owned_parts.size():
			var part_id := owned_parts[slot]
			var part := PartCatalog.get_part(part_id)
			button.icon = PartCatalog.icon(part)
			button.expand_icon = true
			button.tooltip_text = "%s — %s" % [part["name"], part["description"]]
			button.modulate = Color("47e7ff") if part_id == selected_part else Color.WHITE
			button.pressed.connect(func(): _show_active_part(part_id, true))
		else:
			button.text = "+"
			button.disabled = true
		shop_active_parts.add_child(button)
	if owned_parts.is_empty():
		shop_part_description.text = "Purchased parts appear here."
	sell_button.disabled = owned_parts.is_empty()


func _request_sell() -> void:
	if selected_part in owned_parts:
		var part_id := selected_part
		if pending_sell_id != part_id:
			pending_sell_id = part_id
			sell_button.text = "CONFIRM SALE"
			show_shop_result("Press confirm to sell this part for half price.", false)
			return
		pending_sell_id = ""
		sell_button.text = "SELL SELECTED"
		part_sell_requested.emit(part_id)


func _cancel_sell_confirmation() -> void:
	pending_sell_id = ""
	sell_button.text = "SELL SELECTED"


func _show_active_part(part_id: String, in_shop: bool) -> void:
	var part := PartCatalog.get_part(part_id)
	if part.is_empty():
		return
	var details := "%s — %s" % [part["name"], part["description"]]
	if in_shop:
		selected_part = part_id
		_cancel_sell_confirmation()
		shop_part_description.text = "%s  •  SELL VALUE %d GOLD" % [details, int(part["price"]) / 2]
		_rebuild_active_parts()
	else:
		loadout_description.text = details


func show_shop_result(message: String, success: bool) -> void:
	status.text = message
	status.add_theme_color_override("font_color", Color("55f59b") if success else Color("ff6767"))


func keep_shop_open() -> void:
	shop_overlay.visible = true


func _open_shop() -> void:
	status.text = ""
	shop_overlay.visible = true


func _start_selected_level() -> void:
	level_selected.emit(selected_level)


func _change_level(direction: int) -> void:
	selected_level = posmod(selected_level + direction, LevelCatalog.LEVELS.size())
	_rebuild_lobby()


func focus_level(level_index: int) -> void:
	selected_level = clampi(level_index, 0, LevelCatalog.LEVELS.size() - 1)
	_rebuild_lobby()


func _condition_text(name: String) -> String:
	match name:
		"London": return "STEADY RAIN  •  TECHNICAL"
		"Hong Kong": return "NEON RAIN  •  EXPERT"
		"Tokyo": return "HEAVY NIGHT RAIN  •  ELITE"
		"Impossible": return "COSMIC HAZE  •  EXTREME"
		_: return "CLEAR ROAD  •  %s" % ("CHALLENGING" if selected_level > 5 else "OPEN")


func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
