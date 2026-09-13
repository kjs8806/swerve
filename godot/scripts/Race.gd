extends Node2D

# Port of web/game.js - see DESIGN.md for the design rationale and
# tuned balance constants. Logic mirrors the JS version closely so the
# already-validated feel and numbers carry over; only the rendering
# approach changes (Godot's immediate-mode _draw() instead of Canvas2D).

# ---------- Config ----------
const ComboCalloutConfig := preload("res://scripts/ComboCalloutConfig.gd")
const LEVEL_SELECT_SCENE := preload("res://scenes/LevelSelect.tscn")

const LANES := 5
# Five equal lanes: each occupies exactly 20% of the road width at every depth.
const LANE_EDGES: Array[float] = [-1.0, -0.60, -0.20, 0.20, 0.60, 1.0]
const ROAD_LENGTH := 260.0

const COLLISION_PENALTY_MULT := 0.22
const COLLISION_RECOVER_TIME := 1.7
const BOOST_MULT := 1.28
const TURBO_MULT := 1.9
const TURBO_GAUGE_MAX := 100.0
const TURBO_DURATION := 4.2
const TURBO_DRAIN_PER_SEC := TURBO_GAUGE_MAX / TURBO_DURATION
const NEAR_MISS_TURBO_GAIN := 20.0
const ENHANCED_NEAR_MISS_TURBO_GAIN := 25.0
const NITRO_CAPACITOR_SECONDS := 0.25
const QUICKSHIFT_REQUIRED_CHANGES := 5
const QUICKSHIFT_BOOST_TIME := 0.9

# Near-miss timing is intentionally independent from vehicle artwork scale.
# Starting slightly earlier keeps the maneuver readable with the larger HD cars.
const NEAR_MISS_ZONE_START := 0.78
const COLLIDE_AT := 0.97
const PASS_AT := 1.08
const REMOVE_AT := 1.6
const FINISH_REVEAL_RANGE := ROAD_LENGTH * 2.5
# Thickness of the painted finish-line checkers, expressed in the same
# depth units as `p` (rather than fixed screen pixels) so the stripe is
# drawn as a perspective-correct trapezoid that always matches the road's
# own width at both its near and far edge instead of overhanging it.
const FINISH_STRIPE_P_THICKNESS := 0.10

const LANE_CHANGE_TIME := 0.14
# 140ms animation + 90ms input lock, plus a 250ms readability buffer.
const MIN_SAFE_WAVE_INTERVAL := LANE_CHANGE_TIME + 0.09 + 0.25
const OBSTACLE_OVERLAP_SAMPLE_STEP := 0.025
const OBSTACLE_OVERLAP_MARGIN := 5.0

# Impact/turbo feedback - kept brief, low-alpha, and/or geometrically
# confined (see _draw_turbo_ring/_draw_turbo_flash/_draw_speed_lines) so
# they read clearly without ever covering a lane or disabling input.
const SHAKE_DURATION := 0.22
const SHAKE_MAGNITUDE := 9.0
const TURBO_FLASH_DURATION := 0.42
const TURBO_RING_DURATION := 0.72

# Turbo's backdrop is the HD streak sheet itself, scaled up from small to
# large while anchored at the road's far end (the top of the screen, since
# horizon_y() is 0) - a plain zoom of the reference image straight toward the
# camera, not a road-mapped projection. Half the sheet lands above the screen
# and is clipped away for free, which is what gives the streaming-downward
# look without any manual UV cropping. Three staggered copies of one squared
# depth ramp keep a pass always mid-rush, so the loop never visibly restarts.
const SPEED_LINE_ALPHA := 0.85
const SPEED_LINE_LAYERS := 3
const SPEED_LINE_CYCLE := 0.5
const SPEED_LINE_START_SCALE := 0.18
const SPEED_LINE_END_SCALE := 3.2

# Coin pickup feedback: a quick punch on the HUD counter plus a brief
# in-world sparkle (see spark_fx below) at the exact pickup point.
const COIN_PUNCH_DURATION := 0.18
const COIN_PUNCH_SCALE := 1.35
const COIN_PICKUP_FX_DURATION := 0.3
const COIN_SPARK_COLOR := Color(1.0, 0.85, 0.3)
const COIN_LOSS_FX_DURATION := 0.75
const HAZARD_COIN_LOSS := 1
const TRAFFIC_COIN_LOSS := 3
const TURBO_IMPACT_FX_DURATION := 0.72
const TURBO_IMPACT_SPARK_COLOR := Color(1.0, 0.58, 0.12)

# Near-miss feedback: same expanding-spark mechanic as a coin pickup (see
# spark_fx below), positioned at the dodged obstacle, plus a light screen
# tint - far more restrained than hit_flash since this rewards the player
# rather than punishing them.
const NEAR_MISS_FX_DURATION := 0.3
const NEAR_MISS_SPARK_COLOR := Color(0.208, 0.878, 0.631)
const NEAR_MISS_FLASH_DURATION := 0.18

# Render the entire combo badge (Nx label + COMBO artwork) at 80% of its
# original size. Animation values below preserve the same relative punch.
const COMBO_BADGE_SCALE := 0.80
const COMBO_BADGE_INTRO_SCALE := COMBO_BADGE_SCALE * 0.72
const COMBO_BADGE_PEAK_SCALE := COMBO_BADGE_SCALE * 1.12

const HD_VEHICLE_SCALE := 0.45
const VEHICLE_ANGLE_FRAME_COUNT := 5
const TEX_PLAYER_ANGLE_SHEET := preload("res://assets/vehicles/player-gray-angle-sheet.png")
# Every traffic paint variant uses the same approved subtle five-angle geometry.
# Spawning already chooses uniformly from this array, so all variants can appear.
const TRAFFIC_ANGLE_SHEETS := [
	preload("res://assets/vehicles/traffic-blue-angle-sheet.png"),
	preload("res://assets/vehicles/traffic-red-angle-sheet.png"),
	preload("res://assets/vehicles/traffic-green-angle-sheet.png"),
	preload("res://assets/vehicles/traffic-orange-angle-sheet.png"),
	preload("res://assets/vehicles/traffic-yellow-angle-sheet.png"),
]
const TEX_COIN := preload("res://assets/collectibles/coin.png")
# coin.png is a large-source HD circle (not sized 1:1 for the road), so its
# draw size is derived from this instead of the raw texture pixel size - a
# bit larger than the old sprite's on-screen footprint.
const COIN_DRAW_SCALE := 0.19
const TURBO_SEGMENT_COUNT := 17
const TEX_TURBO_SEGMENT_RED := preload("res://assets/hud/turbo-segment-red.png")
const TEX_TURBO_SEGMENT_ORANGE := preload("res://assets/hud/turbo-segment-orange.png")
const TEX_TURBO_SEGMENT_YELLOW := preload("res://assets/hud/turbo-segment-yellow.png")

# Approved turbo-effect sprites.
const TEX_TURBO_EXHAUST := preload("res://assets/effects/turbo-exhaust-flames.png")
const TEX_TURBO_RING := preload("res://assets/effects/turbo-energy-ring.png")
const TEX_TURBO_FLASH := preload("res://assets/effects/turbo-activation-flash.png")
const TEX_TURBO_SPEED_LINES := preload("res://assets/effects/turbo-speed-lines.png")
# Per-variant sizing keeps the flatter/narrower hazards as readable as the tyre.
# Order matches HAZARD_TEXTURES: pothole, loose tyre, traffic cone.
const HAZARD_DRAW_SCALES: Array[float] = [0.29, 0.25, 0.30]
# A restrained lane-dependent yaw sells the perspective without making
# outer-lane cars look as tilted as the converging divider lines.
const MAX_LANE_VISUAL_ROTATION := 0.105
const HAZARD_TEXTURES := [
	preload("res://assets/obstacles/pothole-hd.png"),
	preload("res://assets/obstacles/loose-tire-hd.png"),
	preload("res://assets/obstacles/traffic-cone-hd.png"),
]
const TEX_MENU_ICON := preload("res://assets/hud/menu-button.svg")
const FOG_MAX_COVERAGE := 0.66
const FOG_FEATHER := 0.10
const FOG_MAX_ALPHA := 0.98

# Oil slick patches are their own obstacle kind, not a HAZARD_TEXTURES
# variant. Crossing one locks steering for two seconds and produces a
# visual fishtail, but never causes a coin-loss collision.
const SLICK_SLIDE_DURATION := 2.0
# The source is 991px wide. At this scale its visible width tracks the
# perspective lane width closely from the horizon through the collision row.
const SLICK_DRAW_SCALE := 0.14
const TEX_OIL_SLICK := preload("res://assets/obstacles/oil-slick-hd.png")

# EMP zones knock the turbo gauge fully offline (deactivating turbo if it was
# running, zeroing the gauge, and blocking all charging) for their duration -
# a harsher, more targeted disruption than a normal hazard's speed penalty.
const EMP_DURATION := 3.5
const EMP_DRAW_SCALE := 0.16
const TEX_EMP_ZONE := preload("res://assets/obstacles/emp-zone-hd.png")

# Wind gusts are a periodic sideways push rather than a lane-based obstacle:
# swerving away from the push direction at any point during a gust counters
# it; otherwise it shoves the player one lane over when it ends. The visual
# sway is purely cosmetic feedback for how close the gust is to landing.
const WIND_GUST_DURATION := 1.8
const WIND_SWAY_MAX := 0.55

enum State { READY, PLAYING, PAUSED, WIN, LOSE }

# ---------- State ----------
var state: int = State.READY
var time: float = 0.0
var distance: float = 0.0
var race_gold: int = 0
var combo: int = 0
var best_combo: int = 0
var player_lane: int = int((LANES - 1) / 2)
var player_lane_visual: float = float(player_lane)
var lane_anim_t: float = 1.0
var lane_anim_from: float = float(player_lane)
var turbo_gauge: float = 0.0
var is_turbo: bool = false
var invincible: bool = false
var penalty_t: float = 0.0
var boost_t: float = 0.0
var hit_flash: float = 0.0
var win_flash: float = 0.0
var shake_t: float = 0.0
var turbo_ring_t: float = 0.0
var turbo_flash_t: float = 0.0
var turbo_visual: float = 0.0
var coin_punch_t: float = 0.0
var coin_loss_punch_t: float = 0.0
var near_miss_flash: float = 0.0
var spark_fx: Array = [] # {pos, scale, t, duration, color} - coin pickups + near-misses
var coin_loss_fx: Array = [] # {pos, scale, index, t, duration} - coins scattered by an impact
var road_scroll: float = 0.0
var obstacles: Array = []
var coins_list: Array = []
var obstacle_timer: float = 0.0
var coin_timer: float = 0.0
var phantom_differential_used := false
var clean_lane_changes := 0
var collected_coin_count := 0
var slide_t: float = 0.0
var emp_t: float = 0.0
var wind_timer: float = 0.0
var wind_active: bool = false
var wind_direction: float = 1.0
var wind_gust_t: float = 0.0
var wind_countered: bool = false

var elapsed_t: float = 0.0
var lane_change_lock_until: int = 0
var combo_popup_timer: float = 0.0
var combo_badge_tween: Tween
var combo_popup_tween: Tween
var vignette_tex: GradientTexture2D
var cloud_seeds: Array = []
var rock_seeds: Array = []
var audio_controller
var active_level_index: int = 0
var active_level: LevelConfig = LevelCatalog.get_level(0)
var background_texture: Texture2D
var highest_unlocked_level: int = 0
var total_gold: int = 0
var sound_enabled: bool = true
var lobby_level_index: int = 0
var race_gold_banked: bool = false
var owned_part_ids: Array[String] = []
var shop_offer_ids: Array[String] = []
var shop_seen_offer_ids: Array[String] = []
var shop_refresh_count: int = 0
var shop_seed: int = 73421
var level_select: Control

# ---------- HUD refs ----------
@onready var timer_label: Label = $HUD/Root/TimerPanel/TimerLabel
@onready var coin_label: Label = $HUD/Root/CoinPanel/CoinLabel
@onready var combo_panel: Control = $HUD/Root/ComboPanel
@onready var combo_art: TextureRect = $HUD/Root/ComboPanel/ComboArt
@onready var combo_label: Label = $HUD/Root/ComboPanel/ComboLabel
@onready var progress_track: Control = $HUD/Root/ProgressTrack
@onready var player_marker: TextureRect = $HUD/Root/ProgressTrack/PlayerMarker
@onready var turbo_gauge_track: Control = $HUD/Root/TurboGaugeTrack
@onready var turbo_segments: Control = $HUD/Root/TurboGaugeTrack/TurboSegments
@onready var turbo_banner: Label = get_node_or_null("HUD/Root/TurboBanner") as Label
@onready var combo_popup: Label = $HUD/Root/ComboPopup
@onready var btn_left: TextureButton = $HUD/Root/BtnLeft
@onready var btn_right: TextureButton = $HUD/Root/BtnRight
@onready var pause_button: TextureButton = $HUD/Root/PauseButton
@onready var overlay: Control = $HUD/Root/Overlay
@onready var overlay_title: Label = $HUD/Root/Overlay/OverlayCard/OverlayTitle
@onready var overlay_subtitle: Label = $HUD/Root/Overlay/OverlayCard/OverlaySubtitle
@onready var overlay_button: Button = $HUD/Root/Overlay/OverlayCard/OverlayButton
@onready var overlay_stats: Label = $HUD/Root/Overlay/OverlayCard/OverlayStats
@onready var menu_actions: VBoxContainer = $HUD/Root/Overlay/OverlayCard/MenuActions
@onready var resume_button: Button = $HUD/Root/Overlay/OverlayCard/MenuActions/ResumeButton
@onready var restart_button: Button = $HUD/Root/Overlay/OverlayCard/MenuActions/RestartButton
@onready var sound_button: Button = $HUD/Root/Overlay/OverlayCard/MenuActions/SoundButton
@onready var exit_level_button: Button = $HUD/Root/Overlay/OverlayCard/MenuActions/ExitLevelButton


func _ready() -> void:
	randomize()
	_load_progress()
	_apply_sound_setting()
	background_texture = active_level.background_texture
	# Audio must never prevent the race scene from starting. Load the optional
	# controller at runtime so an unavailable decoder/resource degrades to a
	# silent game instead of making Race.gd fail during its preload phase.
	var controller_script := load("res://scripts/AudioController.gd")
	if controller_script is Script and controller_script.can_instantiate():
		audio_controller = controller_script.new()
		audio_controller.name = "AudioController"
		add_child(audio_controller)
	_build_vignette_texture()
	_build_scenery_seeds()
	_build_turbo_segments()
	btn_left.pressed.connect(func(): try_swerve(-1))
	btn_right.pressed.connect(func(): try_swerve(1))
	overlay_button.pressed.connect(_on_overlay_button_pressed)
	pause_button.pressed.connect(_toggle_pause)
	resume_button.pressed.connect(_resume_game)
	restart_button.pressed.connect(func(): reset_game(true))
	sound_button.pressed.connect(_toggle_sound)
	exit_level_button.pressed.connect(_show_level_select)
	_update_sound_button()
	set_process_unhandled_key_input(true)
	_show_level_select()


func _load_progress() -> void:
	var save := ConfigFile.new()
	if save.load("user://progress.cfg") == OK:
		highest_unlocked_level = clampi(int(save.get_value("progress", "highest_unlocked", 0)), 0, LevelCatalog.MAIN_LEVEL_COUNT - 1)
		total_gold = maxi(0, int(save.get_value("economy", "total_gold", 0)))
		owned_part_ids = _valid_part_ids(save.get_value("garage", "owned_part_ids", PackedStringArray()))
		shop_offer_ids = _valid_part_ids(save.get_value("shop", "offer_ids", PackedStringArray()))
		shop_seen_offer_ids = _valid_catalog_ids(save.get_value("shop", "seen_offer_ids", PackedStringArray()))
		shop_refresh_count = maxi(0, int(save.get_value("shop", "refresh_count", 0)))
		shop_seed = int(save.get_value("shop", "seed", 73421))
		sound_enabled = bool(save.get_value("settings", "sound_enabled", true))
	if shop_seen_offer_ids.is_empty() and not shop_offer_ids.is_empty():
		shop_seen_offer_ids.assign(shop_offer_ids)
	lobby_level_index = highest_unlocked_level
	if shop_offer_ids.is_empty():
		_roll_shop()


func _save_progress() -> void:
	var save := ConfigFile.new()
	save.load("user://progress.cfg")
	save.set_value("progress", "highest_unlocked", highest_unlocked_level)
	save.set_value("economy", "total_gold", total_gold)
	save.set_value("garage", "owned_part_ids", PackedStringArray(owned_part_ids))
	save.set_value("shop", "offer_ids", PackedStringArray(shop_offer_ids))
	save.set_value("shop", "seen_offer_ids", PackedStringArray(shop_seen_offer_ids))
	save.set_value("shop", "refresh_count", shop_refresh_count)
	save.set_value("shop", "seed", shop_seed)
	save.set_value("settings", "sound_enabled", sound_enabled)
	save.save("user://progress.cfg")


func _apply_sound_setting() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, not sound_enabled)


func _update_sound_button() -> void:
	if sound_button != null:
		sound_button.text = "SOUND: ON" if sound_enabled else "SOUND: OFF"


func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	_apply_sound_setting()
	_update_sound_button()
	_save_progress()


func _valid_part_ids(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array or value is PackedStringArray:
		for raw_id in value:
			var part_id := str(raw_id)
			if PartCatalog.has_part(part_id) and part_id not in result and result.size() < PartCatalog.MAX_OWNED:
				result.append(part_id)
	return result


func _valid_catalog_ids(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array or value is PackedStringArray:
		for raw_id in value:
			var part_id := str(raw_id)
			if PartCatalog.has_part(part_id) and part_id not in result:
				result.append(part_id)
	return result


func _roll_shop() -> void:
	shop_offer_ids = PartCatalog.roll_offers(owned_part_ids, shop_seed, total_gold, shop_seen_offer_ids)
	if shop_offer_ids.is_empty():
		# Start a new rotation only after every currently unowned item has appeared.
		shop_seen_offer_ids.clear()
		shop_offer_ids = PartCatalog.roll_offers(owned_part_ids, shop_seed, total_gold)
	for part_id in shop_offer_ids:
		if part_id not in shop_seen_offer_ids:
			shop_seen_offer_ids.append(part_id)
	shop_seed += 7919


func _configure_level_select() -> void:
	level_select.configure(highest_unlocked_level, total_gold, owned_part_ids, shop_offer_ids, shop_refresh_count)


func _show_level_select() -> void:
	state = State.READY
	_audio_call(&"stop_background_music_immediately")
	_save_progress()
	overlay.visible = false
	menu_actions.visible = false
	pause_button.visible = false
	if level_select == null:
		level_select = LEVEL_SELECT_SCENE.instantiate()
		$HUD.add_child(level_select)
		level_select.level_selected.connect(_start_level)
		level_select.part_purchase_requested.connect(_on_part_purchase_requested)
		level_select.part_sell_requested.connect(_on_part_sell_requested)
		level_select.shop_refresh_requested.connect(_on_shop_refresh_requested)
	_configure_level_select()
	level_select.focus_level(lobby_level_index)
	level_select.visible = true


func _on_part_purchase_requested(part_id: String) -> void:
	var part := PartCatalog.get_part(part_id)
	if part.is_empty() or part_id not in shop_offer_ids or part_id in owned_part_ids:
		level_select.show_shop_result("That offer is no longer available.", false)
		return
	if owned_part_ids.size() >= PartCatalog.MAX_OWNED:
		level_select.show_shop_result("All five part slots are full.", false)
		return
	if total_gold < int(part["price"]):
		level_select.show_shop_result("Not enough gold.", false)
		return
	total_gold -= int(part["price"])
	owned_part_ids.append(part_id)
	shop_offer_ids.erase(part_id)
	_save_progress()
	_configure_level_select()
	level_select.keep_shop_open()
	level_select.show_shop_result("%s installed." % part["name"], true)


func _on_part_sell_requested(part_id: String) -> void:
	if part_id not in owned_part_ids:
		return
	var part := PartCatalog.get_part(part_id)
	total_gold += int(part["price"]) / 2
	owned_part_ids.erase(part_id)
	_save_progress()
	_configure_level_select()
	level_select.keep_shop_open()
	level_select.show_shop_result("%s sold for %d gold." % [part["name"], int(part["price"]) / 2], true)


func _on_shop_refresh_requested() -> void:
	var cost := PartCatalog.refresh_cost(shop_refresh_count, _has_part("savings_coil"))
	if total_gold < cost:
		level_select.show_shop_result("Not enough gold to refresh.", false)
		return
	total_gold -= cost
	shop_refresh_count += 1
	_roll_shop()
	_save_progress()
	_configure_level_select()
	level_select.keep_shop_open()
	level_select.show_shop_result("Fresh parts just arrived.", true)


func _start_level(level_index: int) -> void:
	if level_index < 0 or level_index >= LevelCatalog.LEVELS.size():
		return
	var selected_level := LevelCatalog.get_level(level_index)
	if not selected_level.unlocked_by_default and level_index > highest_unlocked_level:
		return
	active_level_index = level_index
	lobby_level_index = level_index
	active_level = selected_level
	background_texture = active_level.background_texture
	level_select.visible = false
	reset_game(true)


func _on_overlay_button_pressed() -> void:
	if state == State.WIN:
		_show_level_select()
	else:
		reset_game(true)


func _audio_call(method: StringName, args: Array = []) -> void:
	if audio_controller != null and audio_controller.has_method(method):
		audio_controller.callv(method, args)


func _build_turbo_segments() -> void:
	for child in turbo_segments.get_children():
		child.queue_free()
	# Pixel-matched to the approved 840x100 gauge artwork at its 420x50
	# runtime size. The base contains the frame, label, and 17 dark slots;
	# these colored overlays are revealed as the live gauge fills.
	const SEGMENT_X: Array[float] = [
		105.16, 120.68, 135.99, 151.40, 166.60, 181.91,
		197.32, 212.73, 228.56, 244.39, 260.33, 276.47,
		292.40, 308.23, 324.27, 340.31, 356.56,
	]
	for i in range(TURBO_SEGMENT_COUNT):
		var segment := TextureRect.new()
		if i < 3:
			segment.texture = TEX_TURBO_SEGMENT_RED
		elif i < 8:
			segment.texture = TEX_TURBO_SEGMENT_ORANGE
		else:
			segment.texture = TEX_TURBO_SEGMENT_YELLOW
		segment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		segment.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		segment.position = Vector2(SEGMENT_X[i], 14.0)
		segment.size = Vector2(25.0, 25.0)
		segment.visible = false
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		turbo_segments.add_child(segment)


func _build_scenery_seeds() -> void:
	for i in range(5):
		cloud_seeds.append({
			"x": randf(), "y": 0.15 + randf() * 0.55, "scale": 0.6 + randf() * 0.8,
		})
	for i in range(6):
		rock_seeds.append({
			"side": -1 if i % 2 == 0 else 1,
			"x": 0.55 + randf() * 0.4, "scale": 0.5 + randf() * 0.9,
		})


func _build_vignette_texture() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.47, 0.0, 0.0))
	grad.set_color(1, Color(1.0, 0.35, 0.0, 1.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.6)
	tex.fill_to = Vector2(1.0, 0.6)
	tex.width = 256
	tex.height = 256
	vignette_tex = tex


# ---------- Perspective helpers (mirror the JS lane/road math exactly) ----------
func get_w() -> float:
	return get_viewport_rect().size.x

func get_h() -> float:
	return get_viewport_rect().size.y

func horizon_y() -> float:
	# Extend the road and its perspective geometry to the top edge.
	return 0.0

func player_row_y() -> float:
	return get_h() * 0.80

func center_x() -> float:
	return get_w() * 0.5

func ease_p(p: float) -> float:
	return pow(clampf(p, 0.0, 2.0), 1.35)

func half_width_at(p: float) -> float:
	var top_half := get_w() * 0.16
	var bot_half := get_w() * 0.50
	return lerp(top_half, bot_half, ease_p(p))

func _lane_center_fraction(lane_index: int) -> float:
	var safe_lane: int = clampi(lane_index, 0, LANES - 1)
	return (LANE_EDGES[safe_lane] + LANE_EDGES[safe_lane + 1]) * 0.5


func lane_fraction(lane_index: float) -> float:
	# Derive every center from the same boundaries that draw the lane. This
	# keeps vehicles centered at every depth even if lane widths change later.
	var lo: int = clampi(int(floor(lane_index)), 0, LANES - 1)
	var hi: int = clampi(int(ceil(lane_index)), 0, LANES - 1)
	var blend: float = lane_index - floor(lane_index)
	return lerpf(_lane_center_fraction(lo), _lane_center_fraction(hi), blend)

func road_half_width_at_y(screen_y: float) -> float:
	# The visible road edges are linear between the horizon and screen bottom.
	# Deriving width from screen Y keeps road objects on the same center axes.
	var hy: float = horizon_y()
	var road_height: float = maxf(1.0, get_h() - hy)
	var screen_depth: float = (screen_y - hy) / road_height
	return lerpf(half_width_at(0.0), half_width_at(1.0), screen_depth)


func lane_x(lane_index: float, p: float) -> float:
	var screen_y: float = row_y(p)
	return center_x() + lane_fraction(lane_index) * road_half_width_at_y(screen_y)


func row_y(p: float) -> float:
	return lerp(horizon_y(), player_row_y(), ease_p(p))

func scale_at(p: float) -> float:
	return lerp(0.28, 1.0, ease_p(p))


# ---------- Game state ----------
func reset_game(play_ui_tap: bool = false) -> void:
	state = State.PLAYING
	time = 0.0
	distance = 0.0
	race_gold = 0
	race_gold_banked = false
	shop_refresh_count = 0
	_save_progress()
	combo = 0
	best_combo = 0
	player_lane = int((LANES - 1) / 2)
	player_lane_visual = float(player_lane)
	lane_anim_from = float(player_lane)
	lane_anim_t = 1.0
	turbo_gauge = 0.0
	is_turbo = false
	invincible = false
	penalty_t = 0.0
	boost_t = 0.0
	hit_flash = 0.0
	win_flash = 0.0
	shake_t = 0.0
	turbo_ring_t = 0.0
	turbo_flash_t = 0.0
	turbo_visual = 0.0
	coin_punch_t = 0.0
	coin_loss_punch_t = 0.0
	near_miss_flash = 0.0
	spark_fx.clear()
	coin_loss_fx.clear()
	position = Vector2.ZERO
	road_scroll = 0.0
	obstacles.clear()
	coins_list.clear()
	obstacle_timer = 0.6
	coin_timer = 0.9
	phantom_differential_used = false
	clean_lane_changes = 0
	collected_coin_count = 0
	slide_t = 0.0
	emp_t = 0.0
	wind_active = false
	wind_gust_t = 0.0
	wind_countered = false
	wind_timer = randf_range(active_level.wind_gust_interval_min, active_level.wind_gust_interval_max) if active_level.wind_enabled else 0.0
	overlay.visible = false
	menu_actions.visible = false
	overlay_button.visible = true
	pause_button.visible = true
	pause_button.texture_normal = TEX_MENU_ICON
	_audio_call(&"begin_race", [play_ui_tap])


func _toggle_pause() -> void:
	if state == State.PLAYING:
		_open_pause_menu()
	elif state == State.PAUSED:
		_resume_game()


func _open_pause_menu() -> void:
	state = State.PAUSED
	_audio_call(&"pause_race")
	overlay.visible = true
	pause_button.visible = false
	overlay_title.text = "PAUSED"
	overlay_subtitle.text = "Level %d  •  %s" % [active_level.level_number, active_level.city_name]
	overlay_stats.text = ""
	overlay_button.visible = false
	menu_actions.visible = true


func _resume_game() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	_audio_call(&"resume_race")
	overlay.visible = false
	menu_actions.visible = false
	overlay_button.visible = true
	pause_button.visible = true


func base_speed() -> float:
	var speed := minf(active_level.base_speed_max, active_level.base_speed_start + active_level.base_speed_ramp * time)
	return speed * (1.07 if _has_part("redline_engine") else 1.0)


func current_speed() -> float:
	var mult := 1.0
	if penalty_t > 0.0:
		var recover := COLLISION_RECOVER_TIME * (0.6 if _has_part("rallycore_suspension") else 1.0)
		var penalty_mult := lerpf(COLLISION_PENALTY_MULT, 1.0, 0.4) if _has_part("rallycore_suspension") else COLLISION_PENALTY_MULT
		var tt: float = 1.0 - penalty_t / recover
		mult *= lerp(penalty_mult, 1.0, clampf(tt, 0.0, 1.0))
	if boost_t > 0.0:
		mult *= BOOST_MULT
	if is_turbo:
		mult *= TURBO_MULT
	if slide_t > 0.0 and not _has_part("grip_tires"):
		mult *= _oil_spinout_speed_multiplier()
	return base_speed() * mult


func _oil_spinout_progress() -> float:
	return clampf(1.0 - slide_t / SLICK_SLIDE_DURATION, 0.0, 1.0)


func _oil_spinout_speed_multiplier() -> float:
	var progress: float = _oil_spinout_progress()
	if progress < 0.42:
		return 1.0 - smoothstep(0.0, 0.42, progress)
	if progress < 0.68:
		return 0.0
	return smoothstep(0.68, 1.0, progress)


func _has_part(part_id: String) -> bool:
	return part_id in owned_part_ids


func _spawn_spark(pos: Vector2, scale: float, duration: float, color: Color) -> void:
	spark_fx.append({"pos": pos, "scale": scale, "t": duration, "duration": duration, "color": color})


func _lose_coins(requested_amount: int, impact_pos: Vector2, impact_scale: float) -> int:
	var lost := mini(requested_amount, total_gold + race_gold)
	if lost <= 0:
		popup_combo("NO COINS", Color(1.0, 0.42, 0.22))
		return 0
	var lost_from_race := mini(race_gold, lost)
	race_gold -= lost_from_race
	var lost_from_total := lost - lost_from_race
	if lost_from_total > 0:
		total_gold = maxi(0, total_gold - lost_from_total)
		_save_progress()
	coin_loss_punch_t = COIN_PUNCH_DURATION
	for i in range(lost):
		coin_loss_fx.append({"pos": impact_pos, "scale": impact_scale, "index": i, "t": COIN_LOSS_FX_DURATION, "duration": COIN_LOSS_FX_DURATION})
	var coin_word := "COIN" if lost == 1 else "COINS"
	popup_combo("-%d %s" % [lost, coin_word], Color(1.0, 0.42, 0.22))
	return lost


func _launch_obstacle(obstacle: Dictionary) -> void:
	var lane: float = float(obstacle["lane"])
	var direction := -1.0 if lane < float(LANES - 1) * 0.5 else 1.0
	if is_equal_approx(lane, float(LANES - 1) * 0.5):
		direction = -1.0 if randi() % 2 == 0 else 1.0
	obstacle["resolved"] = true
	obstacle["turbo_launched"] = true
	obstacle["launch_t"] = TURBO_IMPACT_FX_DURATION
	obstacle["launch_duration"] = TURBO_IMPACT_FX_DURATION
	obstacle["launch_direction"] = direction
	obstacle["launch_spin"] = direction * randf_range(5.5, 7.5)
	var impact_pos := Vector2(lane_x(lane, obstacle["p"]), row_y(obstacle["p"]))
	_spawn_spark(impact_pos, scale_at(obstacle["p"]) * 1.8, TURBO_IMPACT_FX_DURATION * 0.55, TURBO_IMPACT_SPARK_COLOR)
	turbo_flash_t = maxf(turbo_flash_t, TURBO_FLASH_DURATION * 0.45)
	shake_t = maxf(shake_t, SHAKE_DURATION * 0.45)
	popup_combo("TURBO HIT!", TURBO_IMPACT_SPARK_COLOR)
	_audio_call(&"collision", [obstacle["kind"] == "hazard"])


# A pure control debuff, not damage - no coin loss, no speed penalty, no
# combo reset. Grip Tires makes it a complete non-event (still worth calling
# out positively so the part visibly earns its keep).
func _trigger_slick_slide(impact_pos: Vector2, impact_scale: float) -> void:
	_spawn_spark(impact_pos, impact_scale * 1.4, 0.42, Color(1.0, 0.58, 0.16))
	if _has_part("grip_tires"):
		popup_combo("GRIP!", Color(0.4, 1.0, 0.6))
		near_miss_flash = NEAR_MISS_FLASH_DURATION
		return
	slide_t = SLICK_SLIDE_DURATION
	shake_t = maxf(shake_t, SHAKE_DURATION * 0.35)
	popup_combo("TRACTION LOST", Color(1.0, 0.58, 0.16))
	_audio_call(&"collision", [true])


# Knocks turbo fully offline - deactivates it if running, drains the gauge,
# and blocks all charging for the duration - rather than a speed/coin hit.
# Faraday Coil cuts the disable window down instead of negating it outright.
func _trigger_emp(impact_pos: Vector2, impact_scale: float) -> void:
	_spawn_spark(impact_pos, impact_scale * 1.65, 0.48, Color(0.18, 0.82, 1.0))
	_deactivate_turbo()
	turbo_gauge = 0.0
	emp_t = EMP_DURATION * (0.3 if _has_part("faraday_coil") else 1.0)
	turbo_flash_t = maxf(turbo_flash_t, TURBO_FLASH_DURATION * 0.65)
	shake_t = maxf(shake_t, SHAKE_DURATION * 0.5)
	popup_combo("SYSTEM JAMMED", Color(0.18, 0.82, 1.0))
	_audio_call(&"collision", [true])


func popup_combo(text: String, color: Color) -> void:
	if combo_popup_tween != null and combo_popup_tween.is_valid():
		combo_popup_tween.kill()
	combo_popup.text = text
	combo_popup.add_theme_color_override("font_color", color)
	combo_popup.visible = true
	combo_popup.pivot_offset = combo_popup.size * 0.5
	combo_popup.scale = Vector2.ONE * 0.55
	combo_popup.rotation = deg_to_rad(-5.0)
	combo_popup.modulate = Color(1, 1, 1, 0.0)
	combo_popup_timer = 0.65

	combo_popup_tween = create_tween()
	combo_popup_tween.set_parallel(true)
	combo_popup_tween.tween_property(combo_popup, "scale", Vector2.ONE * 1.1, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	combo_popup_tween.tween_property(combo_popup, "rotation", 0.0, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	combo_popup_tween.tween_property(combo_popup, "modulate:a", 1.0, 0.10)
	combo_popup_tween.chain().set_parallel(false)
	combo_popup_tween.tween_property(combo_popup, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_QUAD)
	combo_popup_tween.tween_interval(0.25)
	combo_popup_tween.tween_property(combo_popup, "modulate:a", 0.0, 0.14)


func _play_combo_badge_fx() -> void:
	if combo_badge_tween != null and combo_badge_tween.is_valid():
		combo_badge_tween.kill()
	combo_panel.pivot_offset = combo_panel.size * Vector2(0.82, 0.5)
	combo_panel.scale = Vector2.ONE * COMBO_BADGE_INTRO_SCALE
	combo_panel.rotation = -0.045
	combo_panel.modulate = Color(1.0, 0.82, 0.42, 0.25)
	combo_art.position.x = 24.0
	combo_art.modulate = Color(1.35, 1.12, 0.72, 1.0)
	combo_badge_tween = create_tween().set_parallel(true)
	combo_badge_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	combo_badge_tween.tween_property(combo_panel, "scale", Vector2.ONE * COMBO_BADGE_PEAK_SCALE, 0.14)
	combo_badge_tween.tween_property(combo_panel, "rotation", 0.0, 0.14)
	combo_badge_tween.tween_property(combo_panel, "modulate", Color.WHITE, 0.10)
	combo_badge_tween.tween_property(combo_art, "position:x", 0.0, 0.16)
	combo_badge_tween.tween_property(combo_art, "modulate", Color.WHITE, 0.22)
	combo_badge_tween.chain().set_parallel(false)
	combo_badge_tween.tween_property(combo_panel, "scale", Vector2.ONE * COMBO_BADGE_SCALE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---------- Input ----------
func try_swerve(dir: int) -> void:
	if state != State.PLAYING:
		return
	if slide_t > 0.0 and not _has_part("grip_tires"):
		return
	var now := Time.get_ticks_msec()
	if now < lane_change_lock_until:
		return
	lane_change_lock_until = now + (75 if _has_part("vector_wheel") else 90)
	if wind_active and not wind_countered and dir == -wind_direction:
		wind_countered = true
		popup_combo("HELD STEADY!", Color(0.55, 0.85, 1.0))
	var target: int = clampi(player_lane + dir, 0, LANES - 1)
	if target == player_lane:
		return
	_check_near_miss_on_leave(player_lane)
	lane_anim_from = player_lane_visual
	player_lane = target
	lane_anim_t = 0.0
	clean_lane_changes += 1
	if _has_part("quickshift_transmission") and clean_lane_changes % QUICKSHIFT_REQUIRED_CHANGES == 0:
		boost_t = maxf(boost_t, QUICKSHIFT_BOOST_TIME)
		popup_combo("QUICKSHIFT!", Color(0.2, 0.9, 1.0))
	_audio_call(&"lane_changed")


func _check_near_miss_on_leave(from_lane: int) -> void:
	for o in obstacles:
		if o["resolved"]:
			continue
		if o["lane"] == from_lane and o["p"] >= NEAR_MISS_ZONE_START and o["p"] < COLLIDE_AT:
			o["dodged"] = true


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			try_swerve(-1)
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			try_swerve(1)
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if state == State.LOSE:
				reset_game()
			elif state == State.WIN or state == State.READY:
				_show_level_select()
		elif event.keycode == KEY_ESCAPE:
			_toggle_pause()


# ---------- Spawning ----------
# Spawn intervals shrink to well under an obstacle's ~1.2-1.5s travel time
# at high difficulty, so waves overlap on the road - picking lanes only
# from THIS wave's own set (the old approach) can't see obstacles a
# previous wave left in flight, and the two together can end up covering
# every lane at once (verified by simulation: possible with the old
# per-wave-only logic). Guaranteeing a stronger, simpler invariant instead
# - at least one lane is always completely free of any visible obstacle -
# makes that structurally impossible regardless of how waves overlap.
func _spawn_obstacle_wave() -> void:
	var count := active_level.obstacle_count_at(time, randf())

	# Coin lanes are excluded too, not just other obstacles' - a coin and an
	# oncoming car sharing a lane forces the player to choose between the
	# coin and a collision, which breaks the no-damage full-coin clear a
	# perfect run should always be able to achieve.
	var occupied_lanes: Dictionary = {}
	for o in obstacles:
		# Resolved objects still render until REMOVE_AT. Keeping their lanes
		# occupied prevents a new object from appearing through them.
		occupied_lanes[o["lane"]] = true
	for c in coins_list:
		if not c["collected"]:
			occupied_lanes[c["lane"]] = true

	var free_lanes: Array = []
	for i in range(LANES):
		if not occupied_lanes.has(i):
			free_lanes.append(i)

	# Leave at least one already-free lane untouched by this wave too.
	count = mini(count, maxi(0, free_lanes.size() - 1))
	if count <= 0:
		return

	for i in range(free_lanes.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = free_lanes[i]
		free_lanes[i] = free_lanes[j]
		free_lanes[j] = tmp

	var spawned: Array = []
	for lane in free_lanes:
		if spawned.size() >= count:
			break
		var kind_and_variant := _roll_obstacle_kind()
		var candidate := {
			"lane": lane, "p": 0.0, "resolved": false,
			"dodged": false, "was_near": false,
			"kind": kind_and_variant["kind"], "variant": kind_and_variant["variant"],
		}
		if _obstacle_path_is_clear(candidate, spawned):
			spawned.append(candidate)

	obstacles.append_array(spawned)


# EMP and slick each get their own independent roll on top of the normal
# hazard/traffic split, so they read as occasional disruptions layered onto
# the base mix rather than replacing it. Order (emp, slick, hazard, traffic)
# just partitions one random roll into four bands.
func _roll_obstacle_kind() -> Dictionary:
	var roll := randf()
	var emp_p := active_level.emp_chance
	var slick_p := active_level.slick_chance
	var hazard_p := active_level.hazard_chance_at(time)
	if roll < emp_p:
		return {"kind": "emp", "variant": 0}
	roll -= emp_p
	if roll < slick_p:
		return {"kind": "slick", "variant": 0}
	roll -= slick_p
	if roll < hazard_p:
		return {"kind": "hazard", "variant": randi() % HAZARD_TEXTURES.size()}
	return {"kind": "traffic", "variant": randi() % TRAFFIC_ANGLE_SHEETS.size()}


func _obstacle_path_is_clear(candidate: Dictionary, same_wave: Array) -> bool:
	for existing in obstacles:
		if _obstacle_paths_overlap(candidate, existing):
			return false
	for existing in same_wave:
		if _obstacle_paths_overlap(candidate, existing):
			return false
	return true


func _obstacle_paths_overlap(candidate: Dictionary, existing: Dictionary) -> bool:
	var candidate_p := 0.0
	var existing_start_p: float = existing["p"]
	while candidate_p < REMOVE_AT and existing_start_p + candidate_p < REMOVE_AT:
		var candidate_rect := _obstacle_bounds_at(candidate, candidate_p).grow(OBSTACLE_OVERLAP_MARGIN)
		var existing_rect := _obstacle_bounds_at(existing, existing_start_p + candidate_p).grow(OBSTACLE_OVERLAP_MARGIN)
		if candidate_rect.intersects(existing_rect):
			return true
		candidate_p += OBSTACLE_OVERLAP_SAMPLE_STEP
	return false


func _obstacle_bounds_at(obstacle: Dictionary, p: float) -> Rect2:
	var rendered_size: Vector2
	if obstacle["kind"] == "hazard":
		var variant: int = int(obstacle["variant"])
		rendered_size = HAZARD_TEXTURES[variant].get_size() * scale_at(p) * HAZARD_DRAW_SCALES[variant]
	elif obstacle["kind"] == "slick":
		rendered_size = TEX_OIL_SLICK.get_size() * scale_at(p) * SLICK_DRAW_SCALE
	elif obstacle["kind"] == "emp":
		rendered_size = TEX_EMP_ZONE.get_size() * scale_at(p) * EMP_DRAW_SCALE
	else:
		var sheet: Texture2D = TRAFFIC_ANGLE_SHEETS[int(obstacle["variant"])]
		rendered_size = Vector2(sheet.get_width() / float(VEHICLE_ANGLE_FRAME_COUNT), sheet.get_height()) * scale_at(p) * HD_VEHICLE_SCALE
	# A square using the longest side is conservative for angled hazards and
	# transparent sprite padding, guaranteeing visual separation after rotation.
	var extent := maxf(rendered_size.x, rendered_size.y)
	var size := Vector2(extent, extent)
	var pos := Vector2(lane_x(float(obstacle["lane"]), p), row_y(p))
	return Rect2(pos - size * 0.5, size)


func _spawn_coins() -> void:
	# Same guard as _spawn_obstacle_wave, from the coin side: never place a
	# coin in a lane an obstacle already occupies (including one still
	# resolving/rendering out until REMOVE_AT), so collecting every coin
	# never requires driving into a car.
	var occupied_lanes: Dictionary = {}
	for o in obstacles:
		occupied_lanes[o["lane"]] = true

	var free_lanes: Array = []
	for i in range(LANES):
		if not occupied_lanes.has(i):
			free_lanes.append(i)
	if free_lanes.is_empty():
		return

	var lane: int = free_lanes[randi() % free_lanes.size()]
	var run_len := randi_range(active_level.coin_run_min, active_level.coin_run_max)
	for i in range(run_len):
		coins_list.append({"lane": lane, "p": -i * 0.06, "collected": false})


func _activate_timed_turbo() -> void:
	var was_active := is_turbo
	turbo_gauge = TURBO_GAUGE_MAX
	is_turbo = true
	invincible = true
	var duration := TURBO_DURATION * (1.35 if _has_part("turbo_dynamo") else 1.0)
	popup_combo("TURBO! %.1fs" % duration, Color(1.0, 0.478, 0.102))
	_audio_call(&"turbo_charged")
	if not was_active:
		turbo_ring_t = TURBO_RING_DURATION
		turbo_flash_t = TURBO_FLASH_DURATION
		turbo_visual = maxf(turbo_visual, 0.42)
		shake_t = maxf(shake_t, SHAKE_DURATION * 0.8)
		_audio_call(&"set_turbo", [true])


func _deactivate_turbo(clear_gauge: bool = true) -> void:
	is_turbo = false
	invincible = false
	if clear_gauge:
		turbo_gauge = 0.0
	_audio_call(&"set_turbo", [false])


# ---------- Wind ----------
# A gust either gets countered (the player swerves away from the push
# direction at any point while it's active - see try_swerve) or, if it
# expires uncountered, shoves the player one lane toward the push. The
# Stabilizer part treats every gust as already countered.
func _update_wind(dt: float) -> void:
	if wind_active:
		wind_gust_t = maxf(0.0, wind_gust_t - dt)
		if wind_gust_t <= 0.0:
			_resolve_wind_gust()
		return
	wind_timer -= dt
	if wind_timer <= 0.0:
		wind_active = true
		wind_countered = false
		wind_gust_t = WIND_GUST_DURATION
		wind_direction = -1.0 if randi() % 2 == 0 else 1.0
		popup_combo("WIND GUST!", Color(0.6, 0.85, 1.0))
		_audio_call(&"wind_gust")


func _resolve_wind_gust() -> void:
	wind_active = false
	wind_timer = randf_range(active_level.wind_gust_interval_min, active_level.wind_gust_interval_max)
	if _has_part("stabilizer"):
		popup_combo("STABILIZED", Color(0.18, 0.9, 1.0))
		near_miss_flash = NEAR_MISS_FLASH_DURATION
		return
	if wind_countered:
		popup_combo("GUST DODGED", Color(0.4, 1.0, 0.72))
		near_miss_flash = NEAR_MISS_FLASH_DURATION
		return
	var target: int = clampi(player_lane + int(wind_direction), 0, LANES - 1)
	if target != player_lane:
		lane_anim_from = player_lane_visual
		player_lane = target
		lane_anim_t = 0.0
		popup_combo("GUST PUSHED YOU!", Color(1.0, 0.7, 0.3))
		_audio_call(&"lane_changed")


# Purely cosmetic - grows toward the push direction as the gust nears
# resolution, giving a visual read on how close it is to shoving the player
# over, but never touches player_lane_visual itself (collision math and the
# lane-change animation both stay untouched).
func _wind_sway() -> float:
	if _has_part("stabilizer") or not wind_active or wind_countered:
		return 0.0
	var progress: float = 1.0 - wind_gust_t / WIND_GUST_DURATION
	return wind_direction * WIND_SWAY_MAX * progress


# ---------- Update ----------
func _process(delta: float) -> void:
	elapsed_t += delta
	_update_game(delta)
	queue_redraw()
	_update_hud()


func _update_game(dt: float) -> void:
	if state != State.PLAYING:
		return

	time += dt

	if lane_anim_t < 1.0:
		var lane_time := LANE_CHANGE_TIME * (0.82 if _has_part("vector_wheel") else 1.0)
		lane_anim_t = clampf(lane_anim_t + dt / lane_time, 0.0, 1.0)
		player_lane_visual = lerp(lane_anim_from, float(player_lane), lane_anim_t)

	if penalty_t > 0.0:
		penalty_t = maxf(0.0, penalty_t - dt)
	if boost_t > 0.0:
		boost_t = maxf(0.0, boost_t - dt)
	if slide_t > 0.0:
		slide_t = maxf(0.0, slide_t - dt)
	if emp_t > 0.0:
		emp_t = maxf(0.0, emp_t - dt)

	if is_turbo:
		var drain := TURBO_DRAIN_PER_SEC / (1.35 if _has_part("turbo_dynamo") else 1.0)
		turbo_gauge = maxf(0.0, turbo_gauge - drain * dt)
		if turbo_gauge <= 0.0:
			_deactivate_turbo()

	if active_level.wind_enabled:
		_update_wind(dt)

	var speed := current_speed()
	distance += speed * dt
	var dp: float = (speed / ROAD_LENGTH) * dt
	road_scroll += speed * dt

	# Obstacles: position always advances, even once resolved (hit or
	# passed) - otherwise a resolved car freezes in place forever instead
	# of continuing off-screen and becoming eligible for removal.
	for o in obstacles:
		if o.get("turbo_launched", false):
			o["launch_t"] = maxf(0.0, float(o["launch_t"]) - dt)
			continue
		o["p"] += dp
		if o["resolved"]:
			continue

		if o["lane"] == player_lane and o["p"] >= NEAR_MISS_ZONE_START and o["p"] < COLLIDE_AT:
			o["was_near"] = true

		if o["p"] >= COLLIDE_AT and o["lane"] == player_lane:
			if o["kind"] == "slick" or o["kind"] == "emp":
				o["resolved"] = true
				# Slick patches are a non-event under turbo (matching how
				# invincible bypasses every other hazard), but EMP's entire
				# purpose is to counter turbo/invincibility, so it has to be
				# able to land regardless - otherwise the "anti-turbo"
				# hazard could never actually catch a player using turbo.
				if o["kind"] == "emp" or not invincible:
					var effect_pos := Vector2(lane_x(o["lane"], o["p"]), row_y(o["p"]))
					if o["kind"] == "slick":
						_trigger_slick_slide(effect_pos, scale_at(o["p"]))
					else:
						_trigger_emp(effect_pos, scale_at(o["p"]))
			elif invincible:
				_launch_obstacle(o)
			elif _has_part("phantom_differential") and not phantom_differential_used:
				o["resolved"] = true
				phantom_differential_used = true
				popup_combo("PHASED!", Color(0.68, 0.42, 1.0))
			else:
				o["resolved"] = true
				var impact_pos := Vector2(lane_x(o["lane"], o["p"]), row_y(o["p"]))
				var requested_coin_loss := HAZARD_COIN_LOSS if o["kind"] == "hazard" else TRAFFIC_COIN_LOSS
				_lose_coins(requested_coin_loss, impact_pos, scale_at(o["p"]))
				penalty_t = COLLISION_RECOVER_TIME * (0.6 if _has_part("rallycore_suspension") else 1.0)
				boost_t = 0.0
				combo = 0
				if _has_part("impact_reserve"):
					turbo_gauge *= 0.5
				else:
					turbo_gauge = 0.0
				clean_lane_changes = 0
				hit_flash = 0.25
				shake_t = SHAKE_DURATION
				_audio_call(&"collision", [o["kind"] == "hazard"])
		elif o["p"] >= PASS_AT:
			o["resolved"] = true
			if o["dodged"] or o["was_near"]:
				combo += 1
				best_combo = maxi(best_combo, combo)
				near_miss_flash = NEAR_MISS_FLASH_DURATION
				_spawn_spark(Vector2(lane_x(o["lane"], o["p"]), row_y(o["p"])), scale_at(o["p"]), NEAR_MISS_FX_DURATION, NEAR_MISS_SPARK_COLOR)
				var callout := ComboCalloutConfig.for_combo(combo)
				popup_combo(callout["text"], Color(1.0, 0.78, 0.05))
				_play_combo_badge_fx()
				_audio_call(&"combo_increased", [combo])
				if not is_turbo and emp_t <= 0.0:
					var charge_gain := ENHANCED_NEAR_MISS_TURBO_GAIN if _has_part("slipstream_coil") else NEAR_MISS_TURBO_GAIN
					turbo_gauge = minf(TURBO_GAUGE_MAX, turbo_gauge + charge_gain)
					if turbo_gauge >= TURBO_GAUGE_MAX:
						_activate_timed_turbo()

	obstacles = obstacles.filter(func(o): return float(o.get("launch_t", 1.0)) > 0.0 if o.get("turbo_launched", false) else o["p"] < REMOVE_AT)

	for c in coins_list:
		if c["collected"]:
			continue
		c["p"] += dp
		var turbo_vacuum_active := is_turbo and _has_part("turbo_vacuum")
		if turbo_vacuum_active and c["p"] >= 0.58:
			c["lane"] = move_toward(float(c["lane"]), float(player_lane), dt * 12.0)
		elif _has_part("flux_magnet") and absi(int(round(float(c["lane"]))) - player_lane) <= 1 and c["p"] >= 0.72:
			c["lane"] = move_toward(float(c["lane"]), float(player_lane), dt * 4.0)
		var lane_distance: int = absi(int(round(float(c["lane"]))) - player_lane)
		var magnet_collect := _has_part("flux_magnet") and lane_distance <= 1
		var turbo_vacuum_collect := turbo_vacuum_active
		var collect_at := 0.92 if turbo_vacuum_collect else COLLIDE_AT
		if (lane_distance == 0 or magnet_collect or turbo_vacuum_collect) and c["p"] >= collect_at and c["p"] < COLLIDE_AT + 0.05:
			c["collected"] = true
			collected_coin_count += 1
			var coin_value := 2 if _has_part("golden_gearbox") else 1
			if _has_part("momentum_crown") and combo >= 10:
				coin_value = maxi(coin_value, 3)
			if _has_part("golden_alternator") and collected_coin_count % 10 == 0:
				coin_value += 1
			race_gold += coin_value
			if is_turbo and _has_part("nitro_capacitor"):
				turbo_gauge = minf(TURBO_GAUGE_MAX, turbo_gauge + TURBO_DRAIN_PER_SEC * NITRO_CAPACITOR_SECONDS)
			coin_punch_t = COIN_PUNCH_DURATION
			_spawn_spark(Vector2(lane_x(c["lane"], c["p"]), row_y(c["p"])), scale_at(c["p"]), COIN_PICKUP_FX_DURATION, COIN_SPARK_COLOR)
			_audio_call(&"coin_collected")

	coins_list = coins_list.filter(func(c): return not c["collected"] and c["p"] < REMOVE_AT)

	obstacle_timer -= dt
	if obstacle_timer <= 0.0:
		# Stop feeding in new oncoming traffic once the finish line has
		# scrolled into view, so the final stretch reads as a clear run to
		# the flag instead of a last-second dodge.
		if active_level.finish_distance - distance > FINISH_REVEAL_RANGE:
			_spawn_obstacle_wave()
		var interval := maxf(MIN_SAFE_WAVE_INTERVAL, active_level.obstacle_interval_at(time))
		obstacle_timer = maxf(MIN_SAFE_WAVE_INTERVAL, interval * (0.85 + randf() * 0.3))

	coin_timer -= dt
	if coin_timer <= 0.0:
		_spawn_coins()
		coin_timer = randf_range(active_level.coin_interval_min, active_level.coin_interval_max)

	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - dt)
	if win_flash > 0.0:
		win_flash = maxf(0.0, win_flash - dt)
	if shake_t > 0.0:
		shake_t = maxf(0.0, shake_t - dt)
	turbo_visual = move_toward(turbo_visual, 1.0 if is_turbo else 0.0, dt * (5.0 if is_turbo else 3.0))
	if turbo_ring_t > 0.0:
		turbo_ring_t = maxf(0.0, turbo_ring_t - dt)
	if turbo_flash_t > 0.0:
		turbo_flash_t = maxf(0.0, turbo_flash_t - dt)
	if coin_punch_t > 0.0:
		coin_punch_t = maxf(0.0, coin_punch_t - dt)
	if coin_loss_punch_t > 0.0:
		coin_loss_punch_t = maxf(0.0, coin_loss_punch_t - dt)
	if near_miss_flash > 0.0:
		near_miss_flash = maxf(0.0, near_miss_flash - dt)
	for fx in spark_fx:
		fx["t"] -= dt
	spark_fx = spark_fx.filter(func(fx): return fx["t"] > 0.0)
	for fx in coin_loss_fx:
		fx["t"] -= dt
	coin_loss_fx = coin_loss_fx.filter(func(fx): return fx["t"] > 0.0)

	# Camera shake only ever offsets this Node2D, never the HUD (a separate
	# CanvasLayer, immune to its parent's 2D transform) - so it can never
	# desync touch-button hit testing or the gameplay math, which reads the
	# viewport size directly rather than this node's transform.
	if shake_t > 0.0:
		var shake_frac: float = shake_t / SHAKE_DURATION
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_MAGNITUDE * shake_frac
	elif position != Vector2.ZERO:
		position = Vector2.ZERO

	if combo_popup_timer > 0.0:
		combo_popup_timer -= dt
		if combo_popup_timer <= 0.0:
			combo_popup.visible = false

	if distance >= active_level.finish_distance:
		state = State.WIN
		_bank_race_gold()
		if active_level.advances_progression:
			highest_unlocked_level = maxi(highest_unlocked_level, mini(active_level_index + 1, LevelCatalog.MAIN_LEVEL_COUNT - 1))
			lobby_level_index = mini(active_level_index + 1, LevelCatalog.MAIN_LEVEL_COUNT - 1)
		shop_refresh_count = 0
		_roll_shop()
		_save_progress()
		win_flash = 0.5
		_deactivate_turbo()
		_audio_call(&"finish_race", [true])
		_show_end_screen(true)
	elif time >= active_level.race_time:
		state = State.LOSE
		_bank_race_gold()
		_deactivate_turbo()
		_audio_call(&"finish_race", [false])
		_show_end_screen(false)


func _show_end_screen(won: bool) -> void:
	overlay.visible = true
	pause_button.visible = false
	menu_actions.visible = false
	overlay_button.visible = true
	overlay_title.text = "FINISH!" if won else "TIME UP"
	overlay_subtitle.text = ("Level %d complete — %s mastered." % [active_level.level_number, active_level.city_name] if won
		else "Try %s again and watch for the open lane." % active_level.city_name)
	overlay_button.text = "LEVEL SELECT" if won else "TRY AGAIN"
	var time_used: float = minf(time, active_level.race_time)
	overlay_stats.text = "Time: %.1fs\nDistance: %d / %d\nGold: +%d  •  Total: %d\nBest Combo: x%d" % [
		time_used, int(distance), int(active_level.finish_distance), race_gold, total_gold, best_combo,
	]


func _bank_race_gold() -> void:
	if race_gold_banked:
		return
	race_gold_banked = true
	total_gold += race_gold
	_save_progress()


# ---------- HUD ----------
func _update_hud() -> void:
	var remaining: float = maxf(0.0, active_level.race_time - time)
	if state == State.PLAYING:
		_audio_call(&"update_countdown", [remaining])
	timer_label.text = "%.1f" % remaining
	timer_label.modulate = Color8(0xff, 0x4d, 0x4d) if remaining < 10.0 else Color8(0xff, 0xcc, 0x33)
	coin_label.text = "%d" % (total_gold + (0 if race_gold_banked else race_gold))
	coin_label.pivot_offset = coin_label.size * 0.5
	var coin_punch_frac: float = maxf(coin_punch_t, coin_loss_punch_t) / COIN_PUNCH_DURATION
	coin_label.scale = Vector2.ONE * (1.0 + (COIN_PUNCH_SCALE - 1.0) * coin_punch_frac)
	coin_label.modulate = Color(1.0, 0.32, 0.22) if coin_loss_punch_t > 0.0 else Color.WHITE
	combo_panel.visible = combo > 0
	combo_label.text = "%dx" % maxi(1, combo)

	var pct: float = clampf(distance / active_level.finish_distance, 0.0, 1.0)
	var track_w: float = progress_track.size.x
	# marker_start mirrors the track art's left inset (its leftmost opaque
	# pixel sits ~3px in) so the marker starts flush with the track's own
	# edge; marker_end mirrors the same inset from the right edge so the
	# marker finishes at the checkered flag instead of undershooting to the
	# last checkpoint dot (which sits at ~83% of the track's width).
	var marker_start := 3.0
	var marker_end := track_w - player_marker.size.x - marker_start
	player_marker.position.x = lerpf(marker_start, marker_end, pct)

	var gauge_pct: float = clampf(turbo_gauge / TURBO_GAUGE_MAX, 0.0, 1.0)
	var lit_count: int = clampi(ceili(gauge_pct * TURBO_SEGMENT_COUNT), 0, TURBO_SEGMENT_COUNT)
	for i in range(turbo_segments.get_child_count()):
		var segment := turbo_segments.get_child(i) as TextureRect
		segment.visible = i < lit_count
	if turbo_banner != null:
		turbo_banner.visible = is_turbo
	if is_turbo and turbo_banner != null:
		var glow: float = 0.92 + 0.08 * sin(elapsed_t * 3.0)
		turbo_banner.modulate = Color(0.45, glow, 1.0, 1.0)
	turbo_gauge_track.modulate = Color(1.0 - turbo_visual * 0.25, 1.0, 1.0)


# ---------- Rendering ----------
func _draw() -> void:
	_draw_road()
	if turbo_visual > 0.001:
		_draw_speed_lines(elapsed_t)

	# Everything on the road - coins, traffic, the finish tape, and the
	# player - is drawn in a single depth-sorted pass so a just-passed
	# obstacle (p > 1, "closer to camera" than the player) renders in
	# front of the player as it exits instead of behind it.
	var draw_items: Array = []
	for c in coins_list:
		if c["p"] < -0.1:
			continue
		draw_items.append({"p": c["p"], "cb": func(): _draw_coin_item(c)})
	for o in obstacles:
		draw_items.append({"p": o["p"], "cb": func(): _draw_obstacle(o)})

	var remaining: float = active_level.finish_distance - distance
	if remaining <= FINISH_REVEAL_RANGE and remaining > -FINISH_REVEAL_RANGE * 0.4:
		var finish_p: float = 1.0 - remaining / FINISH_REVEAL_RANGE
		draw_items.append({"p": finish_p, "cb": func(): _draw_finish_tape(finish_p)})

	var visual_lane := player_lane_visual + _wind_sway()
	var px := lane_x(visual_lane, 1.0)
	var py := player_row_y()
	var p_scale := scale_at(1.0) * 1.05
	var player_rotation: float = _lane_visual_rotation(visual_lane, 1.0)
	var sprite_rotation: float = 0.0
	if slide_t > 0.0 and not _has_part("grip_tires"):
		var spin_progress: float = smoothstep(0.0, 0.58, _oil_spinout_progress())
		sprite_rotation = TAU * 2.0 * spin_progress
	var turbo_now := is_turbo
	var t_now := elapsed_t
	draw_items.append({"p": 1.001, "cb": func():
		if turbo_now:
			_draw_flame_trail(Vector2(px, py), p_scale, t_now, player_rotation)
		_draw_angle_sprite_on_road(TEX_PLAYER_ANGLE_SHEET, _angle_frame_for_lane(visual_lane), Vector2(px, py), p_scale * HD_VEHICLE_SCALE, 1.0, 0.34, 1.0, sprite_rotation)
	})

	draw_items.sort_custom(func(a, b): return a["p"] < b["p"])
	for item in draw_items:
		item["cb"].call()
	_draw_fog()

	for fx in spark_fx:
		_draw_spark_fx(fx)
	for fx in coin_loss_fx:
		_draw_coin_loss_fx(fx)

	if turbo_ring_t > 0.0:
		_draw_turbo_ring(px, py)
	if turbo_flash_t > 0.0:
		_draw_turbo_flash(px, py)
		_draw_turbo_activation_pulse(get_viewport_rect().size, Vector2(px, py))

	var sz := get_viewport_rect().size
	if hit_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0, 0, hit_flash * 0.35))
	if near_miss_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.208, 0.878, 0.631, near_miss_flash / NEAR_MISS_FLASH_DURATION * 0.14))
	if win_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, win_flash * 0.6))
	if turbo_visual > 0.001:
		_draw_turbo_edges(sz)
	_draw_rain_overlay(sz)
	if slide_t > 0.0 and not _has_part("grip_tires"):
		_draw_slick_status_overlay(sz)
	if emp_t > 0.0:
		_draw_emp_status_overlay(sz)
	if wind_active:
		_draw_wind_overlay(sz)


func _draw_rain_overlay(size: Vector2) -> void:
	var rainy := active_level.city_name in ["London", "Hong Kong", "Tokyo"]
	if not rainy:
		return
	var heavy := active_level.city_name == "Tokyo"
	var wiped := _has_part("stormcut_wipers")
	var drop_count := 34 if wiped else (92 if heavy else 68)
	var intensity := 0.34 if wiped else (1.0 if heavy else 0.78)
	if _has_part("nightvision_visor"):
		drop_count = int(drop_count * 0.65)
		intensity *= 0.5
	var wind := size.x * 0.075
	var rain_color := Color(0.78, 0.88, 0.96)

	# Each streak gets stable pseudo-random depth and speed. Far rain is short,
	# faint and slow while foreground drops are brighter and motion-blurred.
	for i in range(drop_count):
		var fi := float(i)
		var depth := 0.18 + fmod(fi * 0.61803398875, 1.0) * 0.82
		var x_seed := fmod(fi * 0.754877666, 1.0)
		var y_seed := fmod(fi * 0.569840296, 1.0)
		var fall_speed := lerpf(330.0, 1120.0, depth)
		var streak_length := lerpf(7.0, 36.0, depth)
		var travel_y := fmod(y_seed * (size.y + 120.0) + elapsed_t * fall_speed, size.y + 120.0) - 60.0
		var travel_x := fmod(x_seed * (size.x + 160.0) + elapsed_t * wind * depth + travel_y * 0.055, size.x + 160.0) - 80.0
		var alpha := lerpf(0.055, 0.30, depth) * intensity
		var width := lerpf(0.55, 1.65, depth)
		var end := Vector2(travel_x - streak_length * 0.20, travel_y + streak_length)
		draw_line(Vector2(travel_x, travel_y), end, Color(rain_color, alpha), width, true)

	# A few slow windshield beads add a close focal layer without obscuring play.
	if not wiped:
		var bead_count := 8 if heavy else 5
		for i in range(bead_count):
			var fi := float(i + 1)
			var radius := 1.8 + fmod(fi * 2.37, 3.2)
			var x := fmod(fi * 173.3, size.x * 0.86) + size.x * 0.07
			var y := fmod(fi * 91.7 + elapsed_t * (8.0 + fi), size.y * 0.78) + size.y * 0.06
			draw_circle(Vector2(x, y), radius, Color(0.82, 0.91, 1.0, 0.10 * intensity), false, 0.8, true)


# Fast horizontal streaks and tumbling debris flowing hard in the push
# direction, plus a directional arrow - all growing bolder as the gust nears
# resolution, as a visual countdown to "counter now or get shoved,"
# independent of the car's own cosmetic sway.
func _draw_wind_overlay(size: Vector2) -> void:
	var progress: float = 1.0 - wind_gust_t / WIND_GUST_DURATION
	var intensity: float = lerpf(0.4, 1.0, progress)
	var dir := wind_direction
	var wind_color := Color(0.78, 0.92, 1.0)

	for i in range(40):
		var fi := float(i)
		var depth := 0.15 + fmod(fi * 0.61803398875, 1.0) * 0.85
		var y_seed := fmod(fi * 0.754877666, 1.0)
		var speed := lerpf(480.0, 1300.0, depth) * dir
		var length := lerpf(50.0, 150.0, depth)
		var y := y_seed * size.y * 0.85 + size.y * 0.08
		var travel_x := fmod(elapsed_t * speed + fi * 137.0, size.x + length * 2.0) - length
		if dir < 0.0:
			travel_x = size.x - travel_x
		var alpha := lerpf(0.12, 0.55, depth) * intensity
		var end := Vector2(travel_x + length * dir, y)
		draw_line(Vector2(travel_x, y), end, Color(wind_color, alpha), lerpf(1.8, 4.2, depth), true)

	# Tumbling debris (dust/grit flecks) gives the streaks physical weight
	# instead of reading as pure light rays.
	var debris_color := Color(0.88, 0.84, 0.74)
	for i in range(18):
		var fi := float(i) + 0.5
		var depth := 0.2 + fmod(fi * 0.4539, 1.0) * 0.8
		var y_seed := fmod(fi * 0.9182, 1.0)
		var speed := lerpf(520.0, 1150.0, depth) * dir
		var y_base := y_seed * size.y * 0.82 + size.y * 0.1
		var bob := sin(elapsed_t * lerpf(9.0, 14.0, depth) + fi) * lerpf(4.0, 12.0, depth)
		var travel_x := fmod(elapsed_t * speed + fi * 211.0, size.x + 80.0) - 40.0
		if dir < 0.0:
			travel_x = size.x - travel_x
		var radius := lerpf(1.6, 3.6, depth)
		var alpha := lerpf(0.25, 0.7, depth) * intensity
		draw_circle(Vector2(travel_x, y_base + bob), radius, Color(debris_color, alpha), true, -1.0, true)

	var arrow_alpha := lerpf(0.45, 1.0, progress)
	var arrow_scale := lerpf(1.0, 1.6, progress)
	var cx := size.x * 0.5
	var ay := size.y * 0.10
	var arrow_w := 46.0 * arrow_scale
	var tip := Vector2(cx + dir * arrow_w * 0.5, ay)
	var tail_a := Vector2(cx - dir * arrow_w * 0.5, ay - 14.0 * arrow_scale)
	var tail_b := Vector2(cx - dir * arrow_w * 0.5, ay + 14.0 * arrow_scale)
	draw_colored_polygon(PackedVector2Array([tip, tail_a, tail_b]), Color(wind_color, arrow_alpha))


func _draw_slick_status_overlay(size: Vector2) -> void:
	var strength: float = clampf(slide_t / SLICK_SLIDE_DURATION, 0.0, 1.0)
	var pulse: float = 0.65 + sin(elapsed_t * 12.0) * 0.15
	var edge_color := Color(1.0, 0.38, 0.08, 0.10 * strength * pulse)
	draw_rect(Rect2(0.0, 0.0, size.x * 0.055, size.y), edge_color)
	draw_rect(Rect2(size.x * 0.945, 0.0, size.x * 0.055, size.y), edge_color)
	for i in range(9):
		var fi := float(i)
		var y := size.y * (0.2 + fi * 0.075)
		var sway := sin(elapsed_t * 10.0 + fi * 0.9) * size.x * 0.035
		draw_line(Vector2(size.x * 0.42 + sway, y), Vector2(size.x * 0.58 + sway, y + 7.0), Color(1.0, 0.7, 0.24, 0.11 * strength), 2.0, true)


func _draw_emp_status_overlay(size: Vector2) -> void:
	var max_duration := EMP_DURATION * (0.3 if _has_part("faraday_coil") else 1.0)
	var strength: float = clampf(emp_t / max_duration, 0.0, 1.0)
	var flicker: float = 0.55 + 0.45 * abs(sin(elapsed_t * 31.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.55, 0.9, 0.045 * strength * flicker))
	for i in range(8):
		var y := fmod(float(i) * size.y * 0.173 + elapsed_t * 190.0, size.y)
		var segment_x := fmod(float(i * 97) + elapsed_t * 73.0, size.x * 0.42)
		draw_rect(Rect2(segment_x, y, size.x * 0.34, 2.0), Color(0.22, 0.9, 1.0, 0.12 * strength * flicker))


func _draw_coin_item(coin: Dictionary) -> void:
	var pos := Vector2(lane_x(coin["lane"], coin["p"]), row_y(coin["p"]))
	var scale := scale_at(coin["p"])
	_draw_coin(pos, scale)


func _draw_vgrad(rect: Rect2, c_top: Color, c_bottom: Color, steps: int = 16) -> void:
	var step_h: float = rect.size.y / float(steps)
	for i in range(steps):
		var tt: float = float(i) / float(max(steps - 1, 1))
		var col := c_top.lerp(c_bottom, tt)
		draw_rect(Rect2(rect.position.x, rect.position.y + i * step_h, rect.size.x, step_h + 1.0), col)


func _draw_fog() -> void:
	var density: float = active_level.fog_density
	if _has_part("nightvision_visor"):
		density *= 0.5
	if density <= 0.0:
		return
	var h := get_h()
	var fog_bottom: float = h * FOG_MAX_COVERAGE * density
	var feather: float = h * FOG_FEATHER * density
	var top_color := active_level.fog_color
	top_color.a = FOG_MAX_ALPHA * density
	var bottom_color := active_level.fog_color
	bottom_color.a = 0.0
	_draw_vgrad(Rect2(0.0, 0.0, get_w(), fog_bottom + feather), top_color, bottom_color, 24)


func _draw_dashed_line(p1: Vector2, p2: Vector2, color: Color, width: float, dash: float, gap: float, offset: float) -> void:
	var dir: Vector2 = p2 - p1
	var length := dir.length()
	if length <= 0.0:
		return
	dir = dir / length
	var pattern := dash + gap
	var pos := fmod(-offset, pattern)
	if pos < 0.0:
		pos += pattern
	while pos < length:
		var seg_start: float = maxf(pos, 0.0)
		var seg_end: float = minf(pos + dash, length)
		if seg_end > seg_start:
			draw_line(p1 + dir * seg_start, p1 + dir * seg_end, color, width)
		pos += pattern


func _draw_road() -> void:
	var w := get_w()
	var h := get_h()
	var hy := horizon_y()
	var cx := center_x()

	_draw_city_background(w, h)

	var top_half := half_width_at(0.0)
	var bot_half := half_width_at(1.0)

	# One uniform asphalt surface across all five lanes. Keeping the fill
	# edge-to-edge prevents the outer lanes from appearing shadowed.
	var poly := PackedVector2Array([
		Vector2(cx - top_half, hy), Vector2(cx + top_half, hy),
		Vector2(cx + bot_half, h), Vector2(cx - bot_half, h),
	])
	draw_colored_polygon(poly, Color8(0x3a, 0x3f, 0x50))

	for i in range(1, LANES):
		var frac: float = LANE_EDGES[i]
		var x0: float = cx + frac * half_width_at(0.0)
		var x1: float = cx + frac * half_width_at(1.0)
		_draw_dashed_line(Vector2(x0, hy), Vector2(x1, h), Color(1, 1, 1, 0.88), 4.0, 16.0, 15.0, 0.0)

	draw_line(Vector2(cx - top_half, hy), Vector2(cx - bot_half, h), Color.WHITE, 4.0)
	draw_line(Vector2(cx + top_half, hy), Vector2(cx + bot_half, h), Color.WHITE, 4.0)
	_draw_moving_guardrails(cx, hy, h)


func _draw_city_background(w: float, h: float) -> void:
	# Cross-fade two gently zooming copies to create a seamless forward-motion
	# parallax loop. The slight steering offset makes the skyline respond to the
	# car without exposing the texture edges.
	var phase: float = fmod(road_scroll / 1600.0, 1.0)
	var lane_offset: float = (player_lane_visual - float((LANES - 1) / 2)) * -6.0
	var max_zoom := 0.08
	var zoom_a: float = 1.0 + max_zoom * phase
	var zoom_b: float = 1.0 - max_zoom + max_zoom * phase
	_draw_city_layer(w, h, zoom_a, lane_offset, 1.0 - phase)
	_draw_city_layer(w, h, zoom_b, lane_offset, phase)


func _draw_city_layer(w: float, h: float, zoom: float, x_offset: float, alpha: float) -> void:
	if background_texture == null:
		return
	var size := Vector2(w, h) * zoom
	var pos := Vector2((w - size.x) * 0.5 + x_offset, (h - size.y) * 0.5)
	draw_texture_rect(background_texture, Rect2(pos, size), false, Color(1.0, 1.0, 1.0, alpha))


func _lane_visual_rotation(lane_index: float, p: float) -> float:
	var normalized_lane: float = lane_fraction(lane_index) / 0.8
	var depth: float = clampf(ease_p(p), 0.0, 1.0)
	return -normalized_lane * MAX_LANE_VISUAL_ROTATION * lerpf(0.18, 1.0, depth)


func _depth_tint(p: float) -> Color:
	# Distant objects pick up a subtle cool atmospheric haze, then regain
	# full contrast as they approach the camera.
	var depth: float = clampf(ease_p(p), 0.0, 1.0)
	return Color(
		lerpf(0.74, 1.0, depth),
		lerpf(0.84, 1.0, depth),
		1.0,
		lerpf(0.76, 1.0, depth)
	)


func _draw_road_shadow(pos: Vector2, rendered_size: Vector2, p: float, strength: float) -> void:
	var depth: float = clampf(ease_p(p), 0.0, 1.0)
	var shadow_center := pos + Vector2(0.0, rendered_size.y * 0.22)
	var radius_x: float = rendered_size.x * lerpf(0.25, 0.34, depth)
	var radius_y: float = rendered_size.y * lerpf(0.055, 0.09, depth)
	var alpha: float = strength * lerpf(0.35, 1.0, depth)
	draw_colored_polygon(_ellipse_points(shadow_center, radius_x, radius_y, 20), Color(0.01, 0.015, 0.025, alpha))


func _draw_sprite_on_road(texture: Texture2D, pos: Vector2, scale: float, p: float, rotation: float = 0.0, shadow_strength: float = 0.0, vertical_scale: float = 1.0, tint: Color = Color.WHITE) -> void:
	var size: Vector2 = texture.get_size() * scale
	size.y *= vertical_scale
	if shadow_strength > 0.0:
		_draw_road_shadow(pos, size, p, shadow_strength)
	draw_set_transform(pos, rotation, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-size * 0.5, size), false, _depth_tint(p) * tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _angle_frame_for_lane(lane_index: float) -> int:
	return clampi(int(round(lane_index)), 0, VEHICLE_ANGLE_FRAME_COUNT - 1)


func _draw_angle_sprite_on_road(sheet: Texture2D, frame_index: int, pos: Vector2, scale: float, p: float, shadow_strength: float = 0.0, vertical_scale: float = 1.0, rotation: float = 0.0, tint: Color = Color.WHITE) -> void:
	var frame_width: float = sheet.get_width() / float(VEHICLE_ANGLE_FRAME_COUNT)
	var frame_size := Vector2(frame_width, float(sheet.get_height()))
	var rendered_size: Vector2 = frame_size * scale
	rendered_size.y *= vertical_scale
	if shadow_strength > 0.0:
		_draw_road_shadow(pos, rendered_size, p, shadow_strength)
	var source := Rect2(Vector2(frame_width * frame_index, 0.0), frame_size)
	draw_set_transform(pos, rotation, Vector2.ONE)
	draw_texture_rect_region(sheet, Rect2(-rendered_size * 0.5, rendered_size), source, _depth_tint(p) * tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sprite_centered(texture: Texture2D, pos: Vector2, scale: float) -> void:
	var size: Vector2 = texture.get_size() * scale
	draw_texture_rect(texture, Rect2(pos - size * 0.5, size), false)


func _draw_obstacle(obstacle: Dictionary) -> void:
	var p: float = obstacle["p"]
	var lane: float = float(obstacle["lane"])
	var pos := Vector2(lane_x(lane, p), row_y(p))
	var visual_scale: float = scale_at(p)
	var rotation: float = _lane_visual_rotation(lane, p)
	var depth: float = clampf(ease_p(p), 0.0, 1.0)
	var tint := Color.WHITE
	var launched := bool(obstacle.get("turbo_launched", false))
	if launched:
		var launch_progress: float = 1.0 - float(obstacle["launch_t"]) / float(obstacle["launch_duration"])
		var direction: float = float(obstacle["launch_direction"])
		var viewport_size := get_viewport_rect().size
		pos += Vector2(direction * viewport_size.x * 0.48 * ease(launch_progress, 0.65), -sin(launch_progress * PI) * viewport_size.y * 0.20)
		rotation += float(obstacle["launch_spin"]) * launch_progress
		visual_scale *= lerpf(1.0, 0.58, launch_progress)
		tint.a = 1.0 - smoothstep(0.58, 1.0, launch_progress)
	if obstacle["kind"] == "hazard":
		var variant: int = int(obstacle["variant"])
		var flatness: float = lerpf(0.58, 0.92, depth) if variant == 0 else lerpf(0.88, 1.0, depth)
		var shadow: float = 0.0 if launched or variant == 0 else 0.25
		_draw_sprite_on_road(HAZARD_TEXTURES[variant], pos, visual_scale * HAZARD_DRAW_SCALES[variant], p, rotation, shadow, flatness, tint)
	elif obstacle["kind"] == "slick":
		var flatness: float = lerpf(0.58, 0.92, depth)
		_draw_sprite_on_road(TEX_OIL_SLICK, pos, visual_scale * SLICK_DRAW_SCALE, p, rotation, 0.0, flatness, tint)
		_draw_slick_shimmer(pos, visual_scale, rotation, flatness, tint.a)
	elif obstacle["kind"] == "emp":
		var flatness: float = lerpf(0.65, 0.95, depth)
		_draw_sprite_on_road(TEX_EMP_ZONE, pos, visual_scale * EMP_DRAW_SCALE, p, rotation, 0.18, flatness, tint)
		_draw_emp_hazard_energy(pos, visual_scale, rotation, flatness, tint.a)
	else:
		var car_flatness: float = lerpf(0.88, 1.0, depth)
		_draw_angle_sprite_on_road(TRAFFIC_ANGLE_SHEETS[obstacle["variant"]], _angle_frame_for_lane(lane), pos, visual_scale * HD_VEHICLE_SCALE, p, 0.0 if launched else 0.32, car_flatness, rotation if launched else 0.0, tint)


func _draw_slick_shimmer(pos: Vector2, visual_scale: float, rotation: float, flatness: float, alpha_scale: float) -> void:
	var phase: float = elapsed_t * 2.4
	var half_width: float = 58.0 * visual_scale
	draw_set_transform(pos, rotation, Vector2(1.0, flatness))
	var colors: Array[Color] = [Color(0.15, 0.82, 1.0, 0.32), Color(0.78, 0.3, 1.0, 0.25), Color(1.0, 0.58, 0.12, 0.22)]
	for band in range(3):
		var points: PackedVector2Array = PackedVector2Array()
		for point in range(11):
			var ratio: float = float(point) / 10.0
			var x: float = lerpf(-half_width, half_width, ratio)
			var y: float = (float(band) - 1.0) * 16.0 * visual_scale + sin(ratio * TAU * 1.5 + phase + float(band)) * 5.0 * visual_scale
			points.append(Vector2(x, y))
		var color: Color = colors[band]
		color.a *= alpha_scale
		draw_polyline(points, color, maxf(1.0, 2.5 * visual_scale), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_emp_hazard_energy(pos: Vector2, visual_scale: float, rotation: float, flatness: float, alpha_scale: float) -> void:
	var pulse: float = 0.5 + 0.5 * sin(elapsed_t * 7.5)
	var radius: float = 62.0 * visual_scale
	draw_set_transform(pos, rotation, Vector2(1.0, flatness))
	for ring in range(2):
		var ring_radius := radius * (0.72 + float(ring) * 0.22 + pulse * 0.06)
		var ring_alpha := (0.30 - float(ring) * 0.09) * alpha_scale
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 32, Color(0.12, 0.78, 1.0, ring_alpha), maxf(1.0, (3.0 - ring) * visual_scale), true)
	var orbit_phase := elapsed_t * 2.8
	for i in range(6):
		var angle := orbit_phase + TAU * float(i) / 6.0
		var node_pos := Vector2(cos(angle), sin(angle)) * radius * 0.82
		draw_circle(node_pos, maxf(1.5, 4.0 * visual_scale), Color(0.72, 0.96, 1.0, 0.72 * alpha_scale))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sky(w: float, hy: float) -> void:
	_draw_vgrad(Rect2(0, 0, w, hy), Color8(0x5e, 0xc8, 0xea), Color8(0xbf, 0xe9, 0xf5))
	for seed in cloud_seeds:
		var drift: float = fmod(seed["x"] * w + elapsed_t * 6.0, w + 160.0) - 80.0
		var cy: float = hy * seed["y"]
		var s: float = seed["scale"]
		_draw_cloud(Vector2(drift, cy), s)


func _draw_cloud(pos: Vector2, s: float) -> void:
	var col := Color(1, 1, 1, 0.9)
	draw_circle(pos, 16.0 * s, col)
	draw_circle(pos + Vector2(16.0 * s, 3.0 * s), 12.0 * s, col)
	draw_circle(pos + Vector2(-15.0 * s, 4.0 * s), 11.0 * s, col)
	draw_circle(pos + Vector2(4.0 * s, -6.0 * s), 10.0 * s, col)


func _draw_scenery(w: float, h: float, hy: float, cx: float) -> void:
	# Ocean band beyond the road on both sides, from the horizon down.
	_draw_vgrad(Rect2(0, hy, w, h - hy), Color8(0x1f, 0xa8, 0xc9), Color8(0x0d, 0x6f, 0x8c))
	for i in range(10):
		var yy: float = hy + (h - hy) * (float(i) / 10.0)
		var wobble: float = sin(elapsed_t * 1.5 + i) * 4.0
		draw_line(Vector2(0, yy + wobble), Vector2(w, yy - wobble), Color(1, 1, 1, 0.10), 2.0)

	for seed in rock_seeds:
		var side: float = seed["side"]
		var s: float = seed["scale"]
		var rx: float = cx + side * w * seed["x"]
		var ry: float = hy - 2.0
		var pts := PackedVector2Array([
			Vector2(rx - 22.0 * s, ry), Vector2(rx - 6.0 * s, ry - 30.0 * s),
			Vector2(rx + 10.0 * s, ry - 14.0 * s), Vector2(rx + 24.0 * s, ry),
		])
		draw_colored_polygon(pts, Color8(0x6b, 0x53, 0x3c))


func _guardrail_point(cx: float, hy: float, h: float, p: float, side: float, outward: float = 0.0) -> Vector2:
	var perspective: float = ease_p(p)
	var gap: float = lerpf(7.0, 24.0, perspective)
	var x: float = cx + side * (half_width_at(p) + gap + outward)
	var y: float = lerpf(hy, h, perspective)
	return Vector2(x, y)


func _draw_moving_guardrails(cx: float, hy: float, h: float) -> void:
	const RAIL_SEGMENTS := 28
	const POST_COUNT := 13
	const POST_SCROLL_DISTANCE := 230.0
	var phase: float = fmod(road_scroll / POST_SCROLL_DISTANCE, 1.0)

	for side in [-1.0, 1.0]:
		for i in range(RAIL_SEGMENTS):
			var p0: float = float(i) / RAIL_SEGMENTS
			var p1: float = float(i + 1) / RAIL_SEGMENTS
			var perspective: float = ease_p((p0 + p1) * 0.5)
			var width: float = lerpf(2.5, 9.0, perspective)
			var a0: Vector2 = _guardrail_point(cx, hy, h, p0, side)
			var a1: Vector2 = _guardrail_point(cx, hy, h, p1, side)
			var b0: Vector2 = _guardrail_point(cx, hy, h, p0, side, lerpf(5.0, 16.0, ease_p(p0)))
			var b1: Vector2 = _guardrail_point(cx, hy, h, p1, side, lerpf(5.0, 16.0, ease_p(p1)))
			draw_line(a0, a1, Color8(0x08, 0x3b, 0x57), width + 3.0, true)
			draw_line(a0, a1, Color8(0x54, 0xe8, 0xe0), width, true)
			draw_line(b0, b1, Color8(0x05, 0x2d, 0x48), maxf(2.0, width * 0.72) + 2.0, true)
			draw_line(b0, b1, Color8(0x2b, 0xb9, 0xc7), maxf(2.0, width * 0.72), true)

		for i in range(POST_COUNT):
			var p: float = fmod(float(i) / POST_COUNT + phase, 1.0)
			var perspective: float = ease_p(p)
			var scale: float = lerpf(0.38, 1.45, perspective)
			var top: Vector2 = _guardrail_point(cx, hy, h, p, side, lerpf(2.0, 8.0, perspective))
			var bottom: Vector2 = top + Vector2(side * 3.0 * scale, 17.0 * scale)
			draw_line(top, bottom, Color8(0x03, 0x25, 0x38), 7.0 * scale, true)
			draw_line(top, bottom, Color8(0x35, 0xc9, 0xc7), 4.2 * scale, true)
			var reflector_size: Vector2 = Vector2(5.0, 9.0) * scale
			var reflector_pos: Vector2 = bottom - reflector_size * 0.5
			draw_rect(Rect2(reflector_pos, reflector_size), Color8(0x45, 0x24, 0x08), true)
			draw_rect(Rect2(reflector_pos + reflector_size * 0.18, reflector_size * 0.64), Color8(0xff, 0xb0, 0x18), true)


func _ellipse_points(center: Vector2, rx: float, ry: float, segments: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = (float(i) / segments) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_round_rect(rect: Rect2, color: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	draw_style_box(sb, rect)


func _draw_car(pos: Vector2, scale: float, color: Color) -> void:
	var w: float = 46.0 * scale
	var h: float = 74.0 * scale
	draw_set_transform(pos, 0.0, Vector2.ONE)

	draw_colored_polygon(_ellipse_points(Vector2(0, h * 0.44), w * 0.58, h * 0.15), Color(0, 0, 0, 0.38))

	# Base coat, then a darker lower half for body-side shading and a
	# bright top-down specular streak, so the paint reads as glossy
	# rather than a single flat fill.
	_draw_round_rect(Rect2(-w / 2.0, -h / 2.0, w, h), color, w * 0.28)
	var shade := color.darkened(0.35)
	shade.a = 0.55
	_draw_round_rect(Rect2(-w / 2.0, h * 0.05, w, h * 0.45), shade, w * 0.24)
	var gloss_pts := PackedVector2Array([
		Vector2(-w * 0.16, -h / 2.0 + h * 0.05), Vector2(w * 0.10, -h / 2.0 + h * 0.05),
		Vector2(w * 0.04, h / 2.0 - h * 0.08), Vector2(-w * 0.10, h / 2.0 - h * 0.08),
	])
	draw_colored_polygon(gloss_pts, Color(1, 1, 1, 0.22))

	_draw_round_rect(Rect2(-w / 2.0 + w * 0.14, -h / 2.0 + h * 0.18, w * 0.72, h * 0.32), Color(0.55, 0.75, 0.92, 0.9), w * 0.16)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w / 2.0 + w * 0.16, -h / 2.0 + h * 0.19), Vector2(-w / 2.0 + w * 0.4, -h / 2.0 + h * 0.19),
		Vector2(-w / 2.0 + w * 0.28, -h / 2.0 + h * 0.46), Vector2(-w / 2.0 + w * 0.16, -h / 2.0 + h * 0.46),
	]), Color(1, 1, 1, 0.5))

	draw_rect(Rect2(-w / 2.0 + w * 0.08, -h / 2.0 - 2.0, w * 0.18, 5.0 * scale), Color8(0xff, 0xe0, 0x66))
	draw_rect(Rect2(w / 2.0 - w * 0.26, -h / 2.0 - 2.0, w * 0.18, 5.0 * scale), Color8(0xff, 0xe0, 0x66))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_coin(pos: Vector2, scale: float) -> void:
	var spin: float = 0.68 + 0.32 * abs(sin(elapsed_t * 5.0 + pos.x * 0.03))
	var size := TEX_COIN.get_size() * (scale * COIN_DRAW_SCALE)
	size.x *= spin
	draw_texture_rect(TEX_COIN, Rect2(pos - size * 0.5, size), false)


# Quick colored ring expanding from a world position - shared by coin
# pickups (gold) and near-misses (teal). No dedicated sparkle asset exists
# for either yet, so this stays procedural.
func _draw_spark_fx(fx: Dictionary) -> void:
	var t: float = 1.0 - fx["t"] / fx["duration"]
	var radius: float = lerp(4.0, 26.0, t) * fx["scale"]
	var alpha: float = 1.0 - t
	var col: Color = fx["color"]
	col.a = alpha * 0.9
	draw_arc(fx["pos"], radius, 0.0, TAU, 20, col, 3.0 * fx["scale"], true)


func _draw_coin_loss_fx(fx: Dictionary) -> void:
	var progress: float = 1.0 - fx["t"] / fx["duration"]
	var direction: float = -1.0 if int(fx["index"]) % 2 == 0 else 1.0
	var effect_scale: float = float(fx["scale"])
	var spread: float = (34.0 + 12.0 * int(fx["index"])) * effect_scale
	var offset: Vector2 = Vector2(direction * spread * progress, (-72.0 * progress + 64.0 * progress * progress) * effect_scale)
	var alpha: float = clampf(1.0 - progress, 0.0, 1.0)
	var size: Vector2 = TEX_COIN.get_size() * (effect_scale * COIN_DRAW_SCALE * 0.78)
	draw_texture_rect(TEX_COIN, Rect2(fx["pos"] + offset - size * 0.5, size), false, Color(1.0, 0.62, 0.48, alpha))


func _draw_finish_tape(p: float) -> void:
	var scale := scale_at(p)
	var cx := center_x()

	# The checkers are drawn as a perspective-correct trapezoid spanning a
	# thin slice of depth (p0..p1) rather than a flat rectangle, so its near
	# and far edges each hug the road's own width at that depth instead of
	# overhanging it once the stripe gets thick.
	var half_pt: float = FINISH_STRIPE_P_THICKNESS * 0.5
	var p0: float = maxf(0.0, p - half_pt)
	var p1: float = p + half_pt
	var y0 := row_y(p0)
	var y1 := row_y(p1)
	# Match the width of the road polygon at these exact screen rows. The road
	# reaches its full bottom width at the viewport bottom, while row_y(1.0)
	# is the player's 80%-height row; half_width_at(p) therefore overestimated
	# the stripe width near the player and let its corners hang past the edges.
	var hw0 := road_half_width_at_y(y0)
	var hw1 := road_half_width_at_y(y1)

	var gcols := 20
	for i in range(gcols):
		var t0: float = float(i) / gcols
		var t1: float = float(i + 1) / gcols
		var quad := PackedVector2Array([
			Vector2(cx - hw0 + t0 * hw0 * 2.0, y0), Vector2(cx - hw0 + t1 * hw0 * 2.0, y0),
			Vector2(cx - hw1 + t1 * hw1 * 2.0, y1), Vector2(cx - hw1 + t0 * hw1 * 2.0, y1),
		])
		var gcol: Color = Color8(0x14, 0x14, 0x17) if i % 2 == 0 else Color8(0xf2, 0xf2, 0xf2)
		draw_colored_polygon(quad, gcol)

	var outline := PackedVector2Array([
		Vector2(cx - hw0, y0), Vector2(cx + hw0, y0), Vector2(cx + hw1, y1), Vector2(cx - hw1, y1), Vector2(cx - hw0, y0),
	])
	draw_polyline(outline, Color(0, 0, 0, 0.45), 1.5 * scale)


# Approved twin-exhaust-flame sprite (already a matched left/right pair in
# one image) anchored just behind the player's rear, scaled off the car's
# own perspective scale so it shrinks/grows with the car.
const FLAME_TEX_SCALE := 0.34


func _draw_flame_trail(pos: Vector2, scale: float, t: float, rotation: float = 0.0) -> void:
	var flicker: float = 0.94 + 0.06 * sin(t * 23.0)
	var size: Vector2 = TEX_TURBO_EXHAUST.get_size() * (FLAME_TEX_SCALE * scale)
	var local_origin := Vector2(0.0, 26.0 * scale)
	draw_set_transform(pos, rotation, Vector2.ONE)
	# Layered tapered jets: soft outer plume, cyan body, white hot core.
	for side in [-1.0, 1.0]:
		var nozzle := Vector2(side * 17.0 * scale, 29.0 * scale)
		var jet_length: float = (85.0 + 12.0 * sin(t * 19.0 + side)) * scale
		for layer in range(3):
			var width: float = (14.0 - layer * 4.0) * scale
			var length: float = jet_length * (1.0 - layer * 0.22)
			var tint: Color = [Color(0.05, 0.45, 1.0, 0.15), Color(0.1, 0.85, 1.0, 0.55), Color(0.85, 0.98, 1.0, 0.9)][layer]
			draw_colored_polygon(PackedVector2Array([nozzle + Vector2(-width, 0), nozzle + Vector2(-width * 0.45, length * 0.65), nozzle + Vector2(0, length), nozzle + Vector2(width * 0.45, length * 0.65), nozzle + Vector2(width, 0)]), tint)
	draw_texture_rect(TEX_TURBO_EXHAUST, Rect2(local_origin - Vector2(size.x * 0.5, 0.0), size), false, Color(0.6, 0.85, 1, flicker * 0.65))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Approved energy-ring sprite, scaled up and faded out over
# TURBO_RING_DURATION - centered on the player so it reads as "bursting
# outward from the car" rather than a generic screen-wide flash.
const RING_TEX_MIN_SCALE := 0.24
const RING_TEX_MAX_SCALE := 1.5

func _draw_turbo_ring(px: float, py: float) -> void:
	var t: float = 1.0 - turbo_ring_t / TURBO_RING_DURATION
	var scale: float = lerp(RING_TEX_MIN_SCALE, RING_TEX_MAX_SCALE, 1.0 - pow(1.0 - t, 3.0))
	var alpha: float = (1.0 - t) * (1.0 - t)
	var size: Vector2 = TEX_TURBO_RING.get_size() * scale
	draw_texture_rect(TEX_TURBO_RING, Rect2(Vector2(px, py) - size * 0.5, size), false, Color(0.55, 0.9, 1.0, alpha))
	# A delayed inner wave makes the ignition read as a forceful double pulse.
	var delayed_t: float = clampf((t - 0.16) / 0.84, 0.0, 1.0)
	var delayed_scale: float = lerpf(0.18, 1.05, 1.0 - pow(1.0 - delayed_t, 3.0))
	var delayed_alpha: float = (1.0 - delayed_t) * 0.72 if t > 0.16 else 0.0
	var delayed_size: Vector2 = TEX_TURBO_RING.get_size() * delayed_scale
	draw_texture_rect(TEX_TURBO_RING, Rect2(Vector2(px, py) - delayed_size * 0.5, delayed_size), false, Color(0.85, 0.98, 1.0, delayed_alpha))


# Approved activation-flash sprite - kept small and quick (TURBO_FLASH_DURATION)
# so the burst reads as a hit of energy without ever covering nearby lanes.
const FLASH_TEX_SCALE := 0.52

func _draw_turbo_flash(px: float, py: float) -> void:
	var t: float = 1.0 - turbo_flash_t / TURBO_FLASH_DURATION
	var scale: float = lerp(0.45, 1.25, t) * FLASH_TEX_SCALE
	var alpha: float = pow(1.0 - t, 1.4)
	var size: Vector2 = TEX_TURBO_FLASH.get_size() * scale
	draw_circle(Vector2(px, py), 54.0 * (1.0 + t), Color(0.45, 0.9, 1.0, alpha * 0.22))
	draw_texture_rect(TEX_TURBO_FLASH, Rect2(Vector2(px, py) - size * 0.5, size), false, Color(0.78, 0.96, 1.0, alpha))


func _draw_turbo_activation_pulse(sz: Vector2, center: Vector2) -> void:
	var t: float = 1.0 - turbo_flash_t / TURBO_FLASH_DURATION
	var strength: float = pow(1.0 - t, 2.2)
	# Brief white-blue exposure kick, followed by radial energy rays.
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.55, 0.9, 1.0, strength * 0.16))
	for i in range(16):
		var angle: float = TAU * float(i) / 16.0
		var direction := Vector2(cos(angle), sin(angle))
		var inner: Vector2 = center + direction * (70.0 + t * 80.0)
		var outer: Vector2 = center + direction * (190.0 + t * 260.0)
		draw_line(inner, outer, Color(0.72, 0.94, 1.0, strength * 0.5), 2.5 * strength + 0.5, true)


# Fast perspective streaks and broad wind ribbons create a visible wind tunnel
# while keeping the center of the road readable.
func _draw_speed_lines(t: float) -> void:
	var w: float = get_w()
	var ignition_boost: float = 1.0 + clampf(turbo_flash_t / TURBO_FLASH_DURATION, 0.0, 1.0) * 0.85
	var origin := Vector2(center_x(), horizon_y())
	var sheet_size: Vector2 = TEX_TURBO_SPEED_LINES.get_size()
	var fit: float = w / sheet_size.x
	for layer in range(SPEED_LINE_LAYERS):
		var phase: float = fposmod(t * SPEED_LINE_CYCLE + float(layer) / float(SPEED_LINE_LAYERS), 1.0)
		# Squared, so a pass crawls while it is still distant and then tears
		# past the camera - the same acceleration the road itself uses.
		var depth: float = phase * phase
		var fade: float = sin(phase * PI) * turbo_visual * ignition_boost * SPEED_LINE_ALPHA
		if fade <= 0.003:
			continue
		var size: Vector2 = sheet_size * fit * lerpf(SPEED_LINE_START_SCALE, SPEED_LINE_END_SCALE, depth)
		draw_texture_rect(TEX_TURBO_SPEED_LINES, Rect2(origin - size * 0.5, size), false,
			Color(1.0, 1.0, 1.0, minf(fade, 1.0)))


func _draw_turbo_edges(sz: Vector2) -> void:
	# Feathered edge light replaces the full-screen orange wash.
	for i in range(16):
		var x: float = float(i) * sz.x * 0.006
		var ignition_boost: float = 1.0 + clampf(turbo_flash_t / TURBO_FLASH_DURATION, 0.0, 1.0) * 0.7
		var alpha: float = pow(1.0 - float(i) / 16.0, 2.0) * 0.18 * turbo_visual * ignition_boost
		var tint := Color(0.04, 0.6, 1.0, alpha)
		draw_rect(Rect2(x, 0, sz.x * 0.006 + 1.0, sz.y), tint)
		draw_rect(Rect2(sz.x - x - sz.x * 0.006, 0, sz.x * 0.006 + 1.0, sz.y), tint)
